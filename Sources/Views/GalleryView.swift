import SwiftUI
import SwiftData
import AVKit

struct GalleryView: View {
    @Environment(\.modelContext) private var modelContext
    var folderManager: FolderManager
    @State private var scannerService = ScannerService()
    @State private var actionService = ActionService()
    @State private var indexService = IndexService()
    @State private var indexStore = IndexStore()

    @Query private var processedFiles: [ProcessedFile]

    @State private var hasAcceptedOnboarding = UserDefaults.standard.bool(forKey: "HasAcceptedOnboarding")
    @State private var flowStage: FlowStage = .indexingOptions
    @State private var indexOptions = IndexOptions()
    @State private var selectedCluster: MediaCluster?
    @State private var indexingTask: Task<Void, Never>?
    @State private var showExitConfirmation = false
    @State private var activeSavedIndexID: UUID?
    @State private var indexOpenError: String?

    private enum FlowStage {
        case indexingOptions
        case indexing
        case clusters
        case slicingFullFolder
        case slicingCluster
    }

    /// The titlebar shows the path to the current folder (plain text, centered,
    /// inline with the window controls) only when media is open — terminal-style.
    private var windowTitle: String {
        guard hasAcceptedOnboarding,
              !folderManager.selectedFolders.isEmpty,
              let url = scannerService.selectedURL else { return "" }
        return url.deletingLastPathComponent().abbreviatedTildePath
    }

    var body: some View {
        ZStack {
            Color.themeBackground.edgesIgnoringSafeArea(.all)

            if !hasAcceptedOnboarding {
                OnboardingView {
                    UserDefaults.standard.set(true, forKey: "HasAcceptedOnboarding")
                    hasAcceptedOnboarding = true
                }
            } else if folderManager.selectedFolders.isEmpty {
                FolderSelectionView(
                    folderManager: folderManager,
                    indexStore: indexStore,
                    onOpenIndex: openSavedIndex
                )
            } else {
                activeFolderView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        if let window = NSApp.windows.first {
                            window.center()
                        }
                    }
            }
        }
        .background(WindowConfigurator())
        .overlay(alignment: .top) {
            WindowDragRegion()
                .frame(height: 30)
                .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .top) {
            if !windowTitle.isEmpty {
                Text(windowTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.themeSecondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 90) // keep clear of the traffic lights
                    .frame(height: 28)
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
            }
        }
        .alert("Close folder?", isPresented: $showExitConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Close Folder", role: .destructive) {
                completeReturnToMenu()
            }
        } message: {
            Text("Your saved index will remain available. Any staged deletions will be moved to Trash on exit/menu.")
        }
        .alert("Could Not Open Index", isPresented: Binding(
            get: { indexOpenError != nil },
            set: { if !$0 { indexOpenError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(indexOpenError ?? "Unknown error")
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    @ViewBuilder
    private var activeFolderView: some View {
        switch flowStage {
        case .indexingOptions:
            IndexingOptionsView(
                options: $indexOptions,
                folderCount: folderManager.selectedFolders.count,
                onStart: startIndexing,
                onSkip: {
                    selectedCluster = nil
                    flowStage = .slicingFullFolder
                },
                onBack: closeFolderWithoutConfirmation
            )

        case .indexing:
            IndexingProgressView(
                scannerService: scannerService,
                indexService: indexService,
                onRetry: startIndexing,
                onBackToOptions: returnToIndexingOptions,
                onSkipToFullFolder: skipToFullFolderSlicer,
                onCloseFolder: requestReturnToMenu
            )

        case .clusters:
            ClusterCanvasView(
                clusters: indexService.clusters,
                indexService: indexService,
                onSlice: { cluster in
                    selectedCluster = cluster
                    flowStage = .slicingCluster
                },
                onSliceFullFolder: skipToFullFolderSlicer,
                onBackToOptions: returnToIndexingOptions,
                onCloseFolder: requestReturnToMenu,
                processedPaths: Set(processedFiles.map { $0.filePath }),
                onMoveCluster: { _, _ in
                    persistActiveIndexLayout()
                }
            )

        case .slicingFullFolder:
            MainContentView(
                folderManager: folderManager,
                scannerService: scannerService,
                actionService: actionService,
                processedFiles: processedFiles,
                initialFiles: nil,
                onRequestReturnToMenu: requestReturnToMenu
            )
            .id("full-folder-slicer")

        case .slicingCluster:
            MainContentView(
                folderManager: folderManager,
                scannerService: scannerService,
                actionService: actionService,
                processedFiles: processedFiles,
                initialFiles: selectedCluster?.fileURLs ?? [],
                onRequestReturnToMenu: requestReturnToMenu,
                onRequestBackToClusters: returnToClusters
            )
            .id("cluster-slicer-\(selectedCluster?.id ?? -1)")
        }
    }

    private var requiresExitConfirmation: Bool {
        flowStage == .indexing || AppExitState.hasVolatileIndex || actionService.hasUndoProgress
    }

    private func openSavedIndex(_ summary: SavedIndexSummary) {
        indexingTask?.cancel()
        indexingTask = nil
        actionService.purgeStaged()
        scannerService.clear()
        selectedCluster = nil

        do {
            let result = try indexStore.openIndex(summary)
            folderManager.openSavedIndex(folderRoots: result.folderRoots)
            indexService.load(savedIndex: result.index)
            activeSavedIndexID = result.index.summary.id
            indexOptions = IndexOptions()
            AppExitState.hasVolatileIndex = false
            flowStage = .clusters
        } catch {
            indexOpenError = error.localizedDescription
        }
    }

    private func persistActiveIndexLayout() {
        guard activeSavedIndexID != nil, !folderManager.selectedFolders.isEmpty else { return }
        do {
            let summary = try indexStore.saveIndex(
                folderRoots: folderManager.selectedFolders,
                clusters: indexService.clusters,
                embedderName: indexService.embedderName
            )
            activeSavedIndexID = summary.id
        } catch {
            print("[Mandoline] Failed to persist cluster layout: \(error)")
        }
    }

    private func startIndexing() {
        indexingTask?.cancel()
        selectedCluster = nil
        activeSavedIndexID = nil

        guard indexOptions.semanticClusters else {
            skipToFullFolderSlicer()
            return
        }

        AppExitState.hasVolatileIndex = true
        flowStage = .indexing

        let folders = folderManager.selectedFolders
        let options = indexOptions
        let processedFiles = processedFiles

        indexingTask = Task {
            await scannerService.scan(folders: folders, processedFiles: processedFiles)
            guard !Task.isCancelled else { return }

            await indexService.buildIndex(files: scannerService.mediaFiles, folderRoots: folders, options: options)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                if case .done = indexService.phase {
                    do {
                        let summary = try indexStore.saveIndex(
                            folderRoots: folders,
                            clusters: indexService.clusters,
                            embedderName: indexService.embedderName
                        )
                        activeSavedIndexID = summary.id
                        AppExitState.hasVolatileIndex = false
                        flowStage = .clusters
                    } catch {
                        AppExitState.hasVolatileIndex = true
                        indexService.phase = .failed("Index built but could not be saved: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func returnToIndexingOptions() {
        indexingTask?.cancel()
        indexingTask = nil
        scannerService.clear()
        indexService.clusters = []
        indexService.embedderName = ""
        indexService.phase = .idle
        AppExitState.hasVolatileIndex = false
        selectedCluster = nil
        activeSavedIndexID = nil
        flowStage = .indexingOptions
    }

    private func skipToFullFolderSlicer() {
        indexingTask?.cancel()
        indexingTask = nil
        selectedCluster = nil
        scannerService.clear()
        indexService.phase = .idle
        AppExitState.hasVolatileIndex = false
        flowStage = .slicingFullFolder
    }

    private func returnToClusters() {
        scannerService.clear()
        selectedCluster = nil
        AppExitState.hasVolatileIndex = false
        flowStage = .clusters
    }

    private func requestReturnToMenu() {
        if requiresExitConfirmation {
            showExitConfirmation = true
        } else {
            completeReturnToMenu()
        }
    }

    private func closeFolderWithoutConfirmation() {
        completeReturnToMenu()
    }

    private func completeReturnToMenu() {
        indexingTask?.cancel()
        indexingTask = nil
        actionService.purgeStaged()
        scannerService.clear()
        indexService.cancel()
        indexService.clusters = []
        indexService.embedderName = ""
        indexService.phase = .idle
        AppExitState.hasVolatileIndex = false
        selectedCluster = nil
        activeSavedIndexID = nil
        indexOptions = IndexOptions()
        flowStage = .indexingOptions
        folderManager.clearFolders()
    }
}

private struct IndexingProgressView: View {
    var scannerService: ScannerService
    var indexService: IndexService
    var onRetry: () -> Void
    var onBackToOptions: () -> Void
    var onSkipToFullFolder: () -> Void
    var onCloseFolder: () -> Void

    private var progressValue: Double? {
        if scannerService.isScanning {
            return nil
        }

        switch indexService.phase {
        case let .clipIndexing(_, done?, total?) where total > 0:
            return Double(done) / Double(total)
        case let .embedding(done, total) where total > 0:
            return Double(done) / Double(total)
        case .done:
            return 1
        default:
            return nil
        }
    }

    private var statusText: String {
        if scannerService.isScanning {
            return "Scanning folder for media…"
        }

        switch indexService.phase {
        case .idle:
            return "Preparing index…"
        case .preparing:
            return "Preparing local index…"
        case let .clipIndexing(message, _, _):
            return message
        case let .embedding(done, total):
            return "Embedding media locally (\(done)/\(total))…"
        case .clustering:
            return "Clustering similar media…"
        case .done:
            return "Index complete."
        case let .failed(message):
            return "Indexing failed: \(message)"
        case .cancelled:
            return "Indexing cancelled."
        }
    }

    private var canRecover: Bool {
        if scannerService.isScanning { return false }

        switch indexService.phase {
        case .failed, .cancelled:
            return true
        default:
            return false
        }
    }

    var body: some View {
        CenteredScrollContainer(maxContentWidth: 560) {
            VStack(spacing: 22) {
                Text("Building Local Index")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.themeText)

                Text(statusText)
                    .font(.system(size: 14))
                    .foregroundColor(.themeSecondaryText)
                    .multilineTextAlignment(.center)

                if let progressValue {
                    ProgressView(value: progressValue)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }

                if !indexService.embedderName.isEmpty {
                    Text("Embedder: \(indexService.embedderName)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.themeSecondaryText)
                }

                if canRecover {
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            Button("Retry", action: onRetry)
                                .buttonStyle(.borderedProminent)
                            Button("Back to Options", action: onBackToOptions)
                            Button("Slice Full Folder", action: onSkipToFullFolder)
                        }

                        Button("Close Folder", role: .destructive, action: onCloseFolder)
                    }
                    .padding(.top, 8)
                } else {
                    Button("Close Folder", action: onCloseFolder)
                        .padding(.top, 8)
                }
            }
            .padding(24)
            .cardSurface(cornerRadius: 20, fill: .themeCard)
        }
        .background(Color.themeBackground)
    }
}

struct FolderSelectionView: View {
    private enum LibrarySection: String, CaseIterable, Hashable {
        case recents = "Recents"
        case indexes = "Indexes"
    }

    var folderManager: FolderManager
    var indexStore: IndexStore
    var onOpenIndex: (SavedIndexSummary) -> Void

    @State private var selectedSection: LibrarySection = .recents
    @State private var pendingIndexDelete: SavedIndexSummary?
    @State private var deletionError: String?

    private var displayedIndexes: [SavedIndexSummary] {
        Array(indexStore.savedIndexes.prefix(3))
    }

    var body: some View {
        VStack(spacing: 0) {
            CenteredScrollContainer(maxContentWidth: 560) {
                VStack(spacing: 24) {
                    Text("Welcome to Mandoline")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.themeText)
                        .multilineTextAlignment(.center)
                        .staggeredReveal(0)

                    Text("Pick a folder to scan, or reopen a saved index without rebuilding it.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.themeText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .staggeredReveal(1)

                    Button(action: {
                        folderManager.selectFolder()
                    }) {
                        Text("Choose Folders...")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
                    .staggeredReveal(2)

                    Picker("Library", selection: $selectedSection) {
                        ForEach(LibrarySection.allCases, id: \.self) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                    .staggeredReveal(3)

                    Group {
                        switch selectedSection {
                        case .recents:
                            recentsList
                        case .indexes:
                            indexesList
                        }
                    }
                    .frame(maxWidth: 420)
                    .padding(.top, 2)
                    .staggeredReveal(4)
                }
            }

            StudioCreditLink()
                .padding(.bottom, 20)
                .staggeredReveal(5)
        }
        .background(Color.themeBackground)
        .alert(item: $pendingIndexDelete) { summary in
            Alert(
                title: Text("Delete saved index?"),
                message: Text("This removes Mandoline's cached index metadata for \(summary.displayName). Your media files will not be deleted."),
                primaryButton: .destructive(Text("Delete Index")) {
                    deleteIndex(summary)
                },
                secondaryButton: .cancel()
            )
        }
        .alert("Could Not Delete Index", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deletionError ?? "Unknown error")
        }
    }

    @ViewBuilder
    private var recentsList: some View {
        if folderManager.displayRecents.isEmpty {
            emptyLibraryMessage("No recent folders yet.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Recently Sliced")

                ForEach(folderManager.displayRecents, id: \.self) { url in
                    Button {
                        folderManager.openRecent(url)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "folder")
                                .font(.system(size: 14))
                                .foregroundColor(.themeSecondaryText)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(url.lastPathComponent)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.themeText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(url.abbreviatedTildePath)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(.themeSecondaryText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.themeSecondaryText)
                        }
                    }
                    .buttonStyle(RecentRowButtonStyle())
                    .contextMenu {
                        Button("Remove from Recents", role: .destructive) {
                            folderManager.removeRecent(url)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var indexesList: some View {
        if indexStore.savedIndexes.isEmpty {
            emptyLibraryMessage("No saved indexes yet. Build an index once and it will appear here.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    sectionTitle("Saved Indexes")
                    Spacer()
                    Text("\(indexStore.savedIndexes.count) indexes · \(byteString(indexStore.savedIndexes.reduce(Int64(0)) { $0 + $1.cachedMetadataBytes })) cache")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(.themeSecondaryText)
                }

                ForEach(displayedIndexes) { summary in
                    savedIndexRow(summary)
                }

                if indexStore.savedIndexes.count > displayedIndexes.count {
                    Menu {
                        ForEach(indexStore.savedIndexes) { summary in
                            Button("\(summary.displayName) — \(summary.itemCount) items") {
                                onOpenIndex(summary)
                            }
                        }
                    } label: {
                        Label("View More", systemImage: "ellipsis.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
            }
        }
    }

    private func savedIndexRow(_ summary: SavedIndexSummary) -> some View {
        HStack(spacing: 10) {
            Button {
                onOpenIndex(summary)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 14))
                        .foregroundColor(.themeSecondaryText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.themeText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(indexSubtitle(summary))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundColor(.themeSecondaryText)
                            .lineLimit(1)
                        Text(folderPathSummary(summary))
                            .font(.system(size: 11))
                            .foregroundColor(.themeSecondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.themeSecondaryText)
                }
            }
            .buttonStyle(.plain)

            IndexTrashButton {
                pendingIndexDelete = summary
            }
        }
        .contextMenu {
            Button("Open Index") {
                onOpenIndex(summary)
            }
            Button("Delete Index…", role: .destructive) {
                pendingIndexDelete = summary
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            Color.themeSubtleBackground.opacity(0.55),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.themeSecondaryText)
            .textCase(.uppercase)
            .kerning(0.5)
    }

    private func emptyLibraryMessage(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundColor(.themeSecondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(14)
            .cardSurface(cornerRadius: 12, fill: .themeCard)
    }

    private func deleteIndex(_ summary: SavedIndexSummary) {
        do {
            try indexStore.deleteIndex(summary)
        } catch {
            deletionError = error.localizedDescription
        }
    }

    private func indexSubtitle(_ summary: SavedIndexSummary) -> String {
        "\(summary.clusterCount) clusters · \(summary.itemCount) items · \(byteString(summary.totalMediaBytes)) media · \(byteString(summary.cachedMetadataBytes)) index · \(summary.updatedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func folderPathSummary(_ summary: SavedIndexSummary) -> String {
        guard let first = summary.folderPaths.first else { return "No folder path saved" }
        let abbreviated = URL(fileURLWithPath: first).abbreviatedTildePath
        if summary.folderPaths.count == 1 { return abbreviated }
        return "\(abbreviated) + \(summary.folderPaths.count - 1) more"
    }

    private func byteString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

private struct IndexTrashButton: View {
    var action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(role: .destructive, action: action) {
            Image(systemName: isHovered ? "trash.fill" : "trash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isHovered ? .themeDanger : .themeSecondaryText)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(isHovered ? Color.themeDanger.opacity(0.10) : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 40, height: 40)
        .help("Delete saved index")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

struct HoverLinkButtonStyle: ButtonStyle {
    @State private var isHovered = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isHovered ? .themeText : .themeSecondaryText)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .onHover { hover in
                isHovered = hover
            }
    }
}

/// Footer credit: "Made for everyone by The Applied Research Studio ↗".
/// On hover the studio name darkens and the link-out icon grows with a
/// smooth, bounce-free spring.
struct StudioCreditLink: View {
    @Environment(\.openURL) private var openURL
    @State private var isHovered = false

    private let url = URL(string: "https://thinktars.com")!

    var body: some View {
        HStack(spacing: 5) {
            Text("Made for everyone by")
                .foregroundColor(.themeSecondaryText)

            Button {
                openURL(url)
            } label: {
                HStack(spacing: 3) {
                    Text("The Applied Research Studio")
                        .foregroundColor(isHovered ? .themeText : .themeSecondaryText)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isHovered ? .themeText : .themeSecondaryText)
                        .scaleEffect(isHovered ? 1.2 : 1.0)
                        .offset(x: isHovered ? 1 : 0, y: isHovered ? -1 : 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .onHover { hovering in
                withAnimation(.spring(duration: 0.3, bounce: 0)) {
                    isHovered = hovering
                }
            }
        }
        .font(.system(size: 13, weight: .regular))
    }
}

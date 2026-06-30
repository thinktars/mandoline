import SwiftUI
import SwiftData
import AVKit
import QuickLook
import QuickLookThumbnailing

struct MainContentView: View {
    @Environment(\.modelContext) private var modelContext

    var folderManager: FolderManager
    var scannerService: ScannerService
    var actionService: ActionService
    var processedFiles: [ProcessedFile]
    
    @State private var flashColor: Color = .clear
    @State private var flashOpacity: Double = 0.0
    @State private var showShortcuts: Bool = false
    @State private var isHoveringHelp: Bool = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.themeBackground.edgesIgnoringSafeArea(.all)
            
            if scannerService.isScanning {
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    Text("Scanning media…")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                        .padding(.top)
                }
            } else if let currentMedia = scannerService.selectedURL {
                VStack(spacing: 0) {
                    // MARK: Top bar (its own region — never overlaps the media)
                    // The centered folder name lives in the window titlebar
                    // (principal toolbar item); this row holds file info + controls,
                    // inset to clear the titlebar / traffic lights.
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("[\((scannerService.selectedIndex ?? 0) + 1)/\(scannerService.mediaFiles.count)] \(currentMedia.lastPathComponent)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.themeText)
                                .monospacedDigit()
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(fileSizeString(url: currentMedia))
                                .font(.system(size: 12, weight: .regular))
                                .monospacedDigit()
                                .foregroundColor(.themeSecondaryText)
                        }

                        Spacer(minLength: 16)

                        HStack(spacing: 10) {
                            Button(action: {
                                showShortcuts.toggle()
                            }) {
                                Image(systemName: "questionmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.themeText)
                            }
                            .buttonStyle(CircleIconButtonStyle())
                            .onHover { hover in
                                isHoveringHelp = hover
                            }
                            .onChange(of: isHoveringHelp) { _, new in
                                if new {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                        if self.isHoveringHelp {
                                            self.showShortcuts = true
                                        }
                                    }
                                }
                            }
                            .popover(isPresented: $showShortcuts, arrowEdge: .top) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Shortcuts")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.themeText)
                                        .padding(.bottom, 2)

                                    ShortcutRowView(key: "←", action: "Previous", color: .themeText)
                                    ShortcutRowView(key: "→", action: "Next", color: .themeText)
                                    ShortcutRowView(key: "[", action: "Trash", color: .themeDanger)
                                    ShortcutRowView(key: "]", action: "Keep", color: .themeSuccess)
                                    ShortcutRowView(key: "Z", action: "Undo", color: .themeSecondaryText)
                                    ShortcutRowView(key: "⏎", action: "Reveal in Finder", color: .themeText)
                                    ShortcutRowView(key: "Esc", action: "Menu", color: .themeText)
                                }
                                .padding(16)
                                .frame(width: 220)
                                .cardSurface(cornerRadius: 12, fill: .themeBackground)
                            }

                            Button(action: {
                                returnToMenu()
                            }) {
                                Image(systemName: "door.left.hand.open")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.themeText)
                            }
                            .buttonStyle(CircleIconButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 38)
                    .padding(.bottom, 12)

                    // MARK: Media region (fills remaining space; nothing overlaps it)
                    ZStack {
                        MediaViewer(url: currentMedia)
                            .id(currentMedia) // Force reload on change

                        // Flash overlay confined to the media region.
                        flashColor
                            .opacity(flashOpacity)
                            .allowsHitTesting(false)

                        // Keyboard Event Receiver
                        // IMPORTANT: don't capture `currentMedia`; resolve selection at key-press time.
                        KeyEventHandlingView { event in
                            handleKeyPress(event)
                        }
                        .frame(width: 0, height: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 20)

                    // MARK: Bottom bar (its own region)
                    if !scannerService.mediaFiles.isEmpty {
                        CarouselView(scannerService: scannerService)
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                            .padding(.bottom, 18)
                    }
                }

            } else {
                VStack {
                        HStack {
                            Button(action: {
                                returnToMenu()
                            }) {
                                Image(systemName: "door.left.hand.open")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.themeText)
                            }
                            .buttonStyle(CircleIconButtonStyle())
                            .padding(.horizontal, 20)
                            .padding(.top, 36)
                            .padding(.bottom, 20)
                            
                            Spacer()
                        }
                        
                        Spacer()
                        
                        Text("All Caught Up!")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.primary)
                            .staggeredReveal(0)
                        Text("Nothing left to review here.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.secondary)
                            .padding()
                            .staggeredReveal(1)
                        
                        Button(action: {
                            Task {
                                await scannerService.scan(folders: folderManager.selectedFolders, processedFiles: processedFiles)
                            }
                        }) {
                            Text("Rescan")
                        }
                        .buttonStyle(PillButtonStyle())
                        .staggeredReveal(2)
                        
                        Spacer()
                    }
                }
        }
        .onAppear {
            Task {
                await scannerService.scan(folders: folderManager.selectedFolders, processedFiles: processedFiles)
                scannerService.ensureSelectionValid()
            }
        }
    }
    
    /// Commit staged deletions to the system Trash, then return to the menu.
    private func returnToMenu() {
        actionService.purgeStaged()
        folderManager.clearFolders()
    }

    private func triggerFlash(color: Color) {
        // Simple, non-animated flash.
        flashColor = color
        flashOpacity = 0.35
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            flashOpacity = 0.0
        }
    }
    
    private func handleKeyPress(_ key: String) {
        scannerService.ensureSelectionValid()
        guard let currentMedia = scannerService.selectedURL else { return }

        switch key {
        case "left": // Navigate Prev
            scannerService.selectPrevious()
        case "right": // Navigate Next
            scannerService.selectNext()
        case "[": // Trash
            NSSound(contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif", byReference: true)?.play()
            triggerFlash(color: .themeDanger)
            if actionService.trash(url: currentMedia, roots: folderManager.selectedFolders, context: modelContext) {
                scannerService.removeFromQueue(url: currentMedia)
            } else {
                // Failed to trash; don't advance.
                NSSound(contentsOfFile: "/System/Library/Sounds/Basso.aiff", byReference: true)?.play()
            }
        case "]": // Keep
            triggerFlash(color: .themeSuccess)
            if actionService.keep(url: currentMedia, context: modelContext) {
                scannerService.removeFromQueue(url: currentMedia)
            } else {
                NSSound(contentsOfFile: "/System/Library/Sounds/Basso.aiff", byReference: true)?.play()
            }
        case "z": // Undo
            if let restored = actionService.undo(context: modelContext) {
                triggerFlash(color: .themeBorder)
                scannerService.insertIntoQueue(restored.url)
            } else {
                // Play rejected sound if there's no history left to undo
                NSSound(contentsOfFile: "/System/Library/Sounds/Basso.aiff", byReference: true)?.play()
            }
        case "esc": // Return to menu or close shortcuts
            if showShortcuts {
                showShortcuts = false
            } else {
                returnToMenu()
            }
        case "enter": // Reveal in Finder
            NSWorkspace.shared.activateFileViewerSelecting([currentMedia])
        default:
            break
        }
    }
    
    private func fileSizeString(url: URL) -> String {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = attrs[.size] as? Int64 ?? 0
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useGB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: size)
        } catch {
            return "Unknown size"
        }
    }
}

// MARK: - Subviews

struct CarouselView: View {
    var scannerService: ScannerService
    
    // Strict single row for the carousel
    let rows = [GridItem(.fixed(60), spacing: 8)]
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: rows, spacing: 8) {
                    ForEach(scannerService.mediaFiles, id: \.path) { url in
                        let isActive = (url == scannerService.selectedURL)

                        ThumbnailView(url: url)
                            .frame(width: 80, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(isActive ? Color.themePrimaryAction : Color.black.opacity(0.1), lineWidth: isActive ? 2 : 1)
                            )
                            .id(url.path)
                            .onTapGesture {
                                scannerService.select(url: url)
                            }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .background(Color.themeSubtleBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
            .frame(height: 84)
            .onChange(of: scannerService.selectedURL) { _, newSelection in
                if let newSelection {
                    proxy.scrollTo(newSelection.path, anchor: .center)
                }
            }
            .onAppear {
                if let selected = scannerService.selectedURL {
                    proxy.scrollTo(selected.path, anchor: .center)
                }
            }
        }
    }
}

struct ThumbnailView: View {
    let url: URL
    @State private var image: NSImage?
    
    var body: some View {
        ZStack {
            Color.black
            
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.gray)
            }
        }
        .clipped()
        .task(id: url) {
            await loadThumbnail()
        }
    }
    
    private func loadThumbnail() async {
        let size = CGSize(width: 160, height: 120) // 2x for Retina rendering
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 2.0, representationTypes: .thumbnail)
        
        do {
            let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            await MainActor.run {
                self.image = rep.nsImage
            }
        } catch {
            // Fallback for file types QL doesn't handle natively without extensions
            if let nsImage = NSImage(contentsOf: url) {
                await MainActor.run {
                    self.image = nsImage
                }
            }
        }
    }
}

struct ShortcutRowView: View {
    var key: String
    var action: String
    var color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .frame(minWidth: 32)
                .padding(.vertical, 4)
                .background(Color.themeSubtleBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.themeBorder, lineWidth: 1))
                
            Text(action)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(color)
                
            Spacer()
        }
    }
}

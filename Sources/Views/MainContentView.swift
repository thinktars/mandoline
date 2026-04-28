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
                    Text("Scanning media...")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                        .padding(.top)
                }
            } else if let currentMedia = scannerService.selectedURL {
                MediaViewer(url: currentMedia)
                    .id(currentMedia) // Force reload on change
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 120)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                
                // Flash overlay
                flashColor
                    .opacity(flashOpacity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 120)
                    .allowsHitTesting(false)
                
                // Keyboard Event Receiver
                // IMPORTANT: don't capture `currentMedia` here; always resolve selection at key-press time.
                KeyEventHandlingView { event in
                    handleKeyPress(event)
                }
                .frame(width: 0, height: 0)
                
                VStack {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("[\((scannerService.selectedIndex ?? 0) + 1)/\(scannerService.mediaFiles.count)] \(currentMedia.lastPathComponent)")
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(fileSizeString(url: currentMedia))
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color.themeBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.themeBorder, lineWidth: 1))

                        Spacer()

                        HStack(spacing: 10) {
                            Button(action: {
                                showShortcuts.toggle()
                            }) {
                                Image(systemName: "questionmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.themeText)
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                            .background(Color.themeSubtleBackground, in: Circle())
                            .overlay(Circle().stroke(Color.themeBorder, lineWidth: 1))
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
                                    Text("Keyboard Shortcuts")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.themeText)
                                        .padding(.bottom, 2)

                                    ShortcutRowView(key: "←", action: "Previous Media", color: .themeText)
                                    ShortcutRowView(key: "→", action: "Next Media", color: .themeText)
                                    ShortcutRowView(key: "[", action: "Move to Trash", color: .themeDanger)
                                    ShortcutRowView(key: "]", action: "Keep Media", color: .themeSuccess)
                                    ShortcutRowView(key: "Z", action: "Undo Last", color: .themeBorder)
                                    ShortcutRowView(key: "⏎", action: "Reveal in Finder", color: .themeText)
                                    ShortcutRowView(key: "Esc", action: "Menu", color: .themeText)
                                }
                                .padding(16)
                                .frame(width: 220)
                                .background(Color.themeBackground)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.themeBorder, lineWidth: 1)
                                )
                            }

                            Button(action: {
                                folderManager.clearFolders()
                            }) {
                                Image(systemName: "door.left.hand.open")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.themeText)
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                            .background(Color.themeSubtleBackground, in: Circle())
                            .overlay(Circle().stroke(Color.themeBorder, lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    Spacer()
                }
                
                if !scannerService.mediaFiles.isEmpty {
                    CarouselView(scannerService: scannerService)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)
                }
                
            } else {
                VStack {                        HStack {
                            Button(action: {
                                folderManager.clearFolders()
                            }) {
                                Image(systemName: "door.left.hand.open")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.themeText)
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                            .background(Color.themeSubtleBackground, in: Circle())
                            .overlay(Circle().stroke(Color.themeBorder, lineWidth: 1))
                            .padding(20)
                            
                            Spacer()
                        }
                        
                        Spacer()
                        
                        Text("All Caught Up!")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("No more media to review in the selected folders.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.secondary)
                            .padding()
                        
                        Button(action: {
                            Task {
                                await scannerService.scan(folders: folderManager.selectedFolders, processedFiles: processedFiles)
                            }
                        }) {
                            Text("Rescan Folders")
                                .font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 20)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 10)
                        .background(Color.themeButtonSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.themeBorder, lineWidth: 1)
                        )
                        .foregroundColor(.themeText)
                        .controlSize(.large)
                        
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
                folderManager.clearFolders()
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
            return "Unknown Size"
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
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(isActive ? Color.themePrimaryAction : Color.themeBorder.opacity(0.5), lineWidth: isActive ? 2 : 1)
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
            .background(Color.themeSubtleBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.themeBorder, lineWidth: 1)
            )
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

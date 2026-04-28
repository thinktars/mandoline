import Foundation
import UniformTypeIdentifiers

@Observable
final class ScannerService {
    var mediaFiles: [URL] = []

    /// Finder-like selection: keep selection stable even as the backing array changes.
    /// Keep URLs standardized so equality and ordering behave predictably.
    var selectedURL: URL? = nil

    var isScanning = false

    var selectedIndex: Int? {
        guard let selectedURL else { return nil }
        return mediaFiles.firstIndex(of: selectedURL)
    }

    func ensureSelectionValid() {
        if let selectedURL, mediaFiles.contains(selectedURL) {
            return
        }
        selectedURL = mediaFiles.first
    }

    func selectNext() {
        ensureSelectionValid()
        guard let idx = selectedIndex else { return }
        let next = idx + 1
        if next < mediaFiles.count {
            selectedURL = mediaFiles[next]
        } else {
            // Clamp at the end (Finder-like behavior)
            selectedURL = mediaFiles.last
        }
    }

    func selectPrevious() {
        ensureSelectionValid()
        guard let idx = selectedIndex else { return }
        let prev = idx - 1
        if prev >= 0 {
            selectedURL = mediaFiles[prev]
        }
    }

    func select(url: URL) {
        selectedURL = url.standardizedFileURL
    }

    /// Remove an item from the queue and advance selection like Finder.
    func removeFromQueue(url: URL) {
        let url = url.standardizedFileURL
        guard let removeIndex = mediaFiles.firstIndex(of: url) else { return }

        let wasSelected = (selectedURL == url)

        var newFiles = mediaFiles
        newFiles.remove(at: removeIndex)
        mediaFiles = newFiles

        if mediaFiles.isEmpty {
            selectedURL = nil
            return
        }

        if wasSelected {
            // Keep selection on the next item at the same index if possible, otherwise the previous.
            let newIndex = min(removeIndex, mediaFiles.count - 1)
            selectedURL = mediaFiles[newIndex]
        } else {
            ensureSelectionValid()
        }
    }

    func insertIntoQueue(_ url: URL) {
        let url = url.standardizedFileURL

        var newFiles = mediaFiles
        if !newFiles.contains(url) {
            newFiles.append(url)
            newFiles.sort(by: { $0.path < $1.path })
        }
        mediaFiles = newFiles
        selectedURL = url
    }

    // Allowed extensions
    private let allowedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "webp", "raw", "dng",
        "mp4", "mov", "avi", "mkv", "webm", "m4v"
    ]
    
    func scan(folders: [URL], processedFiles: [ProcessedFile]) async {
        let processedPaths = Set(processedFiles.map { $0.filePath })
        
        await MainActor.run {
            self.isScanning = true
            self.mediaFiles.removeAll()
            self.selectedURL = nil
        }
        
        var newMedia: [URL] = []
        
        for folder in folders {
            guard let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            
            for case let fileURL as URL in enumerator {
                // Yield to keep UI responsive if needed
                await Task.yield()
                
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                    guard resourceValues.isRegularFile == true else { continue }
                    
                    let ext = fileURL.pathExtension.lowercased()
                    if allowedExtensions.contains(ext) {
                        if !processedPaths.contains(fileURL.path) {
                            newMedia.append(fileURL)
                        }
                    }
                } catch {
                    print("Error reading resource values for \(fileURL): \(error)")
                }
            }
        }
        
        // Sort newest first or alphabetically? Let's just shuffle or do randomly for serendipity?
        // Let's sort alphabetically for predictability.
        newMedia.sort(by: { $0.path < $1.path })
        
        let finalMedia = newMedia
        await MainActor.run {
            self.mediaFiles = finalMedia.map { $0.standardizedFileURL }
            self.selectedURL = self.mediaFiles.first
            self.isScanning = false
        }
    }
}

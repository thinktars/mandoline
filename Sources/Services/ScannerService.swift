import Foundation
import UniformTypeIdentifiers

@Observable
final class ScannerService {
    var mediaFiles: [URL] = []

    /// Finder-like selection: keep selection stable even as the backing array changes.
    /// Keep URLs standardized so equality and ordering behave predictably.
    var selectedURL: URL? = nil

    var isScanning = false

    /// Total size of the media currently in the queue. Updated live as items
    /// are trashed or restored.
    var totalBytes: Int64 = 0

    /// Cached per-file sizes (bytes), captured during the scan.
    private var fileSizes: [URL: Int64] = [:]

    /// Identifies the active scan so a cancelled/older task cannot publish over
    /// a newer scan or a cleared folder session.
    private var activeScanID: UUID?

    /// Size of a specific media file, from the scan cache.
    func size(of url: URL) -> Int64 {
        fileSizes[url.standardizedFileURL] ?? 0
    }

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

        totalBytes -= fileSizes[url] ?? 0

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
            let size = fileSizes[url] ?? Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            fileSizes[url] = size
            totalBytes += size
        }
        mediaFiles = newFiles
        selectedURL = url
    }

    func clear() {
        activeScanID = nil
        isScanning = false
        mediaFiles.removeAll()
        selectedURL = nil
        totalBytes = 0
        fileSizes = [:]
    }

    /// Load a precomputed media subset (for example, a semantic cluster) into
    /// the same review queue used by the full-folder scanner.
    func load(files: [URL], processedFiles: [ProcessedFile]) {
        let processedPaths = Set(processedFiles.map { $0.filePath })
        var uniqueFiles: [URL] = []
        var seenPaths: Set<String> = []
        var sizes: [URL: Int64] = [:]

        for file in files {
            let standardized = file.standardizedFileURL
            guard !processedPaths.contains(standardized.path) else { continue }
            guard FileManager.default.fileExists(atPath: standardized.path) else { continue }
            guard allowedExtensions.contains(standardized.pathExtension.lowercased()) else { continue }
            guard !seenPaths.contains(standardized.path) else { continue }

            seenPaths.insert(standardized.path)
            uniqueFiles.append(standardized)
            sizes[standardized] = Int64((try? standardized.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }

        uniqueFiles.sort { $0.path < $1.path }

        isScanning = false
        mediaFiles = uniqueFiles
        selectedURL = uniqueFiles.first
        fileSizes = sizes
        totalBytes = sizes.values.reduce(0, +)
    }

    // Allowed extensions
    private let allowedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "webp", "raw", "dng",
        "mp4", "mov", "avi", "mkv", "webm", "m4v"
    ]

    func scan(folders: [URL], processedFiles: [ProcessedFile]) async {
        let processedPaths = Set(processedFiles.map { $0.filePath })
        let scanID = UUID()

        await MainActor.run {
            self.activeScanID = scanID
            self.isScanning = true
            self.mediaFiles.removeAll()
            self.selectedURL = nil
            self.totalBytes = 0
            self.fileSizes = [:]
        }

        var newMedia: [URL] = []
        var sizes: [URL: Int64] = [:]
        var seenPaths: Set<String> = []

        do {
            try Task.checkCancellation()

            for folder in folders {
                try Task.checkCancellation()

                guard let enumerator = FileManager.default.enumerator(
                    at: folder,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }

                while let fileURL = enumerator.nextObject() as? URL {
                    try Task.checkCancellation()
                    // Yield to keep UI responsive if needed
                    await Task.yield()
                    try Task.checkCancellation()

                    do {
                        let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                        guard resourceValues.isRegularFile == true else { continue }

                        let ext = fileURL.pathExtension.lowercased()
                        if allowedExtensions.contains(ext) {
                            let standardized = fileURL.standardizedFileURL
                            if !processedPaths.contains(standardized.path), !seenPaths.contains(standardized.path) {
                                seenPaths.insert(standardized.path)
                                newMedia.append(standardized)
                                sizes[standardized] = Int64(resourceValues.fileSize ?? 0)
                            }
                        }
                    } catch {
                        print("Error reading resource values for \(fileURL): \(error)")
                    }
                }
            }

            try Task.checkCancellation()

            // Sort newest first or alphabetically? Let's just shuffle or do randomly for serendipity?
            // Let's sort alphabetically for predictability.
            newMedia.sort(by: { $0.path < $1.path })

            let finalMedia = newMedia
            let finalSizes = sizes
            let total = finalSizes.values.reduce(0, +)
            try Task.checkCancellation()

            await MainActor.run {
                guard self.activeScanID == scanID, !Task.isCancelled else {
                    if self.activeScanID == scanID {
                        self.isScanning = false
                    }
                    return
                }

                self.mediaFiles = finalMedia
                self.fileSizes = finalSizes
                self.totalBytes = total
                self.selectedURL = self.mediaFiles.first
                self.isScanning = false
            }
        } catch is CancellationError {
            await MainActor.run {
                if self.activeScanID == scanID {
                    self.isScanning = false
                }
            }
        } catch {
            await MainActor.run {
                if self.activeScanID == scanID {
                    self.isScanning = false
                }
            }
        }
    }
}

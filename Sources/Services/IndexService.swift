import Foundation
import CoreGraphics
import AppKit
import Observation
import QuickLookThumbnailing

/// Which index passes the user ticked on the options screen.
struct IndexOptions: Equatable {
    /// Visual embeddings + k-means clustering (powers the cluster canvas).
    var semanticClusters = true
    /// Phase 2: CLIP helper labels for clusters.
    var autoCategories = false
    /// Phase 3: near-duplicate grouping.
    var nearDuplicates = false
    /// Phase 3: blur / low-detail scoring.
    var blurScores = false
}

/// One cluster of related media, positioned on the 2D canvas.
struct MediaCluster: Identifiable, Equatable {
    let id: Int
    /// "Cluster 3" in Phase 1; CLIP auto-category name in Phase 2.
    var label: String
    var fileURLs: [URL]
    var totalBytes: Int64
    /// Normalized (0...1) canvas position from the 2D projection of the centroid.
    var position: CGPoint

    var previewURLs: [URL] { Array(fileURLs.prefix(4)) }
}

/// Builds and hosts the active index. Auto-categories use the Python CLIP helper JSON;
/// visual clusters without auto-categories use the Phase 1 Apple Vision path.
/// Completed indexes are persisted by `IndexStore` and can be restored into this service.
@Observable
final class IndexService {
    enum Phase: Equatable {
        case idle
        case preparing                    // loading embedder/helper
        case clipIndexing(message: String, done: Int?, total: Int?) // Python CLIP helper progress
        case embedding(done: Int, total: Int)
        case clustering
        case done
        case failed(String)
        case cancelled
    }

    var phase: Phase = .idle
    var clusters: [MediaCluster] = []
    /// Name of the embedder actually used ("CLIP ViT-H/14" or "Apple Vision").
    var embedderName: String = ""

    private let clipRunner: CLIPIndexRunner

    init(clipRunner: CLIPIndexRunner = CLIPIndexRunner()) {
        self.clipRunner = clipRunner
    }

    /// Build the index for `files`. Implemented by the indexing engine.
    func buildIndex(files: [URL], folderRoots: [URL] = [], options: IndexOptions) async {
        await MainActor.run {
            phase = .preparing
            clusters = []
            embedderName = ""
        }

        guard options.semanticClusters || options.autoCategories else {
            await MainActor.run {
                phase = .done
            }
            return
        }

        do {
            try Task.checkCancellation()

            if options.autoCategories {
                try await buildCLIPIndex(files: files, folderRoots: folderRoots)
            } else {
                try await buildVisionIndex(files: files)
            }
        } catch is CancellationError {
            await MainActor.run {
                phase = .cancelled
            }
        } catch {
            await MainActor.run {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        phase = .cancelled
    }

    func load(savedIndex: SavedIndex) {
        clusters = savedIndex.mediaClusters
        embedderName = savedIndex.summary.embedderName
        phase = .done
    }

    func updateClusterPosition(id: Int, position: CGPoint) {
        guard let index = clusters.firstIndex(where: { $0.id == id }) else { return }
        clusters[index].position = CGPoint(
            x: min(max(position.x, 0), 1),
            y: min(max(position.y, 0), 1)
        )
    }

    private func buildCLIPIndex(files: [URL], folderRoots: [URL]) async throws {
        await MainActor.run {
            embedderName = "CLIP ViT-H/14"
            phase = .clipIndexing(message: "Running CLIP auto-categories helper…", done: nil, total: nil)
        }

        guard !files.isEmpty else {
            await MainActor.run {
                clusters = []
                phase = .done
            }
            return
        }

        let result = try await clipRunner.run(inputs: files, folderRoots: folderRoots) { [weak self] progress in
            Task { @MainActor in
                self?.phase = .clipIndexing(message: progress.displayMessage, done: progress.done, total: progress.total)
            }
        }
        defer {
            if result.isTemporaryOutput {
                try? FileManager.default.removeItem(at: result.outputURL)
            }
        }
        try Task.checkCancellation()

        await MainActor.run {
            phase = .clipIndexing(message: "Importing CLIP cluster JSON…", done: nil, total: nil)
        }

        let document = try CLIPIndexParser.decode(contentsOf: result.outputURL)
        let builtClusters = Self.makeClusters(from: document, restrictingTo: files)

        await MainActor.run {
            clusters = builtClusters
            phase = .done
        }
    }

    private func buildVisionIndex(files: [URL]) async throws {
        let embedder = VisionFeaturePrintEmbedder()
        try await embedder.prepare()
        await MainActor.run {
            embedderName = embedder.name
        }

        let total = files.count
        var records: [EmbeddedMedia] = []
        records.reserveCapacity(total)

        for (index, fileURL) in files.enumerated() {
            try Task.checkCancellation()
            await MainActor.run {
                phase = .embedding(done: index, total: total)
            }

            guard let image = await Self.thumbnailImage(for: fileURL) else {
                await Task.yield()
                continue
            }

            do {
                let embedding = try await embedder.embed(image)
                let normalizedEmbedding = ClusterMath.normalized(embedding)
                guard !normalizedEmbedding.isEmpty else { continue }

                records.append(
                    EmbeddedMedia(
                        url: fileURL.standardizedFileURL,
                        bytes: Self.fileSize(for: fileURL),
                        embedding: normalizedEmbedding
                    )
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Skip files Vision or Quick Look cannot decode robustly in Phase 1.
                continue
            }

            await Task.yield()
        }

        try Task.checkCancellation()
        await MainActor.run {
            phase = .embedding(done: total, total: total)
        }

        await MainActor.run {
            phase = .clustering
        }
        let builtClusters = try await Self.makeClusters(from: records)
        await MainActor.run {
            clusters = builtClusters
            phase = .done
        }
    }

    private static func thumbnailImage(for url: URL) async -> CGImage? {
        let size = CGSize(width: 256, height: 256)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: 1.0,
            representationTypes: .thumbnail
        )

        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            return representation.cgImage
        } catch {
            return fallbackImage(for: url)
        }
    }

    private static func fallbackImage(for url: URL) -> CGImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func fileSize(for url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private static func makeClusters(from document: CLIPIndexDocument, restrictingTo files: [URL]) -> [MediaCluster] {
        var allowedByPath: [String: URL] = [:]
        for file in files {
            let standardized = file.standardizedFileURL
            allowedByPath[standardized.path] = standardized
        }

        return document.clusters.compactMap { clipCluster in
            var urls: [URL] = []
            var seenPaths: Set<String> = []
            var totalBytes: Int64 = 0

            for path in clipCluster.paths {
                let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
                guard let url = allowedByPath[standardizedPath] else { continue }
                guard !seenPaths.contains(url.path) else { continue }

                seenPaths.insert(url.path)
                urls.append(url)
                totalBytes += fileSize(for: url)
            }

            guard !urls.isEmpty else { return nil }

            let label = clipCluster.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return MediaCluster(
                id: clipCluster.id,
                label: label.isEmpty ? "Cluster \(clipCluster.id + 1)" : label,
                fileURLs: urls.sorted { $0.path < $1.path },
                totalBytes: totalBytes,
                position: clampedPosition(clipCluster.position.cgPoint)
            )
        }
        .sorted { lhs, rhs in
            if lhs.fileURLs.count == rhs.fileURLs.count {
                return lhs.label < rhs.label
            }
            return lhs.fileURLs.count > rhs.fileURLs.count
        }
    }

    private static func clampedPosition(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(1, max(0, point.x)),
            y: min(1, max(0, point.y))
        )
    }

    private static func makeClusters(from records: [EmbeddedMedia]) async throws -> [MediaCluster] {
        try Task.checkCancellation()
        guard !records.isEmpty else { return [] }

        if records.count == 1 {
            return [
                MediaCluster(
                    id: 0,
                    label: "Cluster 1",
                    fileURLs: [records[0].url],
                    totalBytes: records[0].bytes,
                    position: CGPoint(x: 0.5, y: 0.5)
                )
            ]
        }

        let embeddings = records.map(\.embedding)
        let clusterCount = recommendedClusterCount(for: records.count)
        let assignments = ClusterMath.kMeans(vectors: embeddings, k: clusterCount)
        let centroids = ClusterMath.centroids(for: embeddings, assignments: assignments, clusterCount: clusterCount)
        let positions = ClusterMath.project2D(centroids: centroids)

        var groupedURLs = Array(repeating: [URL](), count: clusterCount)
        var groupedBytes = Array(repeating: Int64(0), count: clusterCount)

        for (index, record) in records.enumerated() {
            try Task.checkCancellation()
            let assignment = assignments.indices.contains(index) ? assignments[index] : 0
            let clusterIndex = min(max(assignment, 0), clusterCount - 1)
            groupedURLs[clusterIndex].append(record.url)
            groupedBytes[clusterIndex] += record.bytes
        }

        return (0..<clusterCount)
            .filter { !groupedURLs[$0].isEmpty }
            .map { clusterIndex in
                MediaCluster(
                    id: clusterIndex,
                    label: "Cluster \(clusterIndex + 1)",
                    fileURLs: groupedURLs[clusterIndex].sorted { $0.path < $1.path },
                    totalBytes: groupedBytes[clusterIndex],
                    position: positions.indices.contains(clusterIndex) ? positions[clusterIndex] : CGPoint(x: 0.5, y: 0.5)
                )
            }
            .sorted { lhs, rhs in
                if lhs.fileURLs.count == rhs.fileURLs.count {
                    return lhs.label < rhs.label
                }
                return lhs.fileURLs.count > rhs.fileURLs.count
            }
    }

    private static func recommendedClusterCount(for itemCount: Int) -> Int {
        guard itemCount > 2 else { return itemCount }

        let estimate = Int((Double(itemCount) / 2.0).squareRoot().rounded())
        return min(30, max(3, min(estimate, itemCount)))
    }
}

private struct EmbeddedMedia {
    let url: URL
    let bytes: Int64
    let embedding: [Float]
}

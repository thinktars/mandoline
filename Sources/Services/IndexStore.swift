import Foundation
import CoreGraphics
import Observation

struct SavedIndexSummary: Identifiable, Codable, Equatable {
    var id: UUID
    var displayName: String
    var folderPaths: [String]
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?
    var embedderName: String
    var clusterCount: Int
    var itemCount: Int
    var totalMediaBytes: Int64
    var cachedMetadataBytes: Int64
}

struct SavedIndexFolderRoot: Codable, Equatable {
    var path: String
    var bookmarkData: Data
}

struct SavedIndexCluster: Codable, Equatable {
    var id: Int
    var label: String
    var filePaths: [String]
    var totalBytes: Int64
    var positionX: Double
    var positionY: Double
}

struct SavedIndex: Codable, Equatable {
    var version: Int
    var summary: SavedIndexSummary
    var folderRoots: [SavedIndexFolderRoot]
    var clusters: [SavedIndexCluster]
}

struct SavedIndexOpenResult {
    var index: SavedIndex
    var folderRoots: [URL]
}

@Observable
final class IndexStore {
    private struct Manifest: Codable {
        var version: Int
        var indexes: [SavedIndexSummary]
    }

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let storeDirectory: URL
    private let manifestURL: URL

    private(set) var savedIndexes: [SavedIndexSummary] = []

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        self.storeDirectory = applicationSupport
            .appendingPathComponent("Mandoline", isDirectory: true)
            .appendingPathComponent("Indexes", isDirectory: true)
        self.manifestURL = storeDirectory.appendingPathComponent("manifest.json", isDirectory: false)

        loadManifest()
    }

    func saveIndex(folderRoots: [URL], clusters: [MediaCluster], embedderName: String) throws -> SavedIndexSummary {
        try fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)

        let standardizedRoots = folderRoots.map { $0.standardizedFileURL }
        let folderPaths = standardizedRoots.map(\.path)
        let now = Date()
        let existing = matchingSummary(folderPaths: folderPaths, embedderName: embedderName)
        let id = existing?.id ?? UUID()
        let indexDirectory = directory(for: id)
        try fileManager.createDirectory(at: indexDirectory, withIntermediateDirectories: true)

        let roots = try standardizedRoots.map { root in
            SavedIndexFolderRoot(
                path: root.path,
                bookmarkData: try root.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            )
        }

        var summary = SavedIndexSummary(
            id: id,
            displayName: Self.displayName(for: standardizedRoots),
            folderPaths: folderPaths,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            lastOpenedAt: existing?.lastOpenedAt,
            embedderName: embedderName.isEmpty ? "Local Index" : embedderName,
            clusterCount: clusters.count,
            itemCount: clusters.reduce(0) { $0 + $1.fileURLs.count },
            totalMediaBytes: clusters.reduce(Int64(0)) { $0 + $1.totalBytes },
            cachedMetadataBytes: 0
        )

        let savedClusters = clusters.map { cluster in
            SavedIndexCluster(
                id: cluster.id,
                label: cluster.label,
                filePaths: cluster.fileURLs.map { $0.standardizedFileURL.path },
                totalBytes: cluster.totalBytes,
                positionX: Double(cluster.position.x),
                positionY: Double(cluster.position.y)
            )
        }

        var index = SavedIndex(version: 1, summary: summary, folderRoots: roots, clusters: savedClusters)
        try write(index, to: indexFile(for: id))
        summary.cachedMetadataBytes = directorySize(at: indexDirectory)
        index.summary = summary
        try write(index, to: indexFile(for: id))

        upsert(summary)
        try saveManifest()
        return summary
    }

    func openIndex(_ summary: SavedIndexSummary) throws -> SavedIndexOpenResult {
        var index = try readIndex(id: summary.id)
        guard index.version == 1 else {
            throw error("Unsupported saved index version \(index.version).")
        }

        var resolvedRoots: [URL] = []
        var rootPathRemaps: [(old: String, new: String)] = []
        do {
            for root in index.folderRoots {
                var isStale = false
                let oldRootPath = root.path
                let url = try URL(
                    resolvingBookmarkData: root.bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ).standardizedFileURL

                guard url.startAccessingSecurityScopedResource() else {
                    throw error("Mandoline no longer has permission to open \(root.path).")
                }

                resolvedRoots.append(url)

                if oldRootPath != url.path {
                    rootPathRemaps.append((old: oldRootPath, new: url.path))
                }

                if isStale || oldRootPath != url.path {
                    let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    if let rootIndex = index.folderRoots.firstIndex(where: { $0.path == oldRootPath }) {
                        index.folderRoots[rootIndex].bookmarkData = bookmark
                        index.folderRoots[rootIndex].path = url.path
                    }
                }
            }
        } catch {
            for url in resolvedRoots {
                url.stopAccessingSecurityScopedResource()
            }
            throw error
        }

        if !rootPathRemaps.isEmpty {
            applyRootPathRemaps(rootPathRemaps, to: &index)
        }

        index.summary.lastOpenedAt = Date()
        index.summary.cachedMetadataBytes = directorySize(at: directory(for: summary.id))
        try write(index, to: indexFile(for: summary.id))
        upsert(index.summary)
        try saveManifest()

        return SavedIndexOpenResult(index: index, folderRoots: resolvedRoots)
    }

    func deleteIndex(_ summary: SavedIndexSummary) throws {
        let indexDirectory = directory(for: summary.id)
        if fileManager.fileExists(atPath: indexDirectory.path) {
            try fileManager.removeItem(at: indexDirectory)
        }
        savedIndexes.removeAll { $0.id == summary.id }
        try saveManifest()
    }

    func summary(id: UUID?) -> SavedIndexSummary? {
        guard let id else { return nil }
        return savedIndexes.first { $0.id == id }
    }

    private func loadManifest() {
        do {
            try fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                savedIndexes = []
                return
            }

            let data = try Data(contentsOf: manifestURL)
            let manifest = try decoder.decode(Manifest.self, from: data)
            savedIndexes = manifest.indexes
                .map { summary in
                    var updated = summary
                    updated.cachedMetadataBytes = directorySize(at: directory(for: summary.id))
                    return updated
                }
                .sorted(by: Self.sortSummaries)
        } catch {
            print("[Mandoline] Failed to load saved indexes: \(error)")
            savedIndexes = []
        }
    }

    private func saveManifest() throws {
        try fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let manifest = Manifest(version: 1, indexes: savedIndexes.sorted(by: Self.sortSummaries))
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: [.atomic])
        savedIndexes = manifest.indexes
    }

    private func applyRootPathRemaps(_ remaps: [(old: String, new: String)], to index: inout SavedIndex) {
        func remapPath(_ path: String) -> String {
            for remap in remaps.sorted(by: { $0.old.count > $1.old.count }) {
                if path == remap.old { return remap.new }
                let prefix = remap.old.hasSuffix("/") ? remap.old : remap.old + "/"
                if path.hasPrefix(prefix) {
                    return remap.new + "/" + String(path.dropFirst(prefix.count))
                }
            }
            return path
        }

        index.summary.folderPaths = index.folderRoots.map(\.path)
        index.clusters = index.clusters.map { cluster in
            var updated = cluster
            updated.filePaths = cluster.filePaths.map(remapPath)
            return updated
        }
    }

    private func readIndex(id: UUID) throws -> SavedIndex {
        let data = try Data(contentsOf: indexFile(for: id))
        return try decoder.decode(SavedIndex.self, from: data)
    }

    private func write(_ index: SavedIndex, to url: URL) throws {
        let data = try encoder.encode(index)
        try data.write(to: url, options: [.atomic])
    }

    private func upsert(_ summary: SavedIndexSummary) {
        savedIndexes.removeAll { $0.id == summary.id }
        savedIndexes.append(summary)
        savedIndexes.sort(by: Self.sortSummaries)
    }

    private func matchingSummary(folderPaths: [String], embedderName: String) -> SavedIndexSummary? {
        let pathSet = Set(folderPaths)
        let normalizedEmbedder = embedderName.isEmpty ? "Local Index" : embedderName
        return savedIndexes.first { summary in
            Set(summary.folderPaths) == pathSet && summary.embedderName == normalizedEmbedder
        }
    }

    private func directory(for id: UUID) -> URL {
        storeDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func indexFile(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent("index.json", isDirectory: false)
    }

    private func directorySize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private func error(_ message: String) -> NSError {
        NSError(domain: "Mandoline.IndexStore", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func displayName(for roots: [URL]) -> String {
        guard let first = roots.first else { return "Saved Index" }
        if roots.count == 1 { return first.lastPathComponent }
        return "\(first.lastPathComponent) + \(roots.count - 1) more"
    }

    private static func sortSummaries(_ lhs: SavedIndexSummary, _ rhs: SavedIndexSummary) -> Bool {
        (lhs.lastOpenedAt ?? lhs.updatedAt) > (rhs.lastOpenedAt ?? rhs.updatedAt)
    }
}

extension SavedIndex {
    var mediaClusters: [MediaCluster] {
        clusters.map { cluster in
            MediaCluster(
                id: cluster.id,
                label: cluster.label,
                fileURLs: cluster.filePaths.map { URL(fileURLWithPath: $0).standardizedFileURL },
                totalBytes: cluster.totalBytes,
                position: CGPoint(x: cluster.positionX, y: cluster.positionY)
            )
        }
    }
}

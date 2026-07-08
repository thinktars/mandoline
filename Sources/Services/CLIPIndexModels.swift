import Foundation
import CoreGraphics

/// Codable representation of the JSON emitted by `tools/clip/index_folder.py`.
/// Keep these names close to the wire format so fixture drift is easy to spot.
struct CLIPIndexDocument: Codable, Equatable {
    let version: Int
    let model: String
    let embeddingDimension: Int
    let items: [CLIPIndexItem]
    let clusters: [CLIPIndexCluster]

    enum CodingKeys: String, CodingKey {
        case version
        case model
        case embeddingDimension = "embedding_dimension"
        case items
        case clusters
    }
}

struct CLIPIndexItem: Codable, Equatable {
    let path: String
    let embedding: [Float]?
    let labels: [CLIPIndexLabel]
}

struct CLIPIndexLabel: Codable, Equatable {
    let label: String
    let score: Double
}

struct CLIPIndexCluster: Codable, Equatable {
    let id: Int
    let label: String
    let score: Double
    let paths: [String]
    let position: CLIPIndexPosition
}

struct CLIPIndexPosition: Codable, Equatable {
    let x: Double
    let y: Double

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

enum CLIPIndexParser {
    static func decode(contentsOf url: URL) throws -> CLIPIndexDocument {
        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> CLIPIndexDocument {
        let decoder = JSONDecoder()
        let document = try decoder.decode(CLIPIndexDocument.self, from: data)
        try validate(document)
        return document
    }

    private static func validate(_ document: CLIPIndexDocument) throws {
        guard document.version == 1 else {
            throw NSError(
                domain: "Mandoline.CLIPIndex",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported CLIP index JSON version \(document.version). Mandoline expects version 1."]
            )
        }

        guard !document.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(
                domain: "Mandoline.CLIPIndex",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "CLIP index JSON is missing the model name."]
            )
        }

        for cluster in document.clusters where cluster.paths.isEmpty {
            throw NSError(
                domain: "Mandoline.CLIPIndex",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "CLIP index cluster \(cluster.id) has no file paths."]
            )
        }
    }
}

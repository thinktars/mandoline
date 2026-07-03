import Foundation
import CoreGraphics

/// Core ML adapter for laion/CLIP-ViT-H-14-laion2B-s32B-b79K.
/// Phase 1 can fall back to Apple Vision when this asset is unavailable.
final class CLIPEmbedder: ImageEmbedder {
    let name = "CLIP ViT-H/14"
    let dimension = 1024

    func prepare() async throws {
        let fileManager = FileManager.default
        let supportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let modelsDirectory = supportDirectory
            .appendingPathComponent("Mandoline", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)

        let candidates = [
            modelsDirectory.appendingPathComponent("CLIP-ViT-H-14.mlpackage", isDirectory: true),
            modelsDirectory.appendingPathComponent("CLIP-ViT-H-14.mlmodelc", isDirectory: true)
        ]

        if let installedModel = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            throw NSError(
                domain: "Mandoline.Indexing",
                code: 5,
                userInfo: [
                    NSLocalizedDescriptionKey: "Found CLIP model asset at \(installedModel.path), but the Phase 1 CLIP Core ML adapter is not implemented yet. Mandoline will use Apple Vision for this index."
                ]
            )
        }

        let expectedPath = candidates.map(\.path).joined(separator: " or ")
        throw NSError(
            domain: "Mandoline.Indexing",
            code: 2,
            userInfo: [
                NSLocalizedDescriptionKey: "CLIP is not available locally. Install a Core ML conversion of laion/CLIP-ViT-H-14-laion2B-s32B-b79K at \(expectedPath). Mandoline will use Apple Vision for this index."
            ]
        )
    }

    func embed(_ image: CGImage) async throws -> [Float] {
        throw NSError(
            domain: "Mandoline.Indexing",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "CLIP image embedding is not wired in Phase 1. Mandoline will use Apple Vision until the Core ML adapter is implemented."]
        )
    }
}

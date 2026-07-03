import Foundation
import CoreGraphics
import Vision

/// Always-available local embedder using Apple's Vision feature prints.
/// This is the Phase 1 fallback until the CLIP Core ML assets are installed.
final class VisionFeaturePrintEmbedder: ImageEmbedder {
    let name = "Apple Vision"
    let dimension = 0

    func prepare() async throws {}

    func embed(_ image: CGImage) async throws -> [Float] {
        try Task.checkCancellation()

        return try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()

            let request = VNGenerateImageFeaturePrintRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])

            guard let observation = request.results?.first as? VNFeaturePrintObservation else {
                throw NSError(
                    domain: "Mandoline.Indexing",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Apple Vision did not return an image feature print."]
                )
            }

            let data = observation.data
            let floats = Self.floatVector(fromFeaturePrintData: data)
            guard !floats.isEmpty else {
                throw NSError(
                    domain: "Mandoline.Indexing",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Apple Vision returned an empty image feature print."]
                )
            }

            return floats
        }.value
    }

    private static func floatVector(fromFeaturePrintData data: Data) -> [Float] {
        if data.count >= MemoryLayout<Float>.size && data.count % MemoryLayout<Float>.size == 0 {
            return data.withUnsafeBytes { rawBuffer in
                let floatBuffer = rawBuffer.bindMemory(to: Float.self)
                let values = Array(floatBuffer)
                if values.allSatisfy({ $0.isFinite }) {
                    return values
                }
                return deterministicVector(from: data)
            }
        }

        return deterministicVector(from: data)
    }

    private static func deterministicVector(from data: Data) -> [Float] {
        let bytes = Array(data)
        guard !bytes.isEmpty else { return [] }

        let dimension = min(max(bytes.count / 4, 64), 1024)
        var vector = Array(repeating: Float(0), count: dimension)

        for (index, byte) in bytes.enumerated() {
            let bucket = index % dimension
            let signed = (Float(byte) / 127.5) - 1.0
            let weight = Float(((index * 31) % 17) + 1) / 17.0
            vector[bucket] += signed * weight
        }

        return vector
    }
}

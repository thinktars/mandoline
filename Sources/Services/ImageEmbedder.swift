import CoreGraphics

/// Produces a fixed-length embedding vector for an image.
///
/// Implementations must be safe to call concurrently after `prepare()`.
/// Phase 1 ships two: `VisionFeaturePrintEmbedder` (always available, on-device)
/// and `CLIPEmbedder` (a placeholder for a future Core ML conversion of
/// laion/CLIP-ViT-H-14; it reports unavailable until the adapter is wired).
protocol ImageEmbedder: Sendable {
    /// Human-readable name for logs/UI ("Apple Vision", "CLIP ViT-H/14").
    var name: String { get }
    /// Embedding vector length.
    var dimension: Int { get }
    /// Load model resources. Called once before embedding begins.
    func prepare() async throws
    /// Embed a decoded image (any size; implementations handle scale/crop).
    func embed(_ image: CGImage) async throws -> [Float]
}

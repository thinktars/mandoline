import Foundation
import CoreGraphics

/// Math helpers for normalizing embeddings, clustering, and 2D projection.
enum ClusterMath {
    static func normalized(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
        let count = min(lhs.count, rhs.count)
        guard count > 0 else { return 0 }

        var dot = Float(0)
        var lhsMagnitude = Float(0)
        var rhsMagnitude = Float(0)

        for index in 0..<count {
            let left = lhs[index]
            let right = rhs[index]
            dot += left * right
            lhsMagnitude += left * left
            rhsMagnitude += right * right
        }

        let denominator = sqrt(lhsMagnitude) * sqrt(rhsMagnitude)
        guard denominator > 0 else { return 0 }
        return dot / denominator
    }

    static func cosineDistance(_ lhs: [Float], _ rhs: [Float]) -> Float {
        1 - cosineSimilarity(lhs, rhs)
    }

    static func centroid(of vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first else { return [] }

        let dimension = first.count
        var centroid = Array(repeating: Float(0), count: dimension)
        var contributingVectors = 0

        for vector in vectors where vector.count == dimension {
            contributingVectors += 1
            for index in 0..<dimension {
                centroid[index] += vector[index]
            }
        }

        guard contributingVectors > 0 else { return [] }
        let divisor = Float(contributingVectors)
        return centroid.map { $0 / divisor }
    }

    static func kMeans(vectors: [[Float]], k requestedK: Int, maxIterations: Int = 40) -> [Int] {
        guard !vectors.isEmpty else { return [] }
        guard vectors.count > 1 else { return [0] }

        let vectors = vectors.map(normalized)
        let k = max(1, min(requestedK, vectors.count))
        var centroids = initialCentroids(from: vectors, k: k)
        var assignments = Array(repeating: -1, count: vectors.count)

        for _ in 0..<maxIterations {
            var changed = false

            for (vectorIndex, vector) in vectors.enumerated() {
                var bestCluster = 0
                var bestDistance = Float.greatestFiniteMagnitude

                for (clusterIndex, centroid) in centroids.enumerated() {
                    let distance = cosineDistance(vector, centroid)
                    if distance < bestDistance {
                        bestDistance = distance
                        bestCluster = clusterIndex
                    }
                }

                if assignments[vectorIndex] != bestCluster {
                    assignments[vectorIndex] = bestCluster
                    changed = true
                }
            }

            var grouped = Array(repeating: [[Float]](), count: k)
            for (index, assignment) in assignments.enumerated() where assignment >= 0 {
                grouped[assignment].append(vectors[index])
            }

            for clusterIndex in 0..<k {
                if grouped[clusterIndex].isEmpty {
                    centroids[clusterIndex] = replacementCentroid(from: vectors, assignments: assignments, centroids: centroids)
                } else {
                    centroids[clusterIndex] = normalized(centroid(of: grouped[clusterIndex]))
                }
            }

            if !changed {
                break
            }
        }

        return assignments.map { max(0, $0) }
    }

    static func centroids(for vectors: [[Float]], assignments: [Int], clusterCount: Int) -> [[Float]] {
        guard clusterCount > 0 else { return [] }

        let vectors = vectors.map(normalized)
        var grouped = Array(repeating: [[Float]](), count: clusterCount)
        for (index, assignment) in assignments.enumerated()
            where assignment >= 0 && assignment < clusterCount && index < vectors.count {
            grouped[assignment].append(vectors[index])
        }

        return grouped.map { normalized(centroid(of: $0)) }
    }

    static func project2D(centroids: [[Float]]) -> [CGPoint] {
        guard !centroids.isEmpty else { return [] }

        let points = centroids.map { centroid in
            let normalizedCentroid = normalized(centroid)
            let x = normalizedCentroid.indices.contains(0) ? CGFloat(normalizedCentroid[0]) : 0
            let y = normalizedCentroid.indices.contains(1) ? CGFloat(normalizedCentroid[1]) : 0
            return CGPoint(x: x, y: y)
        }

        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0

        return points.map { point in
            CGPoint(
                x: normalizedCoordinate(point.x, min: minX, max: maxX),
                y: normalizedCoordinate(point.y, min: minY, max: maxY)
            )
        }
    }

    private static func initialCentroids(from vectors: [[Float]], k: Int) -> [[Float]] {
        guard k > 0 else { return [] }
        guard k > 1 else { return [vectors[0]] }
        guard k < vectors.count else { return vectors }

        let step = Double(vectors.count - 1) / Double(k - 1)
        return (0..<k).map { clusterIndex in
            let vectorIndex = Int((Double(clusterIndex) * step).rounded())
            return vectors[min(vectorIndex, vectors.count - 1)]
        }
    }

    private static func replacementCentroid(from vectors: [[Float]], assignments: [Int], centroids: [[Float]]) -> [Float] {
        var bestVector = vectors[0]
        var bestDistance = -Float.greatestFiniteMagnitude

        for (index, vector) in vectors.enumerated() {
            let assignedCluster = assignments.indices.contains(index) ? assignments[index] : 0
            let assignedCentroid = centroids.indices.contains(assignedCluster) ? centroids[assignedCluster] : centroids[0]
            let distance = cosineDistance(vector, assignedCentroid)
            if distance > bestDistance {
                bestDistance = distance
                bestVector = vector
            }
        }

        return bestVector
    }

    private static func normalizedCoordinate(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        guard max > min else { return 0.5 }
        return Swift.min(1, Swift.max(0, (value - min) / (max - min)))
    }
}

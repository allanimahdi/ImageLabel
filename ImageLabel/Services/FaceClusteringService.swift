import Foundation

/// Groups face indices by embedding distance (single-linkage / union-find).
enum FaceClusteringService {
    /// - Parameters:
    ///   - count: number of faces
    ///   - threshold: max distance to merge (lower = stricter). Vision feature-print face crops often merge well around 0.55–0.85.
    ///   - distance: symmetric distance; callers may return +inf for invalid pairs
    /// - Returns: clusters as arrays of indices (sorted ascending within each cluster)
    static func cluster(
        count: Int,
        threshold: Float,
        distance: (_ i: Int, _ j: Int) -> Float
    ) -> [[Int]] {
        guard count > 0 else { return [] }
        var parent = Array(0..<count)
        var rank = Array(repeating: 0, count: count)

        func find(_ x: Int) -> Int {
            if parent[x] != x { parent[x] = find(parent[x]) }
            return parent[x]
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a)
            let rb = find(b)
            guard ra != rb else { return }
            if rank[ra] < rank[rb] {
                parent[ra] = rb
            } else if rank[ra] > rank[rb] {
                parent[rb] = ra
            } else {
                parent[rb] = ra
                rank[ra] += 1
            }
        }

        if count > 1 {
            for i in 0..<(count - 1) {
                for j in (i + 1)..<count {
                    let d = distance(i, j)
                    if d <= threshold {
                        union(i, j)
                    }
                }
            }
        }

        var buckets: [Int: [Int]] = [:]
        for i in 0..<count {
            buckets[find(i), default: []].append(i)
        }
        return buckets.values
            .map { $0.sorted() }
            .sorted { ($0.first ?? 0) < ($1.first ?? 0) }
    }
}

import Foundation

/// Sample-size math + intelligent (non-random) face selection for mandatory verification.
enum FaceVerificationSampler {
    /// Minimum manual verifications from unique face detections.
    /// ≤100 photos → ceil(20%); >100 photos → ceil(5%).
    static func requiredSampleSize(photoCount: Int, uniqueFaceCount: Int) -> Int {
        guard uniqueFaceCount > 0 else { return 0 }
        let rate = photoCount <= 100 ? 0.20 : 0.05
        return Int(ceil(Double(uniqueFaceCount) * rate))
    }

    /// Lightweight candidate used for ranking (no Vision types — unit-testable).
    struct Candidate: Equatable {
        let faceID: UUID
        let groupID: UUID
        /// 0 = confident library match; 1 = no match / very uncertain.
        let uncertainty: Float
        /// Proxy for pose/lighting diversity (e.g. quantized box size + midX).
        let diversityBucket: Int
        /// Faces with very similar embeddings share a key so we ask once.
        let nearDuplicateKey: Int
    }

    /// Picks up to `limit` faces covering groups, prioritizing uncertain + diverse, skipping near-dupes.
    static func selectFaceIDs(from candidates: [Candidate], limit: Int) -> [UUID] {
        guard limit > 0, !candidates.isEmpty else { return [] }

        // Within each near-duplicate set, keep the most uncertain (stable tie-break).
        var bestByNearDup: [Int: Candidate] = [:]
        for candidate in candidates {
            if let existing = bestByNearDup[candidate.nearDuplicateKey] {
                let better =
                    candidate.uncertainty > existing.uncertainty
                    || (candidate.uncertainty == existing.uncertainty
                        && candidate.faceID.uuidString < existing.faceID.uuidString)
                if better {
                    bestByNearDup[candidate.nearDuplicateKey] = candidate
                }
            } else {
                bestByNearDup[candidate.nearDuplicateKey] = candidate
            }
        }

        var byGroup: [UUID: [Candidate]] = [:]
        for candidate in bestByNearDup.values {
            byGroup[candidate.groupID, default: []].append(candidate)
        }
        for key in byGroup.keys {
            byGroup[key]?.sort {
                if $0.uncertainty != $1.uncertainty { return $0.uncertainty > $1.uncertainty }
                if $0.diversityBucket != $1.diversityBucket {
                    return $0.diversityBucket < $1.diversityBucket
                }
                return $0.faceID.uuidString < $1.faceID.uuidString
            }
        }

        // Round-robin: groups with higher peak uncertainty first.
        var queues = byGroup
            .map { (id: $0.key, items: $0.value) }
            .sorted { a, b in
                let ua = a.items.first?.uncertainty ?? 0
                let ub = b.items.first?.uncertainty ?? 0
                if ua != ub { return ua > ub }
                return a.id.uuidString < b.id.uuidString
            }

        var selected: [UUID] = []
        var usedDiversity = Set<Int>()
        var cursor = 0

        while selected.count < limit, !queues.isEmpty {
            if cursor >= queues.count { cursor = 0 }
            var queue = queues[cursor]
            guard !queue.items.isEmpty else {
                queues.remove(at: cursor)
                continue
            }

            let pickIndex =
                queue.items.firstIndex(where: { !usedDiversity.contains($0.diversityBucket) }) ?? 0
            let chosen = queue.items.remove(at: pickIndex)
            selected.append(chosen.faceID)
            usedDiversity.insert(chosen.diversityBucket)

            if queue.items.isEmpty {
                queues.remove(at: cursor)
            } else {
                queues[cursor] = queue
                cursor += 1
            }
        }

        return selected
    }

    /// Quantize bounding-box size + horizontal position into a diversity bucket.
    static func diversityBucket(boundingBox: CGRect, midX: CGFloat) -> Int {
        let area = max(boundingBox.width * boundingBox.height, 0.0001)
        let sizeBin = min(9, max(0, Int(log10(Double(area) * 1000) + 5)))
        let xBin = min(4, max(0, Int(midX * 5)))
        return sizeBin * 10 + xBin
    }
}

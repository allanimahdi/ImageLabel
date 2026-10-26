import Foundation
import Vision

/// On-device image classification via Apple’s Vision framework (`VNClassifyImageRequest`).
/// Free, offline, no credentials — less capable than Google Cloud Vision.
actor AppleVisionLabeler: ImageLabeling {
    /// Drop low-confidence junk so rename/topic aren’t flooded with noise.
    private let minimumConfidence: Float
    /// If nothing clears the main threshold, accept a single best guess above this floor.
    private let weakFallbackConfidence: Float

    init(minimumConfidence: Float = 0.12, weakFallbackConfidence: Float = 0.05) {
        self.minimumConfidence = minimumConfidence
        self.weakFallbackConfidence = weakFallbackConfidence
    }

    func detectLabels(imageURL: URL, maxResults: Int = 10) async throws -> [VisionLabel] {
        let minimumConfidence = self.minimumConfidence
        let weakFallbackConfidence = self.weakFallbackConfidence
        return try await Task.detached(priority: .userInitiated) {
            try Self.classifySync(
                imageURL: imageURL,
                maxResults: maxResults,
                minimumConfidence: minimumConfidence,
                weakFallbackConfidence: weakFallbackConfidence
            )
        }.value
    }

    nonisolated private static func classifySync(
        imageURL: URL,
        maxResults: Int,
        minimumConfidence: Float,
        weakFallbackConfidence: Float
    ) throws -> [VisionLabel] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(url: imageURL, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw VisionError.labeling(
                "Apple Vision could not read this image (\(error.localizedDescription)). Try another format or Google Cloud Vision."
            )
        }

        let observations = (request.results ?? [])
            .sorted { $0.confidence > $1.confidence }

        guard !observations.isEmpty else {
            throw VisionError.noLabels
        }

        var chosen = observations.filter { $0.confidence >= minimumConfidence }
        if chosen.isEmpty, let best = observations.first, best.confidence >= weakFallbackConfidence {
            chosen = [best]
        }

        guard !chosen.isEmpty else {
            let best = observations.first.map { String(format: "%.0f%%", Double($0.confidence) * 100) } ?? "0%"
            throw VisionError.labeling(
                "Apple Vision found no confident labels (best \(best)). Try a clearer photo, or switch Settings → Labeling to Google Cloud Vision."
            )
        }

        return chosen.prefix(maxResults).map { observation in
            VisionLabel(
                description: humanizeIdentifier(observation.identifier),
                score: Double(observation.confidence)
            )
        }
    }

    /// Vision taxonomy ids are often underscore_separated; make them rename-friendly.
    nonisolated static func humanizeIdentifier(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

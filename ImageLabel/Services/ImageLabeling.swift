import Foundation

/// Shared contract for Google Cloud Vision and on-device Apple Vision labeling.
protocol ImageLabeling: Sendable {
    func detectLabels(imageURL: URL, maxResults: Int) async throws -> [VisionLabel]
}

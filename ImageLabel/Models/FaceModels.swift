import AppKit
import Foundation
import Vision

enum FaceRenameStep: Int, CaseIterable, Identifiable {
    case select = 0
    case detect
    case identify
    case preview

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .select: return "Select Photos"
        case .detect: return "Detect & Group"
        case .identify: return "Identify People"
        case .preview: return "Preview & Rename"
        }
    }
}

enum FaceSkipState: Equatable {
    case named
    case unknown
    case skipped
}

/// One detected face in one photo (on-device Vision pipeline).
final class DetectedFace: Identifiable {
    let id: UUID
    let imageURL: URL
    /// Vision normalized bounding box (origin bottom-left).
    let boundingBox: CGRect
    /// Horizontal center in image coordinates (0…1, left→right) for LTR naming.
    let midX: CGFloat
    let thumbnail: NSImage
    let featurePrint: VNFeaturePrintObservation
    /// Soft quality hint from Vision when available (0…1); nil if not computed.
    let captureQuality: Float?

    init(
        id: UUID = UUID(),
        imageURL: URL,
        boundingBox: CGRect,
        midX: CGFloat,
        thumbnail: NSImage,
        featurePrint: VNFeaturePrintObservation,
        captureQuality: Float? = nil
    ) {
        self.id = id
        self.imageURL = imageURL
        self.boundingBox = boundingBox
        self.midX = midX
        self.thumbnail = thumbnail
        self.featurePrint = featurePrint
        self.captureQuality = captureQuality
    }
}

struct FacePersonGroup: Identifiable, Equatable {
    let id: UUID
    var faceIDs: [UUID]
    var displayThumbnail: NSImage?
    var name: String
    var skipState: FaceSkipState
    /// True when auto-matched to a saved identity below a confident threshold.
    var needsReview: Bool

    var photoCount: Int { Set(faceIDs).count } // updated by session with image URLs

    static func == (lhs: FacePersonGroup, rhs: FacePersonGroup) -> Bool {
        lhs.id == rhs.id
            && lhs.faceIDs == rhs.faceIDs
            && lhs.name == rhs.name
            && lhs.skipState == rhs.skipState
            && lhs.needsReview == rhs.needsReview
    }
}

struct FaceRenameRow: Identifiable, Equatable {
    let id: URL
    let source: URL
    var proposedName: String
    var include: Bool
    var status: String
    var peopleNames: [String]
    var hasUncertain: Bool

    var originalName: String { source.lastPathComponent }
}

struct FaceRenameConflict: Identifiable, Equatable {
    let id = UUID()
    let proposedName: String
    let sources: [URL]
}

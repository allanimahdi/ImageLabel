import Foundation

struct VisionLabel: Identifiable, Hashable, Codable {
    var id: String { description.lowercased() }
    let description: String
    let score: Double
}

enum ImageItemStatus: Equatable {
    case pending
    case labeling
    case labeled
    case failed(String)
    case renamed
    case grouped
}

struct ImageItem: Identifiable, Hashable {
    let id: URL
    let url: URL
    var labels: [VisionLabel] = []
    var status: ImageItemStatus = .pending
    var proposedName: String?
    var errorMessage: String?

    var fileName: String { url.lastPathComponent }
    var fileExtension: String {
        url.pathExtension.isEmpty ? "jpg" : url.pathExtension.lowercased()
    }

    var topLabel: VisionLabel? {
        labels.max(by: { $0.score < $1.score })
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ImageItem, rhs: ImageItem) -> Bool {
        lhs.id == rhs.id
            && lhs.labels == rhs.labels
            && lhs.status == rhs.status
            && lhs.proposedName == rhs.proposedName
            && lhs.errorMessage == rhs.errorMessage
    }
}

extension ImageItemStatus {
    var displayText: String {
        switch self {
        case .pending: return "Pending"
        case .labeling: return "Labeling…"
        case .labeled: return "Labeled"
        case .failed: return "Failed"
        case .renamed: return "Renamed"
        case .grouped: return "Grouped"
        }
    }
}

import Foundation

enum ProcessFolderStep: Int, CaseIterable, Identifiable {
    case select = 0
    case scanning
    case summary
    case faces
    case labelRename
    case done

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .select: return "Select Folder"
        case .scanning: return "Scan Faces"
        case .summary: return "Split Summary"
        case .faces: return "Rename by Faces"
        case .labelRename: return "Label & Group"
        case .done: return "Done"
        }
    }
}

import Foundation

enum FilenameSanitizer {
    /// Turns a Vision label into a filesystem-safe basename (no extension, no score).
    static func basename(from label: String) -> String {
        let lowered = label.lowercased()
        let replaced = lowered
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "\\", with: " ")
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: " -_"))
        let filtered = replaced.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " }
        let collapsed = String(filtered)
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
            .joined(separator: "_")
        return collapsed.isEmpty ? "untitled" : collapsed
    }

    /// Returns a unique URL under `directory` for `basename.ext`, appending `_2`, `_3`, …
    /// Pass `allowing` when the destination may already be the source file (self-rename).
    static func uniqueURL(
        directory: URL,
        basename: String,
        ext: String,
        reserved: inout Set<String>,
        allowing: URL? = nil
    ) -> URL {
        let cleanExt = ext.lowercased()
        var candidate = "\(basename).\(cleanExt)"
        var index = 2
        while isTaken(
            name: candidate,
            directory: directory,
            reserved: reserved,
            allowing: allowing
        ) {
            candidate = "\(basename)_\(index).\(cleanExt)"
            index += 1
        }
        reserved.insert(candidate.lowercased())
        return directory.appendingPathComponent(candidate)
    }

    private static func isTaken(
        name: String,
        directory: URL,
        reserved: Set<String>,
        allowing: URL?
    ) -> Bool {
        if reserved.contains(name.lowercased()) { return true }
        let url = directory.appendingPathComponent(name)
        if let allowing, url.standardizedFileURL == allowing.standardizedFileURL {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

import Foundation

enum FaceNameOrder: String, CaseIterable, Identifiable {
    case leftToRight = "Left → Right"
    case alphabetical = "Alphabetical"

    var id: String { rawValue }
}

enum FaceFilenameBuilder {
    /// Sanitizes a person display name for use in filenames (keeps letters/digits; spaces → nothing joining Camel-ish tokens).
    static func sanitizePersonName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: " -_'"))
        let filtered = String(trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " })
        let parts = filtered
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return "" }
        // Join multi-word names without spaces: "Mary Jane" → "MaryJane"
        return parts.joined()
    }

    /// Builds basename like `Mahdi-Marija` from ordered person names (already sanitized).
    static func basename(fromPersonNames names: [String]) -> String? {
        let cleaned = names.map(sanitizePersonName).filter { !$0.isEmpty }
        let unique = dedupePreservingOrder(cleaned)
        guard !unique.isEmpty else { return nil }
        return unique.joined(separator: "-")
    }

    /// Collision-safe destination using `-002`, `-003`, … before the extension (spec).
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
        while isTaken(name: candidate, directory: directory, reserved: reserved, allowing: allowing) {
            let suffix = String(format: "-%03d", index)
            candidate = "\(basename)\(suffix).\(cleanExt)"
            index += 1
        }
        reserved.insert(candidate.lowercased())
        return directory.appendingPathComponent(candidate)
    }

    private static func dedupePreservingOrder(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in names {
            let key = name.lowercased()
            if seen.insert(key).inserted {
                result.append(name)
            }
        }
        return result
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

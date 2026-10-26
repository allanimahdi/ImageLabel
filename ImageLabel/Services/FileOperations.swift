import Foundation

struct RenamePlan: Identifiable, Hashable {
    let id: URL
    let source: URL
    let destination: URL
    let label: String

    var changesName: Bool {
        source.lastPathComponent != destination.lastPathComponent
    }
}

struct GroupPlan: Identifiable, Hashable {
    let id: URL
    let source: URL
    let destination: URL
    /// Destination folder name (user topic or coarse main category).
    let topic: String
    /// Vision label that drove auto-group assignment (nil for user-picked topic).
    let matchedLabel: String?

    var movesFile: Bool {
        source.standardizedFileURL != destination.standardizedFileURL
    }

    init(id: URL, source: URL, destination: URL, topic: String, matchedLabel: String? = nil) {
        self.id = id
        self.source = source
        self.destination = destination
        self.topic = topic
        self.matchedLabel = matchedLabel
    }
}

enum FileOperations {
    static func buildRenamePlans(for items: [ImageItem]) -> [RenamePlan] {
        guard let first = items.first else { return [] }
        let directory = first.url.deletingLastPathComponent()
        var reserved = Set(
            (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
                .map { $0.lowercased() } ?? []
        )
        // Allow overwriting a file with itself (same path after sanitize).
        var plans: [RenamePlan] = []

        for item in items {
            guard let top = item.topLabel else { continue }
            let base = FilenameSanitizer.basename(from: top.description)
            reserved.remove(item.fileName.lowercased())
            let dest = FilenameSanitizer.uniqueURL(
                directory: directory,
                basename: base,
                ext: item.fileExtension,
                reserved: &reserved,
                allowing: item.url
            )
            plans.append(RenamePlan(id: item.id, source: item.url, destination: dest, label: top.description))
        }
        return plans
    }

    static func applyRenames(_ plans: [RenamePlan]) throws -> [(from: URL, to: URL)] {
        var applied: [(from: URL, to: URL)] = []
        let fm = FileManager.default
        for plan in plans where plan.changesName {
            // Two-step rename if destination exists as another file (shouldn't with uniqueURL).
            if fm.fileExists(atPath: plan.destination.path) {
                throw CocoaError(.fileWriteFileExists)
            }
            try fm.moveItem(at: plan.source, to: plan.destination)
            applied.append((plan.source, plan.destination))
        }
        return applied
    }

    static func undoRenames(_ applied: [(from: URL, to: URL)]) {
        let fm = FileManager.default
        for pair in applied.reversed() {
            try? fm.moveItem(at: pair.to, to: pair.from)
        }
    }

    /// Groups images that include `topic` (case-insensitive) into `folder/topic/`.
    static func buildGroupPlans(for items: [ImageItem], topic: String, root: URL) -> [GroupPlan] {
        let folderName = FilenameSanitizer.basename(from: topic)
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        var reserved = Set(
            (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?
                .map { $0.lowercased() } ?? []
        )
        let needle = topic.lowercased()
        var plans: [GroupPlan] = []

        for item in items {
            let matches = item.labels.contains { $0.description.lowercased() == needle }
            guard matches else { continue }

            let existingBase = item.url.deletingPathExtension().lastPathComponent
            let chosenBase = FilenameSanitizer.basename(from: existingBase)
            let dest = FilenameSanitizer.uniqueURL(
                directory: folder,
                basename: chosenBase,
                ext: item.fileExtension,
                reserved: &reserved,
                allowing: item.url
            )
            plans.append(GroupPlan(id: item.id, source: item.url, destination: dest, topic: topic))
        }
        return plans
    }

    /// Auto-group: each labeled image → one coarse main-category folder under `root`.
    static func buildAutoGroupPlans(for items: [ImageItem], root: URL) -> [GroupPlan] {
        var reservedByFolder: [String: Set<String>] = [:]
        var plans: [GroupPlan] = []

        for item in items {
            guard let assignment = MainCategoryMapper.assign(labels: item.labels) else { continue }
            let folderName = assignment.category.folderName
            let folder = root.appendingPathComponent(folderName, isDirectory: true)

            var reserved = reservedByFolder[folderName] ?? Set(
                (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?
                    .map { $0.lowercased() } ?? []
            )

            let existingBase = item.url.deletingPathExtension().lastPathComponent
            let chosenBase = FilenameSanitizer.basename(from: existingBase)
            let dest = FilenameSanitizer.uniqueURL(
                directory: folder,
                basename: chosenBase,
                ext: item.fileExtension,
                reserved: &reserved,
                allowing: item.url
            )
            reservedByFolder[folderName] = reserved

            // Skip no-ops (already sitting in the right category folder with the same name).
            guard item.url.standardizedFileURL != dest.standardizedFileURL else { continue }

            plans.append(
                GroupPlan(
                    id: item.id,
                    source: item.url,
                    destination: dest,
                    topic: folderName,
                    matchedLabel: assignment.matchedLabel
                )
            )
        }

        return plans.sorted {
            if $0.topic != $1.topic {
                return $0.topic.localizedStandardCompare($1.topic) == .orderedAscending
            }
            return $0.source.lastPathComponent.localizedStandardCompare($1.source.lastPathComponent)
                == .orderedAscending
        }
    }

    static func applyGroups(_ plans: [GroupPlan]) throws -> [(from: URL, to: URL)] {
        let fm = FileManager.default
        var applied: [(from: URL, to: URL)] = []
        for plan in plans where plan.movesFile {
            let dir = plan.destination.deletingLastPathComponent()
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: plan.destination.path) {
                throw CocoaError(.fileWriteFileExists)
            }
            try fm.moveItem(at: plan.source, to: plan.destination)
            applied.append((plan.source, plan.destination))
        }
        return applied
    }
}

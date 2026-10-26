import AppKit
import Foundation
import SwiftUI

@MainActor
final class LabelingSession: ObservableObject {
    @Published var folderURL: URL?
    @Published var items: [ImageItem] = []
    @Published var isLabeling = false
    @Published var isBusy = false
    @Published var progressCompleted = 0
    @Published var progressTotal = 0
    @Published var statusMessage: String?
    @Published var renamePreview: [RenamePlan] = []
    @Published var showRenamePreview = false
    @Published var groupPreview: [GroupPlan] = []
    @Published var showGroupPreview = false
    @Published var selectedTopic: String?
    @Published var lastUndo: (() -> Void)?

    var availableTopics: [String] {
        var counts: [String: Int] = [:]
        for item in items {
            for label in item.labels {
                counts[label.description, default: 0] += 1
            }
        }
        return counts.keys.sorted {
            let lhs = counts[$0, default: 0]
            let rhs = counts[$1, default: 0]
            if lhs != rhs { return lhs > rhs }
            return $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    var labeledCount: Int {
        items.filter {
            if case .failed = $0.status { return false }
            return !$0.labels.isEmpty
        }.count
    }

    var failedCount: Int {
        items.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
        panel.message = "Choose a folder of images to label."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFolder(url)
    }

    func loadFolder(_ url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        folderURL = url
        lastUndo = nil
        renamePreview = []
        groupPreview = []
        selectedTopic = nil
        statusMessage = nil

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            items = []
            statusMessage = "Could not read folder contents."
            return
        }

        items = contents
            .filter { SupportedImageTypes.isSupported(url: $0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { ImageItem(id: $0, url: $0) }

        statusMessage = items.isEmpty
            ? "No supported images found (jpg, png, heic, webp, …)."
            : "Loaded \(items.count) image\(items.count == 1 ? "" : "s")."
    }

    func labelAll(using settings: SettingsStore) async {
        guard !items.isEmpty else { return }
        guard !isLabeling else { return }

        let client: VisionClient
        do {
            client = try settings.makeVisionClient()
        } catch {
            statusMessage = error.localizedDescription
            return
        }

        isLabeling = true
        isBusy = true
        progressCompleted = 0
        progressTotal = items.count
        statusMessage = "Labeling…"
        defer {
            isLabeling = false
            isBusy = false
        }

        for index in items.indices {
            items[index].status = .labeling
            items[index].errorMessage = nil
            do {
                let labels = try await client.detectLabels(imageURL: items[index].url)
                items[index].labels = labels
                if let top = labels.first {
                    items[index].proposedName =
                        "\(FilenameSanitizer.basename(from: top.description)).\(items[index].fileExtension)"
                }
                items[index].status = .labeled
            } catch {
                items[index].status = .failed(error.localizedDescription)
                items[index].errorMessage = error.localizedDescription
                items[index].labels = []
                items[index].proposedName = nil
            }
            progressCompleted = index + 1
        }

        refreshProposedNamesFromTopLabels()

        let ok = labeledCount
        let bad = failedCount
        if bad > 0, let firstError = items.compactMap(\.errorMessage).first {
            statusMessage = "Labeled \(ok) of \(items.count) (\(bad) failed). \(firstError)"
        } else {
            statusMessage = "Labeled \(ok) of \(items.count)"
                + (bad > 0 ? " (\(bad) failed)." : ".")
        }

        // Happy path: after labels arrive, offer rename to top labels (preview → apply).
        if ok > 0 {
            statusMessage = (statusMessage ?? "") + " Review Rename to apply on disk."
            prepareRenamePreview()
        }
    }

    /// Collision-safe proposed filenames from each item’s best-score Vision label (no score in the name).
    func refreshProposedNamesFromTopLabels() {
        let eligible = items.filter { $0.topLabel != nil }
        let plans = FileOperations.buildRenamePlans(for: eligible)
        let bySource = Dictionary(uniqueKeysWithValues: plans.map { ($0.source, $0) })
        for index in items.indices {
            if let plan = bySource[items[index].url] {
                items[index].proposedName = plan.destination.lastPathComponent
            }
        }
    }

    var pendingRenameCount: Int {
        FileOperations.buildRenamePlans(for: items.filter { $0.topLabel != nil })
            .filter(\.changesName)
            .count
    }

    func prepareRenamePreview() {
        let eligible = items.filter { $0.topLabel != nil }
        renamePreview = FileOperations.buildRenamePlans(for: eligible)
        refreshProposedNamesFromTopLabels()
        showRenamePreview = true
    }

    func applyRenamePreview() {
        let plans = renamePreview
        showRenamePreview = false
        isBusy = true
        defer { isBusy = false }

        do {
            let applied = try FileOperations.applyRenames(plans)
            var urlMap: [URL: URL] = [:]
            for plan in plans {
                urlMap[plan.source] = plan.destination
            }
            for index in items.indices {
                if let dest = urlMap[items[index].url] {
                    items[index] = ImageItem(
                        id: dest,
                        url: dest,
                        labels: items[index].labels,
                        status: .renamed,
                        proposedName: dest.lastPathComponent,
                        errorMessage: nil
                    )
                }
            }
            let snapshot = applied
            lastUndo = { [weak self] in
                FileOperations.undoRenames(snapshot)
                self?.reloadAfterUndo()
            }
            statusMessage = applied.isEmpty
                ? "Nothing to rename (names already match top labels)."
                : "Renamed \(applied.count) file\(applied.count == 1 ? "" : "s") to top Vision labels. Undo available."
        } catch {
            statusMessage = "Rename failed: \(error.localizedDescription)"
        }
    }

    func prepareGroupPreview(topic: String) {
        guard let root = folderURL else { return }
        selectedTopic = topic
        groupPreview = FileOperations.buildGroupPlans(for: items, topic: topic, root: root)
        showGroupPreview = true
    }

    func applyGroupPreview() {
        let plans = groupPreview
        showGroupPreview = false
        isBusy = true
        defer { isBusy = false }

        do {
            let applied = try FileOperations.applyGroups(plans)
            var urlMap: [URL: URL] = [:]
            for plan in plans {
                urlMap[plan.source] = plan.destination
            }
            for index in items.indices {
                if let dest = urlMap[items[index].url] {
                    items[index] = ImageItem(
                        id: dest,
                        url: dest,
                        labels: items[index].labels,
                        status: .grouped,
                        proposedName: items[index].proposedName,
                        errorMessage: nil
                    )
                }
            }
            let snapshot = applied
            lastUndo = { [weak self] in
                FileOperations.undoRenames(snapshot)
                self?.reloadAfterUndo()
            }
            statusMessage = "Moved \(applied.count) file\(applied.count == 1 ? "" : "s") into “\(selectedTopic ?? "topic")”. Undo available."
        } catch {
            statusMessage = "Group failed: \(error.localizedDescription)"
        }
    }

    func undoLast() {
        lastUndo?()
        lastUndo = nil
        statusMessage = "Undo complete."
    }

    private func reloadAfterUndo() {
        guard let folder = folderURL else { return }
        // Preserve labels by matching basename where possible is hard after moves;
        // simply reload folder listing and clear labels for safety.
        loadFolder(folder)
        statusMessage = "Undo complete — folder reloaded. Re-run Label if needed."
    }
}

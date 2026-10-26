import AppKit
import Foundation
import SwiftUI

@MainActor
final class FaceRenameSession: ObservableObject {
    @Published var step: FaceRenameStep = .select
    @Published var photoURLs: [URL] = []
    @Published var folderURL: URL?
    @Published var isBusy = false
    @Published var progressCompleted = 0
    @Published var progressTotal = 0
    @Published var statusMessage: String?
    @Published var faces: [DetectedFace] = []
    @Published var groups: [FacePersonGroup] = []
    @Published var previewRows: [FaceRenameRow] = []
    @Published var lastUndo: (() -> Void)?
    @Published var mergeSourceID: UUID?

    private let identityStore: FaceIdentityStore
    private var faceByID: [UUID: DetectedFace] = [:]

    init(identityStore: FaceIdentityStore) {
        self.identityStore = identityStore
    }

    var photoCount: Int { photoURLs.count }

    func reset() {
        step = .select
        photoURLs = []
        folderURL = nil
        isBusy = false
        progressCompleted = 0
        progressTotal = 0
        statusMessage = nil
        faces = []
        groups = []
        previewRows = []
        lastUndo = nil
        mergeSourceID = nil
        faceByID = [:]
    }

    // MARK: - Select

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
        panel.message = "Choose a folder of photos to rename by faces."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = url.startAccessingSecurityScopedResource()
        folderURL = url
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        photoURLs = contents
            .filter { SupportedImageTypes.isSupported(url: $0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        statusMessage = photoURLs.isEmpty
            ? "No supported images in that folder."
            : "Selected \(photoURLs.count) photo\(photoURLs.count == 1 ? "" : "s")."
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = SupportedImageTypes.contentTypes
        panel.prompt = "Select"
        panel.message = "Choose photos to rename by faces."
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls.filter { SupportedImageTypes.isSupported(url: $0) }
        for url in urls { _ = url.startAccessingSecurityScopedResource() }
        photoURLs = urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        folderURL = photoURLs.first?.deletingLastPathComponent()
        statusMessage = photoURLs.isEmpty
            ? "No supported images selected."
            : "Selected \(photoURLs.count) photo\(photoURLs.count == 1 ? "" : "s")."
    }

    // MARK: - Detect & cluster

    func startDetection(settings: SettingsStore) async {
        guard !photoURLs.isEmpty else { return }
        step = .detect
        isBusy = true
        progressCompleted = 0
        progressTotal = photoURLs.count
        statusMessage = "Detecting faces…"
        faces = []
        groups = []
        faceByID = [:]
        defer { isBusy = false }

        let urls = photoURLs
        var collected: [DetectedFace] = []
        for (index, url) in urls.enumerated() {
            do {
                let detected = try await Task.detached(priority: .userInitiated) {
                    try FaceDetectionService.detectFaces(in: url)
                }.value
                collected.append(contentsOf: detected)
            } catch {
                // Continue batch; note in status
                statusMessage = "Skipped \(url.lastPathComponent): \(error.localizedDescription)"
            }
            progressCompleted = index + 1
        }

        faces = collected
        for face in collected { faceByID[face.id] = face }

        guard !collected.isEmpty else {
            statusMessage = "No faces found in the selected photos."
            return
        }

        statusMessage = "Grouping \(collected.count) face\(collected.count == 1 ? "" : "s")…"
        let threshold = Float(settings.faceMatchThreshold)
        let prints = collected.map(\.featurePrint)
        let clusters = FaceClusteringService.cluster(count: collected.count, threshold: threshold) { i, j in
            FaceDetectionService.distance(prints[i], prints[j])
        }

        let reviewDistance = threshold * 0.85
        var built: [FacePersonGroup] = []
        for cluster in clusters {
            let faceIDs = cluster.map { collected[$0].id }
            let thumb = collected[cluster[0]].thumbnail
            var name = ""
            var skip: FaceSkipState = .named
            var needsReview = false

            if settings.persistFaceIdentities,
               let match = identityStore.bestMatch(to: collected[cluster[0]].featurePrint, threshold: threshold) {
                name = match.identity.name
                skip = .named
                needsReview = match.distance > reviewDistance
            }

            built.append(
                FacePersonGroup(
                    id: UUID(),
                    faceIDs: faceIDs,
                    displayThumbnail: thumb,
                    name: name,
                    skipState: skip,
                    needsReview: needsReview
                )
            )
        }

        // Largest clusters first for naming UX
        groups = built.sorted { photoCount(for: $0) > photoCount(for: $1) }
        statusMessage = "Found \(groups.count) person\(groups.count == 1 ? "" : "s") across \(collected.count) faces."
        step = .identify
    }

    func photoCount(for group: FacePersonGroup) -> Int {
        let urls = Set(group.faceIDs.compactMap { faceByID[$0]?.imageURL })
        return urls.count
    }

    func faces(in group: FacePersonGroup) -> [DetectedFace] {
        group.faceIDs.compactMap { faceByID[$0] }
    }

    // MARK: - Identify

    func setName(_ name: String, for groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].name = name
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            groups[index].skipState = .named
            groups[index].needsReview = false
        }
    }

    func markUnknown(_ groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].skipState = .unknown
        groups[index].name = ""
        groups[index].needsReview = false
    }

    func markSkipped(_ groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].skipState = .skipped
        groups[index].name = ""
        groups[index].needsReview = false
    }

    func beginMerge(from groupID: UUID) {
        mergeSourceID = groupID
        statusMessage = "Select another person to merge into."
    }

    func completeMerge(into targetID: UUID) {
        guard let sourceID = mergeSourceID,
              sourceID != targetID,
              let sIdx = groups.firstIndex(where: { $0.id == sourceID }),
              let tIdx = groups.firstIndex(where: { $0.id == targetID })
        else {
            mergeSourceID = nil
            return
        }
        groups[tIdx].faceIDs.append(contentsOf: groups[sIdx].faceIDs)
        if groups[tIdx].name.isEmpty { groups[tIdx].name = groups[sIdx].name }
        groups[tIdx].skipState = .named
        groups.remove(at: sIdx)
        mergeSourceID = nil
        statusMessage = "Merged face groups."
    }

    func cancelMerge() {
        mergeSourceID = nil
        statusMessage = nil
    }

    /// Split one face out of a multi-face group into its own unnamed person.
    func splitFace(_ faceID: UUID, from groupID: UUID) {
        guard let gIdx = groups.firstIndex(where: { $0.id == groupID }),
              groups[gIdx].faceIDs.count > 1,
              let fIdx = groups[gIdx].faceIDs.firstIndex(of: faceID),
              let face = faceByID[faceID]
        else { return }
        groups[gIdx].faceIDs.remove(at: fIdx)
        groups.append(
            FacePersonGroup(
                id: UUID(),
                faceIDs: [faceID],
                displayThumbnail: face.thumbnail,
                name: "",
                skipState: .named,
                needsReview: true
            )
        )
        statusMessage = "Split face into a new person. Assign a name."
    }

    func generatePhotoNames(settings: SettingsStore) {
        guard let root = folderURL ?? photoURLs.first?.deletingLastPathComponent() else { return }

        // Map face → group
        var faceToGroup: [UUID: FacePersonGroup] = [:]
        for group in groups {
            for faceID in group.faceIDs {
                faceToGroup[faceID] = group
            }
        }

        // Persist confirmed names if enabled
        if settings.persistFaceIdentities {
            for group in groups where group.skipState == .named {
                let trimmed = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, let thumb = group.displayThumbnail else { continue }
                identityStore.upsert(name: trimmed, thumbnail: thumb)
            }
        }

        var reserved = Set(
            (try? FileManager.default.contentsOfDirectory(atPath: root.path))?
                .map { $0.lowercased() } ?? []
        )

        var rows: [FaceRenameRow] = []
        for url in photoURLs {
            let imageFaces = faces.filter { $0.imageURL == url }
            if imageFaces.isEmpty {
                rows.append(
                    FaceRenameRow(
                        id: url,
                        source: url,
                        proposedName: url.lastPathComponent,
                        include: false,
                        status: "No faces — keep original",
                        peopleNames: [],
                        hasUncertain: false
                    )
                )
                continue
            }

            // Build (midX, name) for named people only
            var named: [(midX: CGFloat, name: String)] = []
            var hasUncertain = false
            var onlyUnknownOrSkip = true

            for face in imageFaces {
                guard let group = faceToGroup[face.id] else { continue }
                switch group.skipState {
                case .skipped:
                    continue
                case .unknown:
                    hasUncertain = true
                case .named:
                    let trimmed = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        hasUncertain = true
                    } else {
                        onlyUnknownOrSkip = false
                        named.append((face.midX, trimmed))
                        if group.needsReview { hasUncertain = true }
                    }
                }
            }

            if onlyUnknownOrSkip || named.isEmpty {
                rows.append(
                    FaceRenameRow(
                        id: url,
                        source: url,
                        proposedName: url.lastPathComponent,
                        include: false,
                        status: "Unknown/skipped only — keep original",
                        peopleNames: [],
                        hasUncertain: hasUncertain
                    )
                )
                continue
            }

            let orderedNames: [String]
            switch settings.faceNameOrder {
            case .alphabetical:
                orderedNames = named.map(\.name).sorted {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                }
            case .leftToRight:
                orderedNames = named.sorted { $0.midX < $1.midX }.map(\.name)
            }

            guard let base = FaceFilenameBuilder.basename(fromPersonNames: orderedNames) else {
                rows.append(
                    FaceRenameRow(
                        id: url,
                        source: url,
                        proposedName: url.lastPathComponent,
                        include: false,
                        status: "Could not build name",
                        peopleNames: orderedNames,
                        hasUncertain: true
                    )
                )
                continue
            }

            reserved.remove(url.lastPathComponent.lowercased())
            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            let dest = FaceFilenameBuilder.uniqueURL(
                directory: root,
                basename: base,
                ext: ext,
                reserved: &reserved,
                allowing: url
            )
            let changes = dest.lastPathComponent != url.lastPathComponent
            rows.append(
                FaceRenameRow(
                    id: url,
                    source: url,
                    proposedName: dest.lastPathComponent,
                    include: changes,
                    status: changes ? "Ready" : "Already named",
                    peopleNames: orderedNames,
                    hasUncertain: hasUncertain
                )
            )
        }

        previewRows = rows
        step = .preview
        let ready = rows.filter(\.include).count
        statusMessage = "Preview ready — \(ready) photo\(ready == 1 ? "" : "s") to rename."
    }

    // MARK: - Apply

    func applyRenames() {
        isBusy = true
        defer { isBusy = false }

        var applied: [(from: URL, to: URL)] = []
        var failures = 0
        let root = folderURL ?? photoURLs.first?.deletingLastPathComponent()

        for index in previewRows.indices where previewRows[index].include {
            let row = previewRows[index]
            guard let root else { continue }
            let dest = root.appendingPathComponent(row.proposedName)
            if dest.standardizedFileURL == row.source.standardizedFileURL {
                previewRows[index].status = "Skipped (same name)"
                continue
            }
            if FileManager.default.fileExists(atPath: dest.path) {
                previewRows[index].status = "Conflict — file exists"
                previewRows[index].include = false
                failures += 1
                continue
            }
            do {
                try FileManager.default.moveItem(at: row.source, to: dest)
                applied.append((row.source, dest))
                previewRows[index].status = "Renamed"
                previewRows[index].include = false
                // Update session photo URL list
                if let p = photoURLs.firstIndex(of: row.source) {
                    photoURLs[p] = dest
                }
            } catch {
                previewRows[index].status = "Failed: \(error.localizedDescription)"
                failures += 1
            }
        }

        let snapshot = applied
        lastUndo = { [weak self] in
            FaceRenameSession.undoMoves(snapshot)
            self?.statusMessage = "Undo complete."
            self?.lastUndo = nil
        }
        statusMessage = "Renamed \(applied.count) photo\(applied.count == 1 ? "" : "s")"
            + (failures > 0 ? " (\(failures) failed)." : ".")
            + (applied.isEmpty ? "" : " Undo available.")
    }

    private static func undoMoves(_ applied: [(from: URL, to: URL)]) {
        for pair in applied.reversed() {
            try? FileManager.default.moveItem(at: pair.to, to: pair.from)
        }
    }

    func updateProposedName(_ name: String, for id: URL) {
        guard let index = previewRows.firstIndex(where: { $0.id == id }) else { return }
        previewRows[index].proposedName = name
        previewRows[index].status = "Edited"
        previewRows[index].include = true
    }

    func setInclude(_ include: Bool, for id: URL) {
        guard let index = previewRows.firstIndex(where: { $0.id == id }) else { return }
        previewRows[index].include = include
    }
}

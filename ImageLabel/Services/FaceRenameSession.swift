import AppKit
import Foundation
import SwiftUI
import Vision

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

    // MARK: Verification
    @Published var verificationQueue: [FaceVerificationItem] = []
    @Published var verificationIndex = 0
    @Published var requiredVerifications = 0
    @Published var verifiedCount = 0
    /// Draft name for the current verification card.
    @Published var verificationDraftName = ""

    private let identityStore: FaceIdentityStore
    private var faceByID: [UUID: DetectedFace] = [:]
    private var faceToGroupID: [UUID: UUID] = [:]
    /// Confirmed faces only — used as trusted training refs for this batch.
    private var trustedRefs: [TrustedFaceRef] = []
    private var matchThreshold: Float = 0.65

    private struct TrustedFaceRef {
        let name: String
        let featurePrint: VNFeaturePrintObservation
        let thumbnail: NSImage
        let faceID: UUID
    }

    init(identityStore: FaceIdentityStore) {
        self.identityStore = identityStore
    }

    var photoCount: Int { photoURLs.count }

    var currentVerificationItem: FaceVerificationItem? {
        guard verificationQueue.indices.contains(verificationIndex) else { return nil }
        return verificationQueue[verificationIndex]
    }

    var currentVerificationFace: DetectedFace? {
        guard let item = currentVerificationItem else { return nil }
        return faceByID[item.faceID]
    }

    var verificationMinimumMet: Bool { verifiedCount >= requiredVerifications && requiredVerifications > 0
        || (requiredVerifications == 0 && !faces.isEmpty) }

    var canFinishVerification: Bool {
        verificationMinimumMet && verificationQueue.allSatisfy { $0.resolution != nil }
            || (verificationMinimumMet && verifiedCount >= requiredVerifications)
    }

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
        faceToGroupID = [:]
        trustedRefs = []
        verificationQueue = []
        verificationIndex = 0
        requiredVerifications = 0
        verifiedCount = 0
        verificationDraftName = ""
        matchThreshold = 0.65
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
        faceToGroupID = [:]
        trustedRefs = []
        verificationQueue = []
        verificationIndex = 0
        requiredVerifications = 0
        verifiedCount = 0
        matchThreshold = Float(settings.faceMatchThreshold)
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
        let threshold = matchThreshold
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
            var suggestedDistance: Float?

            if settings.persistFaceIdentities,
               let match = identityStore.bestMatch(to: collected[cluster[0]].featurePrint, threshold: threshold) {
                name = match.identity.name
                skip = .named
                needsReview = match.distance > reviewDistance
                suggestedDistance = match.distance
            }

            let group = FacePersonGroup(
                id: UUID(),
                faceIDs: faceIDs,
                displayThumbnail: thumb,
                name: name,
                skipState: skip,
                needsReview: needsReview || (suggestedDistance == nil && name.isEmpty)
            )
            built.append(group)
            for faceID in faceIDs {
                faceToGroupID[faceID] = group.id
            }
        }

        groups = built.sorted { photoCount(for: $0) > photoCount(for: $1) }
        buildVerificationQueue(settings: settings)
        statusMessage =
            "Found \(groups.count) person\(groups.count == 1 ? "" : "s") across \(collected.count) faces. "
            + "Verify \(requiredVerifications) sample face\(requiredVerifications == 1 ? "" : "s")."
        step = .verify
        prepareDraftForCurrentItem()
    }

    private func buildVerificationQueue(settings: SettingsStore) {
        let threshold = matchThreshold
        let highConfidence = threshold * 0.70
        let nearDupThreshold = threshold * 0.40

        // Near-duplicate keys via union-find on close pairs
        let faceList = faces
        var parent = Array(faceList.indices)
        func find(_ x: Int) -> Int {
            if parent[x] != x { parent[x] = find(parent[x]) }
            return parent[x]
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }
        if faceList.count > 1 {
            for i in 0..<(faceList.count - 1) {
                for j in (i + 1)..<faceList.count {
                    let d = FaceDetectionService.distance(faceList[i].featurePrint, faceList[j].featurePrint)
                    if d <= nearDupThreshold { union(i, j) }
                }
            }
        }

        var candidates: [FaceVerificationSampler.Candidate] = []
        for (index, face) in faceList.enumerated() {
            guard let groupID = faceToGroupID[face.id],
                  let group = groups.first(where: { $0.id == groupID })
            else { continue }

            let uncertainty: Float
            if group.name.isEmpty {
                uncertainty = 1.0
            } else if group.needsReview {
                uncertainty = 0.75
            } else if let match = identityStore.bestMatch(to: face.featurePrint, threshold: threshold) {
                // Closer to threshold → more uncertain
                let span = max(threshold - highConfidence, 0.001)
                uncertainty = min(1, max(0, (match.distance - highConfidence) / span))
            } else {
                uncertainty = 0.9
            }

            candidates.append(
                FaceVerificationSampler.Candidate(
                    faceID: face.id,
                    groupID: groupID,
                    uncertainty: uncertainty,
                    diversityBucket: FaceVerificationSampler.diversityBucket(
                        boundingBox: face.boundingBox,
                        midX: face.midX
                    ),
                    nearDuplicateKey: find(index)
                )
            )
        }

        requiredVerifications = FaceVerificationSampler.requiredSampleSize(
            photoCount: photoURLs.count,
            uniqueFaceCount: faces.count
        )
        let selectedIDs = FaceVerificationSampler.selectFaceIDs(
            from: candidates,
            limit: max(requiredVerifications, 0)
        )

        verificationQueue = selectedIDs.map { faceID in
            let suggested = suggestedName(for: faceID, settings: settings)
            return FaceVerificationItem(
                id: faceID,
                faceID: faceID,
                suggestedName: suggested,
                resolution: nil
            )
        }
        verificationIndex = 0
        verifiedCount = 0
    }

    private func suggestedName(for faceID: UUID, settings: SettingsStore) -> String? {
        if let groupID = faceToGroupID[faceID],
           let group = groups.first(where: { $0.id == groupID }) {
            let trimmed = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        guard let face = faceByID[faceID] else { return nil }
        if (settings.persistFaceIdentities || !identityStore.identities.isEmpty),
           let match = identityStore.bestMatch(to: face.featurePrint, threshold: matchThreshold) {
            return match.identity.name
        }
        // Trusted refs from this session
        if let trusted = bestTrustedMatch(to: face.featurePrint, maxDistance: matchThreshold) {
            return trusted.name
        }
        return nil
    }

    private func prepareDraftForCurrentItem() {
        if let item = currentVerificationItem {
            verificationDraftName = item.suggestedName ?? ""
        } else {
            verificationDraftName = ""
        }
    }

    // MARK: - Verification actions

    func confirmCurrentVerification(settings: SettingsStore) {
        let name = verificationDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        resolveCurrent(with: .confirmed(name: name), settings: settings)
    }

    func confirmSuggestedVerification(settings: SettingsStore) {
        guard let suggested = currentVerificationItem?.suggestedName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !suggested.isEmpty
        else { return }
        verificationDraftName = suggested
        resolveCurrent(with: .confirmed(name: suggested), settings: settings)
    }

    func markCurrentUnknown(settings: SettingsStore) {
        resolveCurrent(with: .unknown, settings: settings)
    }

    func skipCurrentVerification(settings: SettingsStore) {
        resolveCurrent(with: .skipped, settings: settings)
    }

    private func resolveCurrent(with resolution: FaceVerificationResolution, settings: SettingsStore) {
        guard verificationQueue.indices.contains(verificationIndex) else { return }
        let previous = verificationQueue[verificationIndex].resolution
        verificationQueue[verificationIndex].resolution = resolution

        if previous?.countsAsVerified == true { verifiedCount = max(0, verifiedCount - 1) }
        if resolution.countsAsVerified { verifiedCount += 1 }

        if case .confirmed(let name) = resolution,
           let face = faceByID[verificationQueue[verificationIndex].faceID] {
            addTrustedRef(name: name, face: face, persist: settings.persistFaceIdentities)
            applyNameToGroup(of: face.id, name: name)
        } else if case .unknown = resolution {
            markGroupUnknown(of: verificationQueue[verificationIndex].faceID)
        }

        advanceAfterResolution(settings: settings)
    }

    private func advanceAfterResolution(settings: SettingsStore) {
        // Move to next unresolved item if any remain in queue
        if let next = verificationQueue.indices.first(where: {
            $0 > verificationIndex && verificationQueue[$0].resolution == nil
        }) {
            verificationIndex = next
            prepareDraftForCurrentItem()
            return
        }
        if let earlier = verificationQueue.indices.first(where: {
            verificationQueue[$0].resolution == nil
        }) {
            verificationIndex = earlier
            prepareDraftForCurrentItem()
            return
        }

        // Queue exhausted — reprocess and open rename preview (adaptive extras via footer if needed).
        if verifiedCount >= requiredVerifications || verificationQueue.allSatisfy({ $0.resolution != nil }) {
            // First pass: offer adaptive ambiguous confirmations before preview.
            finishVerificationAndReprocess(settings: settings, preferPreview: false)
            if step == .identify {
                generatePhotoNames(settings: settings)
            }
        }
    }

    /// Called when the sample queue is exhausted — reprocess, optionally ask for ambiguous faces, else preview.
    func finishVerificationAndReprocess(settings: SettingsStore, preferPreview: Bool = true) {
        guard verifiedCount >= requiredVerifications || faces.isEmpty
            || verificationQueue.allSatisfy({ $0.resolution != nil })
        else {
            statusMessage = "Confirm at least \(requiredVerifications) faces (\(verifiedCount) so far)."
            return
        }
        isBusy = true
        defer { isBusy = false }

        reprocessWithTrustedRefs(settings: settings)

        let ambiguousFaceIDs = faces.compactMap { face -> UUID? in
            guard let groupID = faceToGroupID[face.id],
                  let group = groups.first(where: { $0.id == groupID })
            else { return nil }
            if group.needsReview { return face.id }
            if group.skipState == .named,
               group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return face.id
            }
            return nil
        }

        let alreadyQueued = Set(verificationQueue.map(\.faceID))
        let alreadyVerified = Set(
            verificationQueue.compactMap { item -> UUID? in
                item.countsAsVerified ? item.faceID : nil
            }
        )
        let extra = ambiguousFaceIDs.filter { !alreadyQueued.contains($0) && !alreadyVerified.contains($0) }

        if !extra.isEmpty, verifiedCount >= requiredVerifications, !preferPreview {
            // Adaptive: only ambiguous faces beyond the minimum.
            let additions = Array(extra.prefix(min(extra.count, max(8, requiredVerifications / 2))))
            if !additions.isEmpty {
                for faceID in additions {
                    verificationQueue.append(
                        FaceVerificationItem(
                            id: faceID,
                            faceID: faceID,
                            suggestedName: suggestedName(for: faceID, settings: settings),
                            resolution: nil
                        )
                    )
                }
                requiredVerifications = verifiedCount + additions.count
                if let idx = verificationQueue.firstIndex(where: { $0.resolution == nil }) {
                    verificationIndex = idx
                    prepareDraftForCurrentItem()
                    statusMessage =
                        "Minimum met. \(additions.count) ambiguous face\(additions.count == 1 ? "" : "s") need another look."
                    step = .verify
                    return
                }
            }
        }

        if preferPreview {
            generatePhotoNames(settings: settings)
        } else {
            statusMessage = "Verification complete. Review people or generate names."
            step = .identify
        }
    }

    /// Skip adaptive extras and go to identify for merge/split review.
    func continueAfterMinimum(settings: SettingsStore) {
        reprocessWithTrustedRefs(settings: settings)
        statusMessage = "Using verified references. Review people then generate names."
        step = .identify
    }

    private func addTrustedRef(name: String, face: DetectedFace, persist: Bool) {
        trustedRefs.removeAll {
            $0.faceID == face.id
                || ($0.name.compare(name, options: .caseInsensitive) == .orderedSame
                    && FaceDetectionService.distance($0.featurePrint, face.featurePrint) < matchThreshold * 0.35)
        }
        trustedRefs.append(
            TrustedFaceRef(
                name: name,
                featurePrint: face.featurePrint,
                thumbnail: face.thumbnail,
                faceID: face.id
            )
        )
        if persist {
            identityStore.upsert(name: name, thumbnail: face.thumbnail)
        }
    }

    private func applyNameToGroup(of faceID: UUID, name: String) {
        guard let groupID = faceToGroupID[faceID],
              let index = groups.firstIndex(where: { $0.id == groupID })
        else { return }
        groups[index].name = name
        groups[index].skipState = .named
        groups[index].needsReview = false
        if let face = faceByID[faceID] {
            groups[index].displayThumbnail = face.thumbnail
        }
    }

    private func markGroupUnknown(of faceID: UUID) {
        guard let groupID = faceToGroupID[faceID],
              let index = groups.firstIndex(where: { $0.id == groupID }),
              groups[index].faceIDs.count == 1
        else { return }
        groups[index].skipState = .unknown
        groups[index].name = ""
        groups[index].needsReview = false
    }

    private func bestTrustedMatch(
        to print: VNFeaturePrintObservation,
        maxDistance: Float
    ) -> (name: String, distance: Float)? {
        var best: (String, Float)?
        for ref in trustedRefs {
            let d = FaceDetectionService.distance(print, ref.featurePrint)
            if d <= maxDistance {
                if best == nil || d < best!.1 {
                    best = (ref.name, d)
                }
            }
        }
        return best.map { (name: $0.0, distance: $0.1) }
    }

    /// Auto-assign only high-confidence matches against trusted refs (+ library). Flag ambiguous.
    private func reprocessWithTrustedRefs(settings: SettingsStore) {
        let threshold = matchThreshold
        let highConfidence = threshold * 0.70

        // Build name → faceIDs from trusted + high-confidence assignment
        var assignments: [UUID: (name: String, confident: Bool)] = [:]

        for item in verificationQueue {
            if case .confirmed(let name) = item.resolution {
                assignments[item.faceID] = (name, true)
            } else if case .unknown = item.resolution {
                assignments[item.faceID] = ("", false)
            }
        }

        for face in faces {
            if assignments[face.id] != nil { continue }

            var bestName: String?
            var bestDistance: Float = .greatestFiniteMagnitude

            if let trusted = bestTrustedMatch(to: face.featurePrint, maxDistance: threshold) {
                bestName = trusted.name
                bestDistance = trusted.distance
            }
            if settings.persistFaceIdentities || !identityStore.identities.isEmpty,
               let lib = identityStore.bestMatch(to: face.featurePrint, threshold: threshold),
               lib.distance < bestDistance {
                // Only treat library as assignment source when we have at least one trusted confirm
                // for that name, or persist is on with existing identities — still require high confidence.
                if trustedRefs.contains(where: {
                    $0.name.compare(lib.identity.name, options: .caseInsensitive) == .orderedSame
                }) || settings.persistFaceIdentities {
                    bestName = lib.identity.name
                    bestDistance = lib.distance
                }
            }

            if let name = bestName {
                assignments[face.id] = (name, bestDistance <= highConfidence)
            }
        }

        // Rebuild groups: merge same confident names; leave ambiguous flagged
        var nameBuckets: [String: [UUID]] = [:]
        var unknownSingles: [UUID] = []
        var ambiguousSingles: [(faceID: UUID, name: String)] = []
        var unresolved: [UUID] = []

        for face in faces {
            guard let assignment = assignments[face.id] else {
                unresolved.append(face.id)
                continue
            }
            let trimmed = assignment.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                unknownSingles.append(face.id)
            } else if assignment.confident {
                let key = trimmed.lowercased()
                nameBuckets[key, default: []].append(face.id)
            } else {
                ambiguousSingles.append((face.id, trimmed))
            }
        }

        // Keep original cluster membership for unresolved faces
        var rebuilt: [FacePersonGroup] = []
        var displayNames: [String: String] = [:]
        for ref in trustedRefs {
            displayNames[ref.name.lowercased()] = ref.name
        }

        for (key, faceIDs) in nameBuckets.sorted(by: { $0.key < $1.key }) {
            let display = displayNames[key]
                ?? faceIDs.compactMap { assignments[$0]?.name }.first
                ?? key
            let thumb = faceIDs.compactMap { faceByID[$0]?.thumbnail }.first
            rebuilt.append(
                FacePersonGroup(
                    id: UUID(),
                    faceIDs: faceIDs,
                    displayThumbnail: thumb,
                    name: display,
                    skipState: .named,
                    needsReview: false
                )
            )
        }

        for item in ambiguousSingles {
            rebuilt.append(
                FacePersonGroup(
                    id: UUID(),
                    faceIDs: [item.faceID],
                    displayThumbnail: faceByID[item.faceID]?.thumbnail,
                    name: item.name,
                    skipState: .named,
                    needsReview: true
                )
            )
        }

        for faceID in unknownSingles {
            rebuilt.append(
                FacePersonGroup(
                    id: UUID(),
                    faceIDs: [faceID],
                    displayThumbnail: faceByID[faceID]?.thumbnail,
                    name: "",
                    skipState: .unknown,
                    needsReview: false
                )
            )
        }

        // Unresolved: preserve prior grouping where possible
        let unresolvedSet = Set(unresolved)
        if !unresolvedSet.isEmpty {
            var used = Set<UUID>()
            for group in groups {
                let remaining = group.faceIDs.filter { unresolvedSet.contains($0) && !used.contains($0) }
                guard !remaining.isEmpty else { continue }
                remaining.forEach { used.insert($0) }
                rebuilt.append(
                    FacePersonGroup(
                        id: UUID(),
                        faceIDs: remaining,
                        displayThumbnail: remaining.compactMap { faceByID[$0]?.thumbnail }.first,
                        name: group.name,
                        skipState: group.name.isEmpty ? .named : group.skipState,
                        needsReview: true
                    )
                )
            }
            for faceID in unresolved where !used.contains(faceID) {
                rebuilt.append(
                    FacePersonGroup(
                        id: UUID(),
                        faceIDs: [faceID],
                        displayThumbnail: faceByID[faceID]?.thumbnail,
                        name: "",
                        skipState: .named,
                        needsReview: true
                    )
                )
            }
        }

        groups = rebuilt.sorted { photoCount(for: $0) > photoCount(for: $1) }
        faceToGroupID = [:]
        for group in groups {
            for faceID in group.faceIDs {
                faceToGroupID[faceID] = group.id
            }
        }
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
        for faceID in groups[sIdx].faceIDs {
            faceToGroupID[faceID] = groups[tIdx].id
        }
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
        let newID = UUID()
        groups.append(
            FacePersonGroup(
                id: newID,
                faceIDs: [faceID],
                displayThumbnail: face.thumbnail,
                name: "",
                skipState: .named,
                needsReview: true
            )
        )
        faceToGroupID[faceID] = newID
        statusMessage = "Split face into a new person. Assign a name."
    }

    func generatePhotoNames(settings: SettingsStore) {
        guard let root = folderURL ?? photoURLs.first?.deletingLastPathComponent() else { return }

        var faceToGroup: [UUID: FacePersonGroup] = [:]
        for group in groups {
            for faceID in group.faceIDs {
                faceToGroup[faceID] = group
            }
        }

        // Persist only confirmed / confidently named people — never uncertain auto-matches.
        if settings.persistFaceIdentities {
            for ref in trustedRefs {
                identityStore.upsert(name: ref.name, thumbnail: ref.thumbnail)
            }
            for group in groups where group.skipState == .named && !group.needsReview {
                let trimmed = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, let thumb = group.displayThumbnail else { continue }
                // Prefer already-trusted crops; otherwise store group thumb only if verified.
                let hasTrusted = trustedRefs.contains {
                    $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
                }
                if hasTrusted {
                    identityStore.upsert(name: trimmed, thumbnail: thumb)
                }
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

    /// After verification minimum + reprocess, jump straight to rename preview (spec path).
    func generatePreviewAfterVerification(settings: SettingsStore) {
        finishVerificationAndReprocess(settings: settings, preferPreview: true)
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

private extension FaceVerificationResolution {
    var countsAsVerified: Bool {
        switch self {
        case .confirmed, .unknown: return true
        case .skipped: return false
        }
    }
}

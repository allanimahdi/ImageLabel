import AppKit
import Foundation
import SwiftUI

/// Orchestrates the one-button Process Folder workflow: split by faces, then
/// reuse Rename-by-Faces and Label & Rename → Auto-Group pipelines.
@MainActor
final class ProcessFolderSession: ObservableObject {
    @Published var step: ProcessFolderStep = .select
    @Published var folderURL: URL?
    @Published var allPhotoURLs: [URL] = []
    @Published var withFaceURLs: [URL] = []
    @Published var withoutFaceURLs: [URL] = []
    @Published var isBusy = false
    @Published var progressCompleted = 0
    @Published var progressTotal = 0
    @Published var statusMessage: String?
    @Published var facesBranchCompleted = false
    @Published var labelBranchCompleted = false

    var withFaceCount: Int { withFaceURLs.count }
    var withoutFaceCount: Int { withoutFaceURLs.count }
    var totalCount: Int { allPhotoURLs.count }

    func reset() {
        step = .select
        folderURL = nil
        allPhotoURLs = []
        withFaceURLs = []
        withoutFaceURLs = []
        isBusy = false
        progressCompleted = 0
        progressTotal = 0
        statusMessage = nil
        facesBranchCompleted = false
        labelBranchCompleted = false
    }

    /// Opens a folder picker. Returns `true` if a folder with images was chosen.
    @discardableResult
    func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
        panel.message = "Choose a folder of photos to process (faces + labels)."
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return loadFolder(url)
    }

    @discardableResult
    func loadFolder(_ url: URL) -> Bool {
        _ = url.startAccessingSecurityScopedResource()
        folderURL = url
        withFaceURLs = []
        withoutFaceURLs = []
        facesBranchCompleted = false
        labelBranchCompleted = false
        statusMessage = nil

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        allPhotoURLs = contents
            .filter { SupportedImageTypes.isSupported(url: $0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        if allPhotoURLs.isEmpty {
            statusMessage = "No supported images in that folder."
            step = .select
            return false
        }

        statusMessage = "Selected \(allPhotoURLs.count) photo\(allPhotoURLs.count == 1 ? "" : "s")."
        return true
    }

    func startScan() async {
        guard !allPhotoURLs.isEmpty else { return }
        step = .scanning
        isBusy = true
        progressCompleted = 0
        progressTotal = allPhotoURLs.count
        statusMessage = "Checking which photos contain faces…"
        withFaceURLs = []
        withoutFaceURLs = []
        defer { isBusy = false }

        var withFaces: [URL] = []
        var withoutFaces: [URL] = []

        for (index, url) in allPhotoURLs.enumerated() {
            do {
                if try FaceDetectionService.imageContainsFaces(at: url) {
                    withFaces.append(url)
                } else {
                    withoutFaces.append(url)
                }
            } catch {
                // Unreadable → treat as no-face so Label & Rename can still try.
                withoutFaces.append(url)
            }
            progressCompleted = index + 1
        }

        withFaceURLs = withFaces
        withoutFaceURLs = withoutFaces
        step = .summary
        statusMessage = "\(withFaces.count) with faces · \(withoutFaces.count) without faces"
    }

    /// Advance past summary into faces (or skip to label if none).
    func continueFromSummary() {
        if withFaceCount > 0, !facesBranchCompleted {
            step = .faces
            statusMessage = "Rename photos that contain faces (verification required)."
        } else {
            advanceToLabelOrDone()
        }
    }

    func markFacesBranchCompleted() {
        facesBranchCompleted = true
        advanceToLabelOrDone()
    }

    func skipFacesBranch() {
        facesBranchCompleted = true
        advanceToLabelOrDone()
    }

    func advanceToLabelOrDone() {
        if withoutFaceCount > 0, !labelBranchCompleted {
            step = .labelRename
            statusMessage = "Label & rename photos without faces, then auto-group."
        } else {
            step = .done
            statusMessage = doneMessage
        }
    }

    func markLabelBranchCompleted() {
        labelBranchCompleted = true
        step = .done
        statusMessage = doneMessage
    }

    private var doneMessage: String {
        var parts: [String] = []
        if withFaceCount > 0 {
            parts.append(facesBranchCompleted
                ? "Faces: finished (\(withFaceCount))"
                : "Faces: skipped (\(withFaceCount))")
        }
        if withoutFaceCount > 0 {
            parts.append(labelBranchCompleted
                ? "No-face: labeled & grouped (\(withoutFaceCount))"
                : "No-face: pending (\(withoutFaceCount))")
        }
        if parts.isEmpty { return "Nothing to process." }
        return parts.joined(separator: " · ")
    }
}

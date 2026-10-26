import SwiftUI

/// Guided multi-step Process Folder: scan → split summary → faces → label & auto-group.
struct ProcessFolderFlowView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var processSession: ProcessFolderSession
    @EnvironmentObject private var faceSession: FaceRenameSession
    @EnvironmentObject private var labelingSession: LabelingSession
    @EnvironmentObject private var identityStore: FaceIdentityStore

    let onClose: () -> Void
    let onStartFaces: () -> Void

    @State private var didSeedLabelItems = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(AppTheme.border).frame(height: 1)
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.atmosphereGradient.opacity(0.85))
            Rectangle().fill(AppTheme.border).frame(height: 1)
            footer
        }
        .background(AppTheme.background)
        .onChange(of: processSession.step) { _, newStep in
            if newStep == .labelRename {
                seedLabelItemsIfNeeded()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Process Folder")
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.text)
                Spacer()
                Button("Home") {
                    processSession.reset()
                    onClose()
                }
            }
            HStack(spacing: 14) {
                ForEach(ProcessFolderStep.allCases.filter { $0 != .select }) { step in
                    HStack(spacing: 6) {
                        Image(systemName: stepIcon(step))
                            .foregroundStyle(step.rawValue <= processSession.step.rawValue
                                             ? AppTheme.accent : AppTheme.textTertiary)
                        Text(step.title)
                            .foregroundStyle(step == processSession.step ? AppTheme.text : AppTheme.textSecondary)
                    }
                    .font(.callout)
                }
            }
        }
        .padding()
        .background(AppTheme.surfaceSecondary.opacity(0.5))
    }

    private func stepIcon(_ step: ProcessFolderStep) -> String {
        if step.rawValue < processSession.step.rawValue { return "checkmark.circle.fill" }
        if step == processSession.step { return "circle.inset.filled" }
        return "circle"
    }

    @ViewBuilder
    private var stepContent: some View {
        switch processSession.step {
        case .select:
            selectStep
        case .scanning:
            scanningStep
        case .summary:
            summaryStep
        case .faces:
            facesStep
        case .labelRename:
            labelRenameStep
        case .done:
            doneStep
        }
    }

    private var selectStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.accent)
            Text("Select a folder of photos")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.text)
            Text("We’ll split photos with faces from those without, then guide you through rename-by-faces and label & auto-group.")
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Choose Folder…") {
                if processSession.chooseFolder() {
                    Task { await processSession.startScan() }
                }
            }
            .buttonStyle(AppPrimaryButtonStyle())
            if let message = processSession.statusMessage {
                Text(message).foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding()
    }

    private var scanningStep: some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(processSession.progressCompleted),
                         total: max(Double(processSession.progressTotal), 1))
                .tint(AppTheme.accent)
                .frame(maxWidth: 320)
            Text("Scanning for faces…")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.text)
            Text("\(processSession.progressCompleted) / \(processSession.progressTotal)")
                .monospacedDigit()
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding()
    }

    private var summaryStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Folder split")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.text)
            if let folder = processSession.folderURL {
                Text(folder.path)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            HStack(spacing: 16) {
                summaryCard(
                    title: "With faces",
                    count: processSession.withFaceCount,
                    systemImage: "person.crop.rectangle.stack.fill",
                    detail: "Rename by Faces (verification required)",
                    chip: AppTheme.surfaceSecondary
                )
                summaryCard(
                    title: "Without faces",
                    count: processSession.withoutFaceCount,
                    systemImage: "tag.fill",
                    detail: "Label & Rename → Auto-Group",
                    chip: AppTheme.surfaceTertiary
                )
            }

            Text("Total: \(processSession.totalCount) photo\(processSession.totalCount == 1 ? "" : "s")")
                .foregroundStyle(AppTheme.textSecondary)

            Text("Next you’ll rename photos with faces (including mandatory face verification). Photos without faces are labeled and auto-grouped afterward.")
                .font(.callout)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: 640, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func summaryCard(
        title: String,
        count: Int,
        systemImage: String,
        detail: String,
        chip: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(AppTheme.text)
            Text("\(count)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.accent)
            Text(detail)
                .font(.callout)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(chip)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        }
    }

    private var facesStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.rectangle.stack.fill")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.accent)
            Text("\(processSession.withFaceCount) photos with faces")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.text)
            Text("Open Rename by Faces to detect, verify, identify, and rename. Face verification is required — it won’t be skipped.")
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button("Open Rename by Faces…") {
                faceSession.loadPhotos(processSession.withFaceURLs, folderURL: processSession.folderURL)
                onStartFaces()
            }
            .buttonStyle(AppPrimaryButtonStyle())
            Button("Skip faces for now") {
                processSession.skipFacesBranch()
            }
            .foregroundStyle(AppTheme.textSecondary)
        }
        .padding()
    }

    private var labelRenameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Photos without faces")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.text)
            Text("\(processSession.withoutFaceCount) image\(processSession.withoutFaceCount == 1 ? "" : "s") · Labeling: \(settings.labelingBackend.rawValue)")
                .foregroundStyle(AppTheme.textSecondary)

            if !settings.canLabel {
                Text("Add Google credentials in Settings, or switch Labeling to Local (Apple Vision).")
                    .foregroundStyle(AppTheme.warning)
            }

            GuidedActionRow(
                number: 1,
                title: "Label images",
                subtitle: labelingSession.labeledCount > 0
                    ? "Labeled \(labelingSession.labeledCount) of \(labelingSession.items.count)"
                    : "Run Vision labels on the no-face set",
                buttonTitle: labelingSession.isLabeling ? "Labeling…" : "Label Images",
                isEnabled: settings.canLabel && !labelingSession.items.isEmpty && !labelingSession.isBusy,
                isDone: labelingSession.labeledCount > 0
            ) {
                Task { await labelingSession.labelAll(using: settings) }
            }

            GuidedActionRow(
                number: 2,
                title: "Rename to top labels",
                subtitle: "Review proposed filenames, then apply",
                buttonTitle: "Review Renames…",
                isEnabled: labelingSession.labeledCount > 0 && !labelingSession.isBusy,
                isDone: labelingSession.items.contains { $0.status == .renamed }
            ) {
                labelingSession.prepareRenamePreview()
            }

            GuidedActionRow(
                number: 3,
                title: "Auto-Group into folders",
                subtitle: "Move into coarse main categories (Animals, Nature, …)",
                buttonTitle: "Review Auto-Group…",
                isEnabled: labelingSession.labeledCount > 0 && !labelingSession.isBusy,
                isDone: labelingSession.items.contains { $0.status == .grouped }
            ) {
                labelingSession.prepareAutoGroupPreview()
            }

            if let message = labelingSession.statusMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(28)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.success)
            Text("Folder processing complete")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.text)
            if let message = processSession.statusMessage {
                Text(message)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button("Back to Home") {
                processSession.reset()
                onClose()
            }
            .buttonStyle(AppPrimaryButtonStyle())
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            if processSession.isBusy {
                ProgressView(value: Double(processSession.progressCompleted),
                             total: max(Double(processSession.progressTotal), 1))
                    .tint(AppTheme.accent)
                    .frame(maxWidth: 180)
            }
            if labelingSession.isBusy {
                ProgressView(value: Double(labelingSession.progressCompleted),
                             total: max(Double(labelingSession.progressTotal), 1))
                    .tint(AppTheme.accent)
                    .frame(maxWidth: 180)
                Text("\(labelingSession.progressCompleted)/\(labelingSession.progressTotal)")
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textSecondary)
            }
            if let message = processSession.statusMessage, processSession.step != .done {
                Text(message)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            footerButtons
        }
        .padding()
        .background(AppTheme.surface.opacity(0.9))
    }

    @ViewBuilder
    private var footerButtons: some View {
        switch processSession.step {
        case .select, .scanning:
            EmptyView()
        case .summary:
            Button("Continue") {
                processSession.continueFromSummary()
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .disabled(processSession.totalCount == 0)
        case .faces:
            if processSession.facesBranchCompleted {
                Button("Continue to Label & Group") {
                    processSession.advanceToLabelOrDone()
                }
                .buttonStyle(AppPrimaryButtonStyle())
            } else {
                Button("I’ve finished faces") {
                    processSession.markFacesBranchCompleted()
                }
                .buttonStyle(AppPrimaryButtonStyle())
            }
        case .labelRename:
            Button("Mark complete") {
                processSession.markLabelBranchCompleted()
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .disabled(labelingSession.isBusy)
        case .done:
            EmptyView()
        }
    }

    private func seedLabelItemsIfNeeded() {
        guard !didSeedLabelItems || labelingSession.items.isEmpty else { return }
        labelingSession.loadImages(processSession.withoutFaceURLs, folderURL: processSession.folderURL)
        didSeedLabelItems = true
    }
}

private struct GuidedActionRow: View {
    let number: Int
    let title: String
    let subtitle: String
    let buttonTitle: String
    let isEnabled: Bool
    let isDone: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(isDone ? AppTheme.icyAqua : AppTheme.powderBlush.opacity(0.35))
                    .frame(width: 28, height: 28)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.success)
                } else {
                    Text("\(number)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.text)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(AppTheme.text)
                Text(subtitle).font(.callout).foregroundStyle(AppTheme.textSecondary)
            }
            Spacer(minLength: 8)
            Button(buttonTitle, action: action)
                .buttonStyle(AppPrimaryButtonStyle())
                .disabled(!isEnabled)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        }
    }
}

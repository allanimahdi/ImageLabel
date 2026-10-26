import SwiftUI

struct FaceRenameFlowView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var faceSession: FaceRenameSession
    @EnvironmentObject private var identityStore: FaceIdentityStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(AppTheme.border).frame(height: 1)
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.background.opacity(0.9))
            Rectangle().fill(AppTheme.border).frame(height: 1)
            footer
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(AppTheme.eggshell)
        .tint(AppTheme.accent)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Rename Photos by Faces")
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.text)
                Spacer()
                Button("Close") {
                    faceSession.reset()
                    dismiss()
                }
            }
            HStack(spacing: 16) {
                ForEach(FaceRenameStep.allCases) { step in
                    HStack(spacing: 6) {
                        Image(systemName: step.rawValue < faceSession.step.rawValue
                              ? "checkmark.circle.fill"
                              : (step == faceSession.step ? "circle.inset.filled" : "circle"))
                            .foregroundStyle(step.rawValue <= faceSession.step.rawValue ? AppTheme.accent : AppTheme.textTertiary)
                        Text(step.title)
                            .foregroundStyle(step == faceSession.step ? AppTheme.text : AppTheme.textSecondary)
                    }
                    .font(.callout)
                }
            }
        }
        .padding()
        .background(AppTheme.surfaceSecondary.opacity(0.45))
    }

    @ViewBuilder
    private var stepContent: some View {
        switch faceSession.step {
        case .select:
            FaceSelectStepView()
        case .detect:
            FaceDetectStepView()
        case .verify:
            FaceVerifyStepView()
        case .identify:
            FaceIdentifyStepView()
        case .preview:
            FacePreviewStepView()
        }
    }

    private var footer: some View {
        HStack {
            if faceSession.isBusy {
                ProgressView(value: Double(faceSession.progressCompleted), total: max(Double(faceSession.progressTotal), 1))
                    .tint(AppTheme.accent)
                    .frame(maxWidth: 200)
                Text("\(faceSession.progressCompleted)/\(faceSession.progressTotal)")
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textSecondary)
            }
            if let message = faceSession.statusMessage {
                Text(message)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
                    .help(message)
            }
            Spacer()
            if faceSession.lastUndo != nil, faceSession.step == .preview {
                Button("Undo Rename") {
                    faceSession.lastUndo?()
                }
            }
            stepButtons
        }
        .padding()
        .background(AppTheme.surface.opacity(0.95))
    }

    @ViewBuilder
    private var stepButtons: some View {
        switch faceSession.step {
        case .select:
            Button("Detect & Group Faces") {
                Task { await faceSession.startDetection(settings: settings) }
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .disabled(faceSession.photoURLs.isEmpty || faceSession.isBusy)
        case .detect:
            EmptyView()
        case .verify:
            if faceSession.verificationMinimumMet {
                Button("Skip Ambiguous") {
                    faceSession.continueAfterMinimum(settings: settings)
                }
                Button("Reprocess & Preview") {
                    faceSession.generatePreviewAfterVerification(settings: settings)
                }
                .buttonStyle(AppPrimaryButtonStyle())
            } else {
                Text("Confirm \(max(0, faceSession.requiredVerifications - faceSession.verifiedCount)) more")
                    .foregroundStyle(AppTheme.textSecondary)
                    .font(.callout)
            }
        case .identify:
            if faceSession.mergeSourceID != nil {
                Button("Cancel Merge") { faceSession.cancelMerge() }
            }
            Button("Back to Verification") {
                faceSession.step = .verify
            }
            Button("Generate Photo Names") {
                faceSession.generatePhotoNames(settings: settings)
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .disabled(faceSession.isBusy || faceSession.groups.isEmpty)
        case .preview:
            Button("Back to Identify") {
                faceSession.step = .identify
            }
            Button("Rename All Photos") {
                faceSession.applyRenames()
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .disabled(faceSession.isBusy || !faceSession.previewRows.contains(where: \.include))
        }
    }
}

import SwiftUI

struct FaceRenameFlowView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var faceSession: FaceRenameSession
    @EnvironmentObject private var identityStore: FaceIdentityStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Rename Photos by Faces")
                    .font(.title2.bold())
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
                            .foregroundStyle(step.rawValue <= faceSession.step.rawValue ? Color.accentColor : Color.secondary)
                        Text(step.title)
                            .foregroundStyle(step == faceSession.step ? Color.primary : Color.secondary)
                    }
                    .font(.callout)
                }
            }
        }
        .padding()
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
                    .frame(maxWidth: 200)
                Text("\(faceSession.progressCompleted)/\(faceSession.progressTotal)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let message = faceSession.statusMessage {
                Text(message)
                    .foregroundStyle(.secondary)
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
    }

    @ViewBuilder
    private var stepButtons: some View {
        switch faceSession.step {
        case .select:
            Button("Detect & Group Faces") {
                Task { await faceSession.startDetection(settings: settings) }
            }
            .buttonStyle(.borderedProminent)
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
                .buttonStyle(.borderedProminent)
            } else {
                Text("Confirm \(max(0, faceSession.requiredVerifications - faceSession.verifiedCount)) more")
                    .foregroundStyle(.secondary)
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
            .buttonStyle(.borderedProminent)
            .disabled(faceSession.isBusy || faceSession.groups.isEmpty)
        case .preview:
            Button("Back to Identify") {
                faceSession.step = .identify
            }
            Button("Rename All Photos") {
                faceSession.applyRenames()
            }
            .buttonStyle(.borderedProminent)
            .disabled(faceSession.isBusy || !faceSession.previewRows.contains(where: \.include))
        }
    }
}

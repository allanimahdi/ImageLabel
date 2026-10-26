import SwiftUI

struct FaceVerifyStepView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var faceSession: FaceRenameSession
    @EnvironmentObject private var identityStore: FaceIdentityStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let face = faceSession.currentVerificationFace {
                faceCard(face)
            } else if faceSession.verificationMinimumMet {
                completedPlaceholder
            } else {
                ContentUnavailableView(
                    "Nothing to verify",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("No sample faces were selected.")
                )
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Face Verification — \(faceSession.verifiedCount) / \(faceSession.requiredVerifications) confirmed")
                .font(.title3.weight(.semibold))
            Spacer()
            if faceSession.verificationMinimumMet {
                Text("Minimum met")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.18))
                    .clipShape(Capsule())
            }
        }
        .padding()
    }

    private var completedPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.success)
            Text("Sample verification complete")
                .font(.headline)
            Text("Reprocess remaining faces, then review people or open the rename preview.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private func faceCard(_ face: DetectedFace) -> some View {
        VStack(spacing: 20) {
            Image(nsImage: face.thumbnail)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 280, maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 2, y: 1)

            Text(face.imageURL.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let suggested = faceSession.currentVerificationItem?.suggestedName,
               !suggested.isEmpty {
                HStack(spacing: 8) {
                    Text("Suggested: \(suggested)")
                        .font(.callout)
                    Button("Confirm \(suggested)") {
                        faceSession.confirmSuggestedVerification(settings: settings)
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TextField("Person name", text: $faceSession.verificationDraftName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .onSubmit { faceSession.confirmCurrentVerification(settings: settings) }

                Button("Confirm") {
                    faceSession.confirmCurrentVerification(settings: settings)
                }
                .buttonStyle(AppPrimaryButtonStyle())
                .disabled(
                    faceSession.verificationDraftName
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )
            }

            if !libraryNames.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("People Library")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    FlowNameChips(names: libraryNames) { name in
                        faceSession.verificationDraftName = name
                    }
                }
                .frame(maxWidth: 480)
            }

            HStack(spacing: 12) {
                Button("Unknown") {
                    faceSession.markCurrentUnknown(settings: settings)
                }
                Button("Skip") {
                    faceSession.skipCurrentVerification(settings: settings)
                }
            }
            .font(.callout)

            Text("Confirm or correct a name to count toward the sample. Skip does not.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var libraryNames: [String] {
        var names = identityStore.identities.map(\.name)
        // Also surface names already confirmed this session via draft suggestions on other items
        for item in faceSession.verificationQueue {
            if case .confirmed(let name) = item.resolution {
                names.append(name)
            }
        }
        var seen = Set<String>()
        return names.filter {
            let key = $0.lowercased()
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

/// Simple wrapping chip row without extra dependencies.
private struct FlowNameChips: View {
    let names: [String]
    let onSelect: (String) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 88), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(names, id: \.self) { name in
                Button(name) { onSelect(name) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

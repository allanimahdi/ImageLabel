import SwiftUI

/// First-viewport home: brand + Process Folder primary + secondary advanced actions.
struct HomeLandingView: View {
    let labelingBackendLabel: String
    let canLabel: Bool
    let onProcessFolder: () -> Void
    let onLabelAndRename: () -> Void
    let onAutoGroup: () -> Void
    let onRenameByFaces: () -> Void
    let onSettings: () -> Void

    var body: some View {
        ZStack {
            AppTheme.atmosphereGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    brandBlock
                    primaryAction
                    advancedSection
                }
                .frame(maxWidth: 720)
                .padding(.horizontal, 36)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var brandBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ImageLabel")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.text)
            Text("Process a folder in one pass — faces, labels, and groups.")
                .font(.title3)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(canLabel
                ? "Labeling: \(labelingBackendLabel)"
                : "Add Google credentials in Settings, or switch Labeling to Local.")
                .font(.subheadline)
                .foregroundStyle(canLabel ? AppTheme.textSecondary : AppTheme.warning)
        }
    }

    private var primaryAction: some View {
        Button(action: onProcessFolder) {
            HStack(alignment: .center, spacing: 18) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(AppTheme.onAccent)
                    .frame(width: 64, height: 64)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppTheme.accent)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Process Folder")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(AppTheme.text)
                    Text("Select a folder → split by faces → rename people & label the rest into category folders.")
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AppTheme.borderStrong, lineWidth: 2)
            }
            .shadow(color: AppTheme.blueSlate.opacity(0.12), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .help("One-button workflow: faces + label & auto-group")
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Advanced")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                HomeSecondaryButton(
                    title: "Label & Rename",
                    subtitle: "Vision labels → rename files",
                    systemImage: "tag.fill",
                    action: onLabelAndRename
                )
                HomeSecondaryButton(
                    title: "Auto-Group into Folders",
                    subtitle: "Sort labeled photos into categories",
                    systemImage: "folder.badge.gearshape",
                    action: onAutoGroup
                )
                HomeSecondaryButton(
                    title: "Rename by Faces",
                    subtitle: "On-device faces → name → rename",
                    systemImage: "person.crop.rectangle.stack.fill",
                    action: onRenameByFaces
                )
                HomeSecondaryButton(
                    title: "Settings",
                    subtitle: "Local or Google labeling, faces",
                    systemImage: "gearshape.fill",
                    action: onSettings
                )
            }
        }
    }
}

private struct HomeSecondaryButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.text)
                    .frame(width: 36, height: 36)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.surfaceSecondary)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.text)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hovering ? AppTheme.surfaceTertiary : AppTheme.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            }
            .shadow(color: AppTheme.blueSlate.opacity(hovering ? 0.1 : 0.04), radius: hovering ? 8 : 3, y: 2)
            .scaleEffect(hovering ? 1.01 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(subtitle)
    }
}

import SwiftUI

/// First-viewport home: brand + one short line + four large primary actions.
struct HomeLandingView: View {
    let labelingBackendLabel: String
    let canLabel: Bool
    let onLabelAndRename: () -> Void
    let onAutoGroup: () -> Void
    let onRenameByFaces: () -> Void
    let onSettings: () -> Void

    var body: some View {
        ZStack {
            atmosphere
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    brandBlock
                    actionGrid
                }
                .frame(maxWidth: 720)
                .padding(.horizontal, 36)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var atmosphere: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color.accentColor.opacity(0.08),
                Color(nsColor: .underPageBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var brandBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ImageLabel")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text("Organize a folder of photos — label, rename, group, or rename by the people in them.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(canLabel
                ? "Labeling: \(labelingBackendLabel)"
                : "Add Google credentials in Settings, or switch Labeling to Local.")
                .font(.subheadline)
                .foregroundStyle(canLabel ? Color.secondary : Color.orange)
        }
    }

    private var actionGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ],
            spacing: 16
        ) {
            HomeActionButton(
                title: "Label & Rename",
                subtitle: "Vision labels → rename files to the top label",
                systemImage: "tag.fill",
                action: onLabelAndRename
            )
            HomeActionButton(
                title: "Auto-Group into Folders",
                subtitle: "Sort labeled photos into coarse category folders",
                systemImage: "folder.badge.gearshape",
                action: onAutoGroup
            )
            HomeActionButton(
                title: "Rename by Faces",
                subtitle: "On-device faces → name people → rename photos",
                systemImage: "person.crop.rectangle.stack.fill",
                action: onRenameByFaces
            )
            HomeActionButton(
                title: "Settings",
                subtitle: "Local or Google labeling, faces, credentials",
                systemImage: "gearshape.fill",
                action: onSettings
            )
        }
    }
}

private struct HomeActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 48, height: 48)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accentColor.opacity(0.08))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(hovering ? 0.14 : 0.06), radius: hovering ? 12 : 5, y: hovering ? 5 : 2)
            .scaleEffect(hovering ? 1.015 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(subtitle)
    }
}

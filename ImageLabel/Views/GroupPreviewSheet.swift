import SwiftUI

struct GroupPreviewSheet: View {
    @EnvironmentObject private var session: LabelingSession
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        session.groupPreviewIsAuto ? "Auto-Group into Folders" : "Group by Topic"
    }

    private var subtitle: String {
        if session.groupPreviewIsAuto {
            return "Each image moves into one coarse main category (Animals, People, Nature, Food, …) based on its Vision labels — not fine-grained subcategories. Review, then apply."
        }
        return "Move images that include “\(session.selectedTopic ?? "topic")” into a folder with that name. You chose the topic — this is not limited to each file’s top label."
    }

    private var categorySummary: String {
        let counts = Dictionary(grouping: session.groupPreview, by: \.topic).mapValues(\.count)
        return counts.keys.sorted().map { "\($0) (\(counts[$0] ?? 0))" }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(AppTheme.text)
                .padding()

            Text(subtitle)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal)
                .padding(.bottom, 8)

            if session.groupPreviewIsAuto, !session.groupPreview.isEmpty {
                Text(categorySummary)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            if session.groupPreview.isEmpty {
                ContentUnavailableView(
                    session.groupPreviewIsAuto ? "Nothing to auto-group" : "No matching images",
                    systemImage: "folder",
                    description: Text(
                        session.groupPreviewIsAuto
                            ? "Label images first. Files already in the right category folder are skipped."
                            : "No labeled images include this topic."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if session.groupPreviewIsAuto {
                autoTable
            } else {
                topicTable
            }

            HStack {
                Text("\(session.groupPreview.count) file\(session.groupPreview.count == 1 ? "" : "s")")
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Button("Cancel") {
                    session.showGroupPreview = false
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(session.groupPreviewIsAuto ? "Create Folders & Move" : "Move into Folder") {
                    session.applyGroupPreview()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(AppPrimaryButtonStyle())
                .disabled(session.groupPreview.isEmpty)
            }
            .padding()
            .background(AppTheme.surfaceSecondary.opacity(0.4))
        }
        .frame(minWidth: 720, minHeight: 440)
        .background(AppTheme.eggshell)
        .tint(AppTheme.accent)
    }

    private var autoTable: some View {
        Table(session.groupPreview) {
            TableColumn("File") { plan in
                Text(plan.source.lastPathComponent)
                    .lineLimit(1)
            }
            TableColumn("Category") { plan in
                Text(plan.topic)
                    .lineLimit(1)
            }
            TableColumn("Via label") { plan in
                Text(plan.matchedLabel ?? "—")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            TableColumn("Path") { plan in
                Text(relativeDestination(plan))
                    .lineLimit(1)
            }
        }
    }

    private var topicTable: some View {
        Table(session.groupPreview) {
            TableColumn("File") { plan in
                Text(plan.source.lastPathComponent)
                    .lineLimit(1)
            }
            TableColumn("Destination") { plan in
                Text(relativeDestination(plan))
                    .lineLimit(1)
            }
        }
    }

    private func relativeDestination(_ plan: GroupPlan) -> String {
        guard let root = session.folderURL else {
            return plan.destination.path
        }
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        if plan.destination.path.hasPrefix(rootPath) {
            return String(plan.destination.path.dropFirst(rootPath.count))
        }
        return plan.destination.lastPathComponent
    }
}

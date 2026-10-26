import SwiftUI

struct GroupPreviewSheet: View {
    @EnvironmentObject private var session: LabelingSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Group by Topic")
                .font(.title2.bold())
                .padding()

            Text("Move images that include “\(session.selectedTopic ?? "topic")” into a folder with that name. You chose the topic — this is not limited to each file’s top label.")
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)

            if session.groupPreview.isEmpty {
                ContentUnavailableView(
                    "No matching images",
                    systemImage: "folder",
                    description: Text("No labeled images include this topic.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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

            HStack {
                Text("\(session.groupPreview.count) file\(session.groupPreview.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    session.showGroupPreview = false
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Move into Folder") {
                    session.applyGroupPreview()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(session.groupPreview.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 640, minHeight: 420)
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

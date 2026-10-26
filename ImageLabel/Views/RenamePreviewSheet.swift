import SwiftUI

struct RenamePreviewSheet: View {
    @EnvironmentObject private var session: LabelingSession
    @Environment(\.dismiss) private var dismiss

    private var changeCount: Int {
        session.renamePreview.filter(\.changesName).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Rename to Top Labels")
                .font(.title2.bold())
                .padding()

            Text("Each file becomes its best-score Vision label only (no score in the filename). Collisions get _2, _3, … suffixes. Grouping by topic is a separate step.")
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)

            if session.renamePreview.isEmpty {
                ContentUnavailableView(
                    "No labels to rename from",
                    systemImage: "tag.slash",
                    description: Text("Label images with Vision first, then rename.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(session.renamePreview) {
                    TableColumn("Current") { plan in
                        Text(plan.source.lastPathComponent)
                            .lineLimit(1)
                    }
                    TableColumn("New name") { plan in
                        Text(plan.destination.lastPathComponent)
                            .lineLimit(1)
                            .foregroundStyle(plan.changesName ? .primary : .secondary)
                    }
                    TableColumn("Label") { plan in
                        Text(plan.label)
                            .lineLimit(1)
                    }
                }
            }

            HStack {
                Text(changeCount == 0
                    ? "All names already match top labels."
                    : "\(changeCount) of \(session.renamePreview.count) will be renamed on disk")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Not Now") {
                    session.showRenamePreview = false
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Apply Renames") {
                    session.applyRenamePreview()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(changeCount == 0)
            }
            .padding()
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}

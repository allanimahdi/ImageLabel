import SwiftUI

struct RenamePreviewSheet: View {
    @EnvironmentObject private var session: LabelingSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Rename Preview")
                .font(.title2.bold())
                .padding()

            Text("Each file is renamed to its best-score Vision label only (no score in the name). Collisions get numeric suffixes.")
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)

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

            HStack {
                Text("\(session.renamePreview.filter(\.changesName).count) of \(session.renamePreview.count) will change")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    session.showRenamePreview = false
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Apply Renames") {
                    session.applyRenamePreview()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(session.renamePreview.filter(\.changesName).isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}

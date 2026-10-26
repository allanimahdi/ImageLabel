import SwiftUI

struct FacePreviewStepView: View {
    @EnvironmentObject private var faceSession: FaceRenameSession
    @State private var onlyUncertain = false

    private var rows: [FaceRenameRow] {
        if onlyUncertain {
            return faceSession.previewRows.filter(\.hasUncertain)
        }
        return faceSession.previewRows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Review names before changing files. Unknown-only photos keep their original filenames by default.")
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Uncertain only", isOn: $onlyUncertain)
                    .toggleStyle(.checkbox)
            }
            .padding()

            Table(rows) {
                TableColumn("Include") { row in
                    Toggle("", isOn: Binding(
                        get: { row.include },
                        set: { faceSession.setInclude($0, for: row.id) }
                    ))
                    .labelsHidden()
                    .disabled(row.status.contains("keep original") && row.peopleNames.isEmpty)
                }
                .width(60)

                TableColumn("Original") { row in
                    Text(row.originalName)
                        .lineLimit(1)
                }

                TableColumn("New name") { row in
                    TextField("New name", text: Binding(
                        get: { row.proposedName },
                        set: { faceSession.updateProposedName($0, for: row.id) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                TableColumn("People") { row in
                    Text(row.peopleNames.isEmpty ? "—" : row.peopleNames.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                TableColumn("Status") { row in
                    Text(row.status)
                        .foregroundStyle(row.status.lowercased().contains("fail") || row.status.lowercased().contains("conflict")
                                         ? Color.red : Color.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

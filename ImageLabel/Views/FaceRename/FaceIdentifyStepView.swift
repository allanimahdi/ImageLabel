import SwiftUI

struct FaceIdentifyStepView: View {
    @EnvironmentObject private var faceSession: FaceRenameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("After face verification, high-confidence matches are filled in. Confirm flagged people, merge / split if needed, then generate names.")
                .foregroundStyle(.secondary)
                .padding()

            if faceSession.groups.isEmpty {
                ContentUnavailableView(
                    "No people found",
                    systemImage: "person.slash",
                    description: Text("Go back and select photos that contain visible faces.")
                )
            } else {
                List {
                    ForEach(faceSession.groups) { group in
                        personRow(group)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    @ViewBuilder
    private func personRow(_ group: FacePersonGroup) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let thumb = group.displayThumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 64, height: 64)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(faceSession.photoCount(for: group)) photo\(faceSession.photoCount(for: group) == 1 ? "" : "s") · \(group.faceIDs.count) face\(group.faceIDs.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if group.needsReview {
                        Text("Review match")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }

                TextField("Name", text: Binding(
                    get: { group.name },
                    set: { faceSession.setName($0, for: group.id) }
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(group.skipState == .skipped || group.skipState == .unknown)

                HStack(spacing: 8) {
                    Button("Unknown") { faceSession.markUnknown(group.id) }
                    Button("Skip") { faceSession.markSkipped(group.id) }
                    if faceSession.mergeSourceID == group.id {
                        Text("Merging…")
                            .foregroundStyle(.secondary)
                    } else if let source = faceSession.mergeSourceID, source != group.id {
                        Button("Merge into this") { faceSession.completeMerge(into: group.id) }
                    } else {
                        Button("Merge…") { faceSession.beginMerge(from: group.id) }
                    }
                    if group.faceIDs.count > 1 {
                        Menu("Split face…") {
                            ForEach(faceSession.faces(in: group)) { face in
                                Button("From \(face.imageURL.lastPathComponent)") {
                                    faceSession.splitFace(face.id, from: group.id)
                                }
                            }
                        }
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .opacity(group.skipState == .skipped ? 0.45 : 1)
    }
}

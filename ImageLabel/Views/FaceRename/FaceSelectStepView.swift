import SwiftUI

struct FaceSelectStepView: View {
    @EnvironmentObject private var faceSession: FaceRenameSession

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Select photos to analyze")
                .font(.title3)
            Text("Faces are detected and matched entirely on this Mac — photos are not uploaded.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 12) {
                Button("Select Folder…") { faceSession.chooseFolder() }
                Button("Select Photos…") { faceSession.chooseFiles() }
            }
            if faceSession.photoCount > 0 {
                Text("\(faceSession.photoCount) photo\(faceSession.photoCount == 1 ? "" : "s") selected")
                    .font(.headline)
                if let folder = faceSession.folderURL {
                    Text(folder.path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

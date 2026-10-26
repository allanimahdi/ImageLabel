import SwiftUI

struct FaceSelectStepView: View {
    @EnvironmentObject private var faceSession: FaceRenameSession

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.accent)
            Text("Select photos to analyze")
                .font(.title3)
                .foregroundStyle(AppTheme.text)
            Text("Faces are detected and matched entirely on this Mac — photos are not uploaded.")
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 12) {
                Button("Select Folder…") { faceSession.chooseFolder() }
                    .buttonStyle(AppPrimaryButtonStyle())
                Button("Select Photos…") { faceSession.chooseFiles() }
            }
            if faceSession.photoCount > 0 {
                Text("\(faceSession.photoCount) photo\(faceSession.photoCount == 1 ? "" : "s") selected")
                    .font(.headline)
                    .foregroundStyle(AppTheme.text)
                if let folder = faceSession.folderURL {
                    Text(folder.path)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

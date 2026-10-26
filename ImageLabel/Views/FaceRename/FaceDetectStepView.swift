import SwiftUI

struct FaceDetectStepView: View {
    @EnvironmentObject private var faceSession: FaceRenameSession

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(faceSession.progressCompleted), total: max(Double(faceSession.progressTotal), 1))
                .frame(maxWidth: 360)
            Text("Detecting faces & building embeddings…")
                .font(.headline)
            Text("\(faceSession.progressCompleted) of \(faceSession.progressTotal) photos")
                .foregroundStyle(.secondary)
            Text("On-device Vision face rectangles + image feature prints. Clustering runs when detection finishes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

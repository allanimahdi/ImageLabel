import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var session: LabelingSession
    @EnvironmentObject private var faceSession: FaceRenameSession
    @EnvironmentObject private var identityStore: FaceIdentityStore
    @State private var showSettings = false
    @State private var showFaceRename = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if session.items.isEmpty {
                emptyState
            } else {
                imageTable
            }
            Divider()
            footer
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(identityStore)
                .frame(width: 540, height: 520)
        }
        .sheet(isPresented: $session.showRenamePreview) {
            RenamePreviewSheet()
                .environmentObject(session)
        }
        .sheet(isPresented: $session.showGroupPreview) {
            GroupPreviewSheet()
                .environmentObject(session)
        }
        .sheet(isPresented: $showFaceRename) {
            FaceRenameFlowView()
                .environmentObject(settings)
                .environmentObject(faceSession)
                .environmentObject(identityStore)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                session.chooseFolder()
            } label: {
                Label("Select Folder", systemImage: "folder")
            }
            .disabled(session.isBusy)

            Button {
                Task { await session.labelAll(using: settings) }
            } label: {
                Label("Label Images", systemImage: "tag")
            }
            .disabled(session.items.isEmpty || session.isBusy || !settings.canLabel)
            .help(labelButtonHelp)

            Button {
                session.prepareRenamePreview()
            } label: {
                Label("Rename Files…", systemImage: "pencil")
            }
            .disabled(session.labeledCount == 0 || session.isBusy)
            .help("Preview renaming each file to its best-score Vision label (no score in the name), then Apply")

            Button {
                faceSession.reset()
                showFaceRename = true
            } label: {
                Label("Rename by Faces…", systemImage: "person.crop.rectangle.stack")
            }
            .disabled(session.isBusy)
            .help("Detect faces on-device, name people once, preview, then rename photos")

            Button {
                session.prepareAutoGroupPreview()
            } label: {
                Label("Auto-Group into Folders", systemImage: "folder.badge.gearshape")
            }
            .disabled(session.labeledCount == 0 || session.isBusy)
            .help("Preview moving each image into a coarse main category (Animals, People, Nature, …)")

            Menu {
                if session.availableTopics.isEmpty {
                    Text("Label images first")
                } else {
                    ForEach(session.availableTopics, id: \.self) { topic in
                        Button(topic) {
                            session.prepareGroupPreview(topic: topic)
                        }
                    }
                }
            } label: {
                Label("Group by Topic", systemImage: "square.stack.3d.up")
            }
            .disabled(session.labeledCount == 0 || session.isBusy)
            .help("Optional: move images into a folder for a Vision label you pick")

            if session.lastUndo != nil {
                Button {
                    session.undoLast()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(session.isBusy)
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Select a folder of images")
                .font(.title2)
            Text("1) Label → 2) Rename to top label → 3) Auto-Group into Folders (or pick a topic).")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Text(settings.labelingBackend == .localApple
                ? "Settings default to Local (Apple Vision) — free & offline."
                : "Google Cloud Vision selected — credentials required in Settings.")
                .font(.callout)
                .foregroundStyle(settings.canLabel ? Color.secondary : Color.orange)
            if settings.labelingBackend == .googleCloud && !settings.canLabel {
                Text("Add an API key or service-account JSON, or switch Labeling to Local.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            Button("Select Folder") {
                session.chooseFolder()
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var imageTable: some View {
        Table(session.items) {
            TableColumn("File") { item in
                Text(item.fileName)
                    .lineLimit(1)
            }
            .width(min: 140, ideal: 200)

            TableColumn("Top Label") { item in
                Text(item.topLabel?.description ?? "—")
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 140)

            TableColumn("Score") { item in
                if let score = item.topLabel?.score {
                    Text(score, format: .percent.precision(.fractionLength(0)))
                        .foregroundStyle(.secondary)
                } else {
                    Text("—")
                }
            }
            .width(60)

            TableColumn("New Name") { item in
                Text(item.proposedName ?? "—")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 180)

            TableColumn("Status") { item in
                statusCell(item)
            }
            .width(min: 100, ideal: 160)
        }
    }

    @ViewBuilder
    private func statusCell(_ item: ImageItem) -> some View {
        switch item.status {
        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
                .help(message)
                .lineLimit(2)
        default:
            Text(item.status.displayText)
                .foregroundStyle(statusColor(item.status))
        }
    }

    private func statusColor(_ status: ImageItemStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .labeling: return .blue
        case .labeled: return .primary
        case .failed: return .red
        case .renamed, .grouped: return .green
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if session.isLabeling {
                ProgressView(value: Double(session.progressCompleted), total: max(Double(session.progressTotal), 1))
                    .frame(maxWidth: 220)
                Text("\(session.progressCompleted)/\(session.progressTotal)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if let message = session.statusMessage {
                Text(message)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(message)
            }

            Spacer()

            if session.labeledCount > 0, !session.isBusy, session.pendingRenameCount > 0 {
                Button("Rename Files…") {
                    session.prepareRenamePreview()
                }
                .buttonStyle(.borderedProminent)
                .help("Rename on disk to each file’s best Vision label")
            }

            if let folder = session.folderURL {
                Text(folder.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var labelButtonHelp: String {
        switch settings.labelingBackend {
        case .localApple:
            return "Classify on-device with Apple Vision (no network or API key)"
        case .googleCloud:
            return settings.canLabel
                ? "Run Google Cloud Vision label detection"
                : "Add Google credentials in Settings, or switch to Local (Apple Vision)"
        }
    }
}

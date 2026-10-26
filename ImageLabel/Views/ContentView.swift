import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var session: LabelingSession
    @EnvironmentObject private var faceSession: FaceRenameSession
    @EnvironmentObject private var identityStore: FaceIdentityStore
    @State private var showSettings = false
    @State private var showFaceRename = false
    /// When false, show the home landing; true after opening a folder for Label & Rename.
    @State private var showLabelWorkspace = false

    var body: some View {
        Group {
            if showLabelWorkspace, session.folderURL != nil {
                labelWorkspace
            } else {
                HomeLandingView(
                    labelingBackendLabel: settings.labelingBackend.rawValue,
                    canLabel: settings.canLabel,
                    onLabelAndRename: startLabelAndRename,
                    onAutoGroup: startAutoGroupFromHome,
                    onRenameByFaces: {
                        faceSession.reset()
                        showFaceRename = true
                    },
                    onSettings: { showSettings = true }
                )
            }
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
        .onChange(of: session.folderURL) { _, url in
            if url == nil {
                showLabelWorkspace = false
            }
        }
    }

    // MARK: - Home actions

    private func startLabelAndRename() {
        session.chooseFolder()
        if session.folderURL != nil {
            showLabelWorkspace = true
        }
    }

    private func startAutoGroupFromHome() {
        if session.labeledCount > 0 {
            showLabelWorkspace = session.folderURL != nil
            session.prepareAutoGroupPreview()
            return
        }
        // Need labels first — open a folder, then user runs Label Images.
        session.chooseFolder()
        if session.folderURL != nil {
            showLabelWorkspace = true
            session.statusMessage = "Label Images first, then use Auto-Group into Folders."
        }
    }

    // MARK: - Label workspace (compact chrome after landing)

    private var labelWorkspace: some View {
        VStack(spacing: 0) {
            workspaceToolbar
            Divider()
            if session.items.isEmpty {
                workspaceEmpty
            } else {
                imageTable
            }
            Divider()
            footer
        }
    }

    private var workspaceToolbar: some View {
        HStack(spacing: 10) {
            Button {
                showLabelWorkspace = false
            } label: {
                Label("Home", systemImage: "chevron.left")
            }
            .help("Back to home")

            Divider().frame(height: 18)

            Button {
                session.chooseFolder()
            } label: {
                Label("Folder", systemImage: "folder")
            }
            .disabled(session.isBusy)

            Button {
                Task { await session.labelAll(using: settings) }
            } label: {
                Label("Label", systemImage: "tag")
            }
            .disabled(session.items.isEmpty || session.isBusy || !settings.canLabel)
            .help(labelButtonHelp)

            Button {
                session.prepareRenamePreview()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .disabled(session.labeledCount == 0 || session.isBusy)

            Button {
                session.prepareAutoGroupPreview()
            } label: {
                Label("Auto-Group", systemImage: "folder.badge.gearshape")
            }
            .disabled(session.labeledCount == 0 || session.isBusy)

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
                Label("Topic", systemImage: "square.stack.3d.up")
            }
            .disabled(session.labeledCount == 0 || session.isBusy)

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
                faceSession.reset()
                showFaceRename = true
            } label: {
                Label("Faces", systemImage: "person.crop.rectangle.stack")
            }
            .disabled(session.isBusy)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var workspaceEmpty: some View {
        VStack(spacing: 12) {
            Text("No supported images in this folder")
                .font(.title3)
            Text("Pick another folder, or go Home and choose a different action.")
                .foregroundStyle(.secondary)
            Button("Choose Folder") { session.chooseFolder() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

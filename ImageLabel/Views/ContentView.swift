import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var session: LabelingSession
    @State private var showSettings = false

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
                .frame(width: 520, height: 400)
        }
        .sheet(isPresented: $session.showRenamePreview) {
            RenamePreviewSheet()
                .environmentObject(session)
        }
        .sheet(isPresented: $session.showGroupPreview) {
            GroupPreviewSheet()
                .environmentObject(session)
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
            .disabled(session.items.isEmpty || session.isBusy || !settings.hasCredentials)
            .help(settings.hasCredentials ? "Run Google Vision label detection" : "Add credentials in Settings first")

            Button {
                session.prepareRenamePreview()
            } label: {
                Label("Rename Files…", systemImage: "pencil")
            }
            .disabled(session.labeledCount == 0 || session.isBusy)
            .help("Preview renaming each file to its best-score Vision label (no score in the name), then Apply")

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
            .help("Optional: move images into a folder for a label you pick")

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
            Text("1) Label with Vision → 2) Rename Files to the top label → optionally Group by Topic.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if !settings.hasCredentials {
                Text("Add your Vision API key or service-account JSON in Settings before labeling.")
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
}

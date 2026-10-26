import SwiftUI

@main
struct ImageLabelApp: App {
    @StateObject private var settings = SettingsStore()
    @StateObject private var session = LabelingSession()
    @StateObject private var processSession = ProcessFolderSession()
    @StateObject private var identityStore: FaceIdentityStore
    @StateObject private var faceSession: FaceRenameSession

    init() {
        let store = FaceIdentityStore()
        _identityStore = StateObject(wrappedValue: store)
        _faceSession = StateObject(wrappedValue: FaceRenameSession(identityStore: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(session)
                .environmentObject(processSession)
                .environmentObject(faceSession)
                .environmentObject(identityStore)
                .tint(AppTheme.accent)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(identityStore)
                .frame(width: 540, height: 520)
        }
    }
}

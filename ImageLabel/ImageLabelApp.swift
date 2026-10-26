import SwiftUI

@main
struct ImageLabelApp: App {
    @StateObject private var settings = SettingsStore()
    @StateObject private var session = LabelingSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(session)
                .frame(minWidth: 780, minHeight: 520)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }
}

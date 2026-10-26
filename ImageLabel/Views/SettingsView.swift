import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Picker("Authentication", selection: $settings.authMode) {
                    ForEach(SettingsStore.AuthMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Google Cloud Vision")
            } footer: {
                Text("Credentials stay on this Mac (API key in Keychain; JSON path in preferences). Nothing is committed to the repo.")
            }

            if settings.authMode == .apiKey {
                Section("API Key") {
                    SecureField("AIza…", text: $settings.apiKey)
                    Text("Enable the Cloud Vision API in your Google Cloud project, then create an API key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Service Account") {
                    HStack {
                        TextField("Path to JSON key file", text: $settings.serviceAccountPath)
                            .onSubmit {
                                let path = settings.serviceAccountPath.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !path.isEmpty else { return }
                                settings.setServiceAccountURL(URL(fileURLWithPath: path))
                            }
                        Button("Browse…") { pickServiceAccount() }
                    }
                    Text("Use a service-account key with the Cloud Vision User role (or broader). Prefer Browse so sandbox access is remembered. Keep the file outside this repo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Link(
                    "Vision API quickstart",
                    destination: URL(string: "https://cloud.google.com/vision/docs/setup")!
                )
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func pickServiceAccount() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "Choose"
        panel.message = "Select your Google Cloud service-account JSON key."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.setServiceAccountURL(url)
    }
}

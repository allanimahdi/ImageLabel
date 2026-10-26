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
                .onChange(of: settings.authMode) { _, _ in
                    settings.refreshCredentialStatus()
                }

                Text(settings.authMode.helpSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Google Cloud Vision")
            } footer: {
                Text("Credentials stay on this Mac (API key in Keychain; JSON path in preferences). Nothing is committed to the repo.")
            }

            if settings.authMode == .apiKey {
                Section {
                    SecureField("AIza…", text: $settings.apiKey)
                        .onChange(of: settings.apiKey) { _, _ in
                            settings.refreshCredentialStatus()
                        }
                    Text("Cloud Console → APIs & Services → Credentials → Create API key. Restrict it to Cloud Vision API when possible.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("API Key")
                } footer: {
                    Text("Do not paste a service-account JSON here. That mode is the other tab.")
                }
            } else {
                Section {
                    HStack {
                        TextField("Path to service-account JSON", text: $settings.serviceAccountPath)
                            .onSubmit {
                                let path = settings.serviceAccountPath.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !path.isEmpty else { return }
                                settings.setServiceAccountURL(URL(fileURLWithPath: path))
                            }
                        Button("Browse…") { pickServiceAccount() }
                    }
                    Text("IAM → Service accounts → Keys → Add key → JSON. Prefer Browse so sandbox access is remembered. Keep the file outside this repo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Service Account JSON")
                } footer: {
                    Text("Do not paste an API key into the path field. Use the API Key tab for that.")
                }
            }

            if let status = settings.credentialStatus {
                Section("Status") {
                    Text(status)
                        .foregroundStyle(statusContainsProblem(status) ? Color.orange : Color.secondary)
                        .textSelection(.enabled)
                }
            }

            Section {
                Link(
                    "Vision API setup",
                    destination: URL(string: "https://cloud.google.com/vision/docs/setup")!
                )
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 480, minHeight: 360)
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear { settings.refreshCredentialStatus() }
    }

    private func statusContainsProblem(_ status: String) -> Bool {
        let lowered = status.lowercased()
        return lowered.contains("looks like")
            || lowered.contains("missing")
            || lowered.contains("not found")
            || lowered.contains("could not")
            || lowered.contains("expected")
            || lowered.contains("invalid")
            || lowered.contains("switch")
            || lowered.contains("no api key")
            || lowered.contains("no service-account")
    }

    private func pickServiceAccount() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "Choose"
        panel.message = "Select your Google Cloud service-account JSON key (type: service_account)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.setServiceAccountURL(url)
    }
}

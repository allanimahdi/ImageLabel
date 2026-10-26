import Foundation
import Security
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let authMode = "authMode"
        static let serviceAccountPath = "serviceAccountPath"
        static let serviceAccountBookmark = "serviceAccountBookmark"
        static let keychainService = "com.imagelabel.credentials"
        static let keychainAccount = "googleVisionAPIKey"
    }

    enum AuthMode: String, CaseIterable, Identifiable {
        case apiKey = "API Key"
        case serviceAccount = "Service Account JSON"

        var id: String { rawValue }
    }

    @Published var authMode: AuthMode {
        didSet { UserDefaults.standard.set(authMode.rawValue, forKey: Keys.authMode) }
    }

    @Published var apiKey: String {
        didSet { Self.saveAPIKey(apiKey) }
    }

    @Published var serviceAccountPath: String = ""

    init() {
        let savedMode = UserDefaults.standard.string(forKey: Keys.authMode) ?? AuthMode.apiKey.rawValue
        authMode = AuthMode(rawValue: savedMode) ?? .apiKey
        apiKey = Self.loadAPIKey() ?? ""
        serviceAccountPath = UserDefaults.standard.string(forKey: Keys.serviceAccountPath) ?? ""
        _ = resolveServiceAccountURL()
    }

    /// Persists path + security-scoped bookmark so sandbox access survives relaunch.
    func setServiceAccountURL(_ url: URL) {
        serviceAccountPath = url.path
        UserDefaults.standard.set(url.path, forKey: Keys.serviceAccountPath)
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Keys.serviceAccountBookmark)
        } catch {
            UserDefaults.standard.removeObject(forKey: Keys.serviceAccountBookmark)
        }
    }

    func resolveServiceAccountURL() -> URL? {
        if let data = UserDefaults.standard.data(forKey: Keys.serviceAccountBookmark) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                if isStale {
                    setServiceAccountURL(url)
                }
                if serviceAccountPath != url.path {
                    serviceAccountPath = url.path
                }
                return url
            }
        }
        let path = serviceAccountPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    var hasCredentials: Bool {
        switch authMode {
        case .apiKey:
            return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .serviceAccount:
            let path = serviceAccountPath.trimmingCharacters(in: .whitespacesAndNewlines)
            return !path.isEmpty && FileManager.default.fileExists(atPath: path)
        }
    }

    func makeVisionClient() throws -> VisionClient {
        switch authMode {
        case .apiKey:
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                throw VisionError.missingCredentials("Add a Google Cloud Vision API key in Settings.")
            }
            return VisionClient(auth: .apiKey(key))
        case .serviceAccount:
            guard let url = resolveServiceAccountURL() else {
                throw VisionError.missingCredentials("Choose a service-account JSON file in Settings.")
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw VisionError.missingCredentials("Service-account JSON not found at \(url.path).")
            }
            return VisionClient(auth: .serviceAccount(url))
        }
    }

    // MARK: - Keychain

    private static func saveAPIKey(_ key: String) {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.keychainService,
            kSecAttrAccount as String: Keys.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        guard !key.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.keychainService,
            kSecAttrAccount as String: Keys.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

import Foundation
import Security

enum VisionAuth {
    case apiKey(String)
    case serviceAccount(URL)
}

enum VisionError: LocalizedError {
    case missingCredentials(String)
    case invalidImageData
    case httpStatus(Int, String)
    case decodeFailed(String)
    case noLabels
    case serviceAccount(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials(let message): return message
        case .invalidImageData: return "Could not read image data."
        case .httpStatus(let code, let body): return "Vision API HTTP \(code): \(body)"
        case .decodeFailed(let message): return "Unexpected Vision response: \(message)"
        case .noLabels: return "No labels returned for this image."
        case .serviceAccount(let message): return message
        }
    }
}

actor VisionClient {
    private let auth: VisionAuth
    private let session: URLSession
    private var cachedAccessToken: (token: String, expiry: Date)?
    private var cachedQuotaProjectID: String?

    init(auth: VisionAuth, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    func detectLabels(imageURL: URL, maxResults: Int = 10) async throws -> [VisionLabel] {
        let data = try ImageDataLoader.dataForVision(at: imageURL)

        let body: [String: Any] = [
            "requests": [
                [
                    "image": ["content": data.base64EncodedString()],
                    "features": [
                        ["type": "LABEL_DETECTION", "maxResults": maxResults]
                    ]
                ]
            ]
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)

        var request = try await makeAnnotateRequest()
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw VisionError.httpStatus(-1, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw VisionError.httpStatus(
                http.statusCode,
                GoogleAPIErrorFormatter.userMessage(statusCode: http.statusCode, body: responseData, auth: auth)
            )
        }

        let decoded = try JSONDecoder().decode(AnnotateResponse.self, from: responseData)
        if let apiError = decoded.responses.first?.error {
            let code = apiError.code ?? http.statusCode
            let raw = apiError.message ?? "API error"
            throw VisionError.httpStatus(
                code,
                GoogleAPIErrorFormatter.userMessage(
                    statusCode: code,
                    googleMessage: raw,
                    googleStatus: nil,
                    auth: auth
                )
            )
        }
        let annotations = decoded.responses.first?.labelAnnotations ?? []
        guard !annotations.isEmpty else { throw VisionError.noLabels }

        return annotations.map {
            VisionLabel(description: $0.description ?? "untitled", score: $0.score ?? 0)
        }
        .sorted { $0.score > $1.score }
    }

    private func makeAnnotateRequest() async throws -> URLRequest {
        switch auth {
        case .apiKey(let key):
            // API-key auth: query param only — never RSA / Bearer.
            var components = URLComponents(string: "https://vision.googleapis.com/v1/images:annotate")!
            components.queryItems = [URLQueryItem(name: "key", value: key)]
            guard let url = components.url else {
                throw VisionError.missingCredentials("Could not build Vision request URL.")
            }
            return URLRequest(url: url)
        case .serviceAccount(let url):
            let token = try await accessToken(serviceAccountURL: url)
            var request = URLRequest(url: URL(string: "https://vision.googleapis.com/v1/images:annotate")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            // Helps quota/billing attribution when org policies require a user project.
            if let projectID = cachedQuotaProjectID, !projectID.isEmpty {
                request.setValue(projectID, forHTTPHeaderField: "x-goog-user-project")
            }
            return request
        }
    }

    private func accessToken(serviceAccountURL: URL) async throws -> String {
        if let cached = cachedAccessToken, cached.expiry > Date().addingTimeInterval(60) {
            return cached.token
        }

        let credentials = try ServiceAccountCredentials.load(from: serviceAccountURL)
        cachedQuotaProjectID = credentials.projectID
        let now = Date()
        let claims: [String: Any] = [
            "iss": credentials.clientEmail,
            "scope": "https://www.googleapis.com/auth/cloud-vision",
            "aud": credentials.tokenURI,
            "iat": Int(now.timeIntervalSince1970),
            "exp": Int(now.addingTimeInterval(3600).timeIntervalSince1970)
        ]
        let assertion = try JWT.sign(claims: claims, privateKeyPEM: credentials.privateKey)

        var request = URLRequest(url: URL(string: credentials.tokenURI)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:jwt-bearer"),
            URLQueryItem(name: "assertion", value: assertion)
        ]
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw VisionError.serviceAccount(
                GoogleAPIErrorFormatter.userMessage(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1, body: data, auth: auth)
            )
        }
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        cachedAccessToken = (
            tokenResponse.accessToken,
            Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn ?? 3600))
        )
        return tokenResponse.accessToken
    }
}

// MARK: - Service account JSON

/// Parsed Google Cloud service-account key (values are never logged).
struct ServiceAccountCredentials: Equatable {
    let clientEmail: String
    let privateKey: String
    let tokenURI: String
    let projectID: String?

    /// Loads and validates a downloaded service-account JSON key file.
    static func load(from url: URL) throws -> ServiceAccountCredentials {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw VisionError.serviceAccount(
                "Could not read the service-account file. Use Browse… in Settings so sandbox access is granted."
            )
        }
        return try load(from: data)
    }

    static func load(from data: Data) throws -> ServiceAccountCredentials {
        let trimmed = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if trimmed.hasPrefix("AIza") || looksLikeAPIKeyOnly(trimmed) {
            throw VisionError.serviceAccount(
                "This looks like an API key, not a service-account JSON file. In Settings, choose “API Key” and paste the key there — or download a service-account key JSON from Google Cloud."
            )
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VisionError.serviceAccount(
                "The selected file is not valid JSON. Choose the service-account key file downloaded from Google Cloud (type: service_account)."
            )
        }

        if root["installed"] != nil || root["web"] != nil {
            throw VisionError.serviceAccount(
                "This looks like an OAuth client secret JSON, not a service-account key. In Google Cloud → IAM → Service accounts, create a key and download that JSON — or use an API key instead."
            )
        }

        if let type = root["type"] as? String, type != "service_account" {
            throw VisionError.serviceAccount(
                "JSON type is “\(type)”, expected “service_account”. Download a service-account key, or switch Settings to API Key."
            )
        }

        guard
            let email = root["client_email"] as? String, !email.isEmpty,
            let privateKey = root["private_key"] as? String, !privateKey.isEmpty,
            let tokenURI = root["token_uri"] as? String, !tokenURI.isEmpty
        else {
            throw VisionError.serviceAccount(
                "Missing client_email, private_key, or token_uri. Use a Google Cloud service-account key JSON (not an API key string)."
            )
        }

        guard privateKey.contains("BEGIN") && privateKey.contains("PRIVATE KEY") else {
            throw VisionError.serviceAccount(
                "private_key is missing PEM headers. Re-download the service-account key from Google Cloud."
            )
        }

        // Fail fast if the key cannot be imported (avoids cryptic OSStatus later).
        _ = try RSAKey(pem: privateKey)

        let projectID = (root["project_id"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ServiceAccountCredentials(
            clientEmail: email,
            privateKey: privateKey,
            tokenURI: tokenURI,
            projectID: (projectID?.isEmpty == false) ? projectID : nil
        )
    }

    private static func looksLikeAPIKeyOnly(_ text: String) -> Bool {
        // Single-line secret with no JSON structure.
        !text.contains("{") && !text.contains("\"") && text.count >= 20 && text.count <= 128
            && text.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
    }
}

// MARK: - Google API error surfacing (no secrets)

enum GoogleAPIErrorFormatter {
    static func userMessage(statusCode: Int, body: Data, auth: VisionAuth) -> String {
        let parsed = parse(body)
        return userMessage(
            statusCode: statusCode,
            googleMessage: parsed?.message,
            googleStatus: parsed?.status,
            auth: auth
        )
    }

    static func userMessage(
        statusCode: Int,
        googleMessage: String?,
        googleStatus: String?,
        auth: VisionAuth
    ) -> String {
        let cleaned = redactSecrets(googleMessage ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let status = googleStatus?.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = []
        if !cleaned.isEmpty {
            parts.append(cleaned)
        } else if let status, !status.isEmpty {
            parts.append(status)
        } else {
            parts.append("HTTP \(statusCode)")
        }

        if let hint = configurationHint(statusCode: statusCode, message: cleaned, status: status, auth: auth) {
            parts.append(hint)
        }
        return parts.joined(separator: " — ")
    }

    private static func parse(_ body: Data) -> (message: String, status: String?)? {
        guard
            let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let error = root["error"] as? [String: Any]
        else {
            let raw = String(data: body, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if raw.isEmpty { return nil }
            return (String(raw.prefix(400)), nil)
        }
        let message = (error["message"] as? String) ?? ""
        let status = error["status"] as? String
        return (String(message.prefix(500)), status)
    }

    /// Strip API keys / bearer tokens if Google ever echoes them (defensive).
    static func redactSecrets(_ text: String) -> String {
        var result = text
        // API keys
        if let regex = try? NSRegularExpression(pattern: #"AIza[0-9A-Za-z\-_]{10,}"#) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "AIza…REDACTED")
        }
        // Bearer tokens / long opaque secrets
        if let regex = try? NSRegularExpression(pattern: #"(?i)(Bearer\s+)[A-Za-z0-9._\-]{20,}"#) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1…REDACTED")
        }
        if let regex = try? NSRegularExpression(pattern: #"(?i)(key=)[A-Za-z0-9_\-]{10,}"#) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1…REDACTED")
        }
        return result
    }

    static func configurationHint(
        statusCode: Int,
        message: String,
        status: String?,
        auth: VisionAuth
    ) -> String? {
        let blob = (message + " " + (status ?? "")).lowercased()
        guard statusCode == 403 || statusCode == 401
            || blob.contains("permission")
            || blob.contains("forbidden")
            || blob.contains("denied")
            || blob.contains("disabled")
            || blob.contains("not been used")
            || blob.contains("billing")
        else {
            return nil
        }

        if blob.contains("not been used") || blob.contains("is disabled") || blob.contains("has not been used") {
            return "Enable Cloud Vision API for this GCP project: Console → APIs & Services → Library → “Cloud Vision API” → Enable. Wait a few minutes, then retry (⌘R)."
        }
        if blob.contains("billing") {
            return "Link a billing account to the GCP project (Billing → Link a billing account). Vision requires billing even within free-tier quotas."
        }
        if blob.contains("api key not valid") || blob.contains("api_key_invalid") || blob.contains("missing a valid api key") {
            return "Check Settings → API Key: paste a key from the same project where Vision is enabled. Under Credentials → your key → API restrictions, allow “Cloud Vision API” (or don’t restrict APIs while testing)."
        }
        if blob.contains("api_key_service_blocked") || blob.contains("api_key_http_referrer") || blob.contains("requests from this") {
            return "API key application restrictions are blocking this Mac app. In Console → Credentials → your key, set Application restrictions to None (or IP) while testing; API restrictions should include Cloud Vision API."
        }

        switch auth {
        case .apiKey:
            return "Likely GCP config: (1) enable Cloud Vision API, (2) ensure billing is linked, (3) fix API key restrictions (allow Cloud Vision API; avoid HTTP-referrer restriction for a Mac app). Same project as the key."
        case .serviceAccount:
            return "Likely GCP config: (1) enable Cloud Vision API on the service-account’s project, (2) link billing, (3) grant the SA “Cloud Vision AI User” (roles/serviceusage.serviceUsageConsumer may also be needed for quota). Then ⌘R."
        }
    }
}

// MARK: - API models

private struct AnnotateResponse: Decodable {
    struct Response: Decodable {
        let labelAnnotations: [Annotation]?
        let error: APIError?
    }
    struct Annotation: Decodable {
        let description: String?
        let score: Double?
    }
    struct APIError: Decodable {
        let code: Int?
        let message: String?
    }
    let responses: [Response]
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

// MARK: - Minimal JWT (RS256) for service accounts

enum JWT {
    static func sign(claims: [String: Any], privateKeyPEM: String) throws -> String {
        let header = ["alg": "RS256", "typ": "JWT"]
        let headerData = try JSONSerialization.data(withJSONObject: header)
        let claimsData = try JSONSerialization.data(withJSONObject: claims)
        let signingInput = "\(base64URL(headerData)).\(base64URL(claimsData))"

        let key = try RSAKey(pem: privateKeyPEM)
        let signature = try key.sign(Data(signingInput.utf8))
        return "\(signingInput).\(base64URL(signature))"
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - RSA private key import (PKCS#8 + PKCS#1)

/// Imports Google service-account private keys for JWT signing.
///
/// Google JSON keys use PKCS#8 (`BEGIN PRIVATE KEY`). `SecKeyCreateWithData` only
/// accepts the inner PKCS#1 `RSAPrivateKey` DER — passing PKCS#8 yields OSStatus -50
/// ("RSA private key creation from data failed").
struct RSAKey {
    let secKey: SecKey

    init(pem: String) throws {
        let normalized = pem
            .replacingOccurrences(of: "\\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let format: PEMFormat
        if normalized.contains("BEGIN RSA PRIVATE KEY") {
            format = .pkcs1
        } else if normalized.contains("BEGIN PRIVATE KEY") {
            format = .pkcs8
        } else {
            throw VisionError.serviceAccount(
                "Unrecognized private key PEM. Expected a Google service-account key (BEGIN PRIVATE KEY)."
            )
        }

        guard let der = Self.derBody(from: normalized) else {
            throw VisionError.serviceAccount("Invalid private key encoding (base64).")
        }

        let rsaDER: Data
        switch format {
        case .pkcs1:
            rsaDER = der
        case .pkcs8:
            do {
                rsaDER = try Self.rsaPrivateKeyDER(fromPKCS8: der)
            } catch {
                throw VisionError.serviceAccount(
                    "Could not read PKCS#8 private key. Re-download the service-account JSON from Google Cloud."
                )
            }
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(rsaDER as CFData, attributes as CFDictionary, &error) else {
            // Never include key material in the message.
            _ = error?.takeRetainedValue()
            throw VisionError.serviceAccount(
                "Could not import the RSA private key. Confirm Settings uses a service-account JSON key (not an API key), then try again."
            )
        }
        self.secKey = key
    }

    func sign(_ data: Data) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            secKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            &error
        ) as Data? else {
            _ = error?.takeRetainedValue()
            throw VisionError.serviceAccount("Failed to sign the service-account JWT.")
        }
        return signature
    }

    private enum PEMFormat {
        case pkcs1
        case pkcs8
    }

    private static func derBody(from pem: String) -> Data? {
        let stripped = pem
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Data(base64Encoded: stripped)
    }

    /// Unwraps PrivateKeyInfo (PKCS#8) → RSAPrivateKey DER for SecKeyCreateWithData.
    static func rsaPrivateKeyDER(fromPKCS8 pkcs8: Data) throws -> Data {
        var index = pkcs8.startIndex

        func readLength(_ i: inout Data.Index) throws -> Int {
            guard i < pkcs8.endIndex else {
                throw VisionError.serviceAccount("Truncated PKCS#8 key.")
            }
            let first = Int(pkcs8[i])
            i = pkcs8.index(after: i)
            if first & 0x80 == 0 { return first }
            let byteCount = first & 0x7F
            guard byteCount > 0, byteCount <= 4 else {
                throw VisionError.serviceAccount("Invalid PKCS#8 length.")
            }
            var length = 0
            for _ in 0..<byteCount {
                guard i < pkcs8.endIndex else {
                    throw VisionError.serviceAccount("Truncated PKCS#8 key.")
                }
                length = (length << 8) | Int(pkcs8[i])
                i = pkcs8.index(after: i)
            }
            return length
        }

        func expectTag(_ tag: UInt8, _ i: inout Data.Index) throws -> Int {
            guard i < pkcs8.endIndex, pkcs8[i] == tag else {
                throw VisionError.serviceAccount("Unexpected PKCS#8 structure.")
            }
            i = pkcs8.index(after: i)
            return try readLength(&i)
        }

        // PrivateKeyInfo ::= SEQUENCE { version, algorithm, privateKey OCTET STRING, ... }
        _ = try expectTag(0x30, &index)
        let versionLen = try expectTag(0x02, &index)
        guard pkcs8.distance(from: index, to: pkcs8.endIndex) >= versionLen else {
            throw VisionError.serviceAccount("Truncated PKCS#8 key.")
        }
        index = pkcs8.index(index, offsetBy: versionLen)

        let algorithmLen = try expectTag(0x30, &index)
        guard pkcs8.distance(from: index, to: pkcs8.endIndex) >= algorithmLen else {
            throw VisionError.serviceAccount("Truncated PKCS#8 key.")
        }
        index = pkcs8.index(index, offsetBy: algorithmLen)

        let keyLen = try expectTag(0x04, &index)
        guard pkcs8.distance(from: index, to: pkcs8.endIndex) >= keyLen else {
            throw VisionError.serviceAccount("Truncated PKCS#8 key.")
        }
        return Data(pkcs8[index..<pkcs8.index(index, offsetBy: keyLen)])
    }
}

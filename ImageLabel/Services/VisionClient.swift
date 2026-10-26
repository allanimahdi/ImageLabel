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
            let text = String(data: responseData, encoding: .utf8) ?? ""
            throw VisionError.httpStatus(http.statusCode, text.prefix(400).description)
        }

        let decoded = try JSONDecoder().decode(AnnotateResponse.self, from: responseData)
        if let apiError = decoded.responses.first?.error {
            throw VisionError.httpStatus(apiError.code ?? http.statusCode, apiError.message ?? "API error")
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
            // API-key auth never touches RSA / JWT.
            var components = URLComponents(string: "https://vision.googleapis.com/v1/images:annotate")!
            components.queryItems = [URLQueryItem(name: "key", value: key)]
            return URLRequest(url: components.url!)
        case .serviceAccount(let url):
            let token = try await accessToken(serviceAccountURL: url)
            var request = URLRequest(url: URL(string: "https://vision.googleapis.com/v1/images:annotate")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return request
        }
    }

    private func accessToken(serviceAccountURL: URL) async throws -> String {
        if let cached = cachedAccessToken, cached.expiry > Date().addingTimeInterval(60) {
            return cached.token
        }

        let credentials = try ServiceAccountCredentials.load(from: serviceAccountURL)
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
        let form = "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=\(assertion)"
        request.httpBody = Data(form.utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw VisionError.serviceAccount("Token request failed: \(text.prefix(300))")
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

        return ServiceAccountCredentials(
            clientEmail: email,
            privateKey: privateKey,
            tokenURI: tokenURI
        )
    }

    private static func looksLikeAPIKeyOnly(_ text: String) -> Bool {
        // Single-line secret with no JSON structure.
        !text.contains("{") && !text.contains("\"") && text.count >= 20 && text.count <= 128
            && text.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
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

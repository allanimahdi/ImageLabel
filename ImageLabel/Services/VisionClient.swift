import Foundation

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

        let credentials = try JSONDecoder().decode(
            ServiceAccountCredentials.self,
            from: Data(contentsOf: serviceAccountURL)
        )
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

private struct ServiceAccountCredentials: Decodable {
    let clientEmail: String
    let privateKey: String
    let tokenURI: String

    enum CodingKeys: String, CodingKey {
        case clientEmail = "client_email"
        case privateKey = "private_key"
        case tokenURI = "token_uri"
    }
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

private enum JWT {
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

/// Thin SecKey wrapper for PKCS#8 RSA private keys from Google service-account JSON.
private struct RSAKey {
    let secKey: SecKey

    init(pem: String) throws {
        let stripped = pem
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\\n", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let der = Data(base64Encoded: stripped) else {
            throw VisionError.serviceAccount("Invalid private key encoding.")
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &error) else {
            let message = error?.takeRetainedValue().localizedDescription ?? "SecKey create failed"
            throw VisionError.serviceAccount(message)
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
            let message = error?.takeRetainedValue().localizedDescription ?? "Sign failed"
            throw VisionError.serviceAccount(message)
        }
        return signature
    }
}

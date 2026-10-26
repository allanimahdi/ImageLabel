import XCTest
@testable import ImageLabel

final class CredentialCryptoTests: XCTestCase {
    func testPKCS8PrivateKeyImportsAndSigns() throws {
        let pem = try Self.generatePEM(pkcs8: true)
        let key = try RSAKey(pem: pem)
        let signature = try key.sign(Data("imagelabel-jwt-test".utf8))
        XCTAssertFalse(signature.isEmpty)
    }

    func testPKCS1PrivateKeyImportsAndSigns() throws {
        let pem = try Self.generatePEM(pkcs8: false)
        let key = try RSAKey(pem: pem)
        let signature = try key.sign(Data("imagelabel-jwt-test".utf8))
        XCTAssertFalse(signature.isEmpty)
    }

    func testLiteralEscapedNewlinesInPrivateKey() throws {
        // Mimic JSON where someone double-escaped newlines into the string value.
        let pem = try Self.generatePEM(pkcs8: true)
        let escaped = pem.replacingOccurrences(of: "\n", with: "\\n")
        let key = try RSAKey(pem: escaped)
        XCTAssertNotNil(key.secKey)
    }

    func testServiceAccountJSONLoadsPKCS8() throws {
        let pem = try Self.generatePEM(pkcs8: true)
        let json: [String: Any] = [
            "type": "service_account",
            "client_email": "test@test-project.iam.gserviceaccount.com",
            "private_key": pem,
            "token_uri": "https://oauth2.googleapis.com/token"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let creds = try ServiceAccountCredentials.load(from: data)
        XCTAssertEqual(creds.clientEmail, "test@test-project.iam.gserviceaccount.com")
        XCTAssertTrue(creds.privateKey.contains("BEGIN PRIVATE KEY"))
    }

    func testAPIKeyStringRejectedAsServiceAccount() {
        let data = Data("AIzaSyDummyTestKeyNotReal000000000000".utf8)
        XCTAssertThrowsError(try ServiceAccountCredentials.load(from: data)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(message.localizedCaseInsensitiveContains("API key"), message)
        }
    }

    func testOAuthClientJSONRejected() throws {
        let json: [String: Any] = [
            "installed": ["client_id": "x", "client_secret": "y"]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try ServiceAccountCredentials.load(from: data)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(message.localizedCaseInsensitiveContains("OAuth"), message)
        }
    }

    func testJWTSignsWithPKCS8() throws {
        let pem = try Self.generatePEM(pkcs8: true)
        let token = try JWT.sign(
            claims: [
                "iss": "test@test-project.iam.gserviceaccount.com",
                "scope": "https://www.googleapis.com/auth/cloud-vision",
                "aud": "https://oauth2.googleapis.com/token",
                "iat": 1_700_000_000,
                "exp": 1_700_003_600
            ],
            privateKeyPEM: pem
        )
        let parts = token.split(separator: ".")
        XCTAssertEqual(parts.count, 3)
        // Ensure we never accidentally embed the PEM in the JWT.
        XCTAssertFalse(token.contains("BEGIN"))
        XCTAssertFalse(token.contains("PRIVATE"))
    }

    // MARK: - OpenSSL fixtures (throwaway; never committed)

    private static func generatePEM(pkcs8: Bool) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageLabelCredTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let rawURL = dir.appendingPathComponent("raw.pem")
        let pkcs1URL = dir.appendingPathComponent("pkcs1.pem")
        let pkcs8URL = dir.appendingPathComponent("pkcs8.pem")

        // LibreSSL's /usr/bin/openssl rejects genrsa -traditional; OpenSSL 3 accepts
        // `rsa -traditional`. Prefer Homebrew openssl when present.
        try runOpenSSL(["genrsa", "-out", rawURL.path, "2048"])
        try runOpenSSL([
            "pkcs8", "-topk8", "-nocrypt",
            "-in", rawURL.path,
            "-out", pkcs8URL.path
        ])
        // Convert to PKCS#1 PEM when possible (needed for the PKCS#1 import test).
        do {
            try runOpenSSL(["rsa", "-in", rawURL.path, "-traditional", "-out", pkcs1URL.path])
        } catch {
            try runOpenSSL(["rsa", "-in", rawURL.path, "-out", pkcs1URL.path])
        }

        let url = pkcs8 ? pkcs8URL : pkcs1URL
        let pem = try String(contentsOf: url, encoding: .utf8)
        if pkcs8 {
            XCTAssertTrue(pem.contains("BEGIN PRIVATE KEY"), "expected PKCS#8 PEM")
            XCTAssertFalse(pem.contains("BEGIN RSA PRIVATE KEY"))
        } else {
            XCTAssertTrue(
                pem.contains("BEGIN RSA PRIVATE KEY"),
                "expected PKCS#1 PEM; got headers: \(pem.split(separator: "\n").prefix(1))"
            )
        }
        return pem
    }

    private static func opensslExecutable() -> URL {
        let candidates = [
            "/usr/local/bin/openssl",
            "/opt/homebrew/bin/openssl",
            "/usr/bin/openssl"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "/usr/bin/openssl")
    }

    private static func runOpenSSL(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = opensslExecutable()
        process.arguments = arguments
        let err = Pipe()
        process.standardError = err
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(
                domain: "CredentialCryptoTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "openssl failed: \(message)"]
            )
        }
    }
}

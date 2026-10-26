import XCTest
@testable import ImageLabel

final class GoogleAPIErrorFormatterTests: XCTestCase {
    func testParsesPermissionDeniedAndHintsEnableAPI() {
        let body = Data("""
        {"error":{"code":403,"message":"Cloud Vision API has not been used in project 123 before or it is disabled.","status":"PERMISSION_DENIED"}}
        """.utf8)
        let message = GoogleAPIErrorFormatter.userMessage(
            statusCode: 403,
            body: body,
            auth: .apiKey("AIzaSyDummyTestKeyNotReal000000000000")
        )
        XCTAssertTrue(message.contains("Cloud Vision API has not been used"), message)
        XCTAssertTrue(message.localizedCaseInsensitiveContains("Enable Cloud Vision API"), message)
        XCTAssertFalse(message.contains("AIzaSyDummy"), "must not echo API key")
    }

    func testRedactsAPIKeyInRawBody() {
        let body = Data("key=AIzaSyDummyTestKeyNotReal000000000000 failed".utf8)
        let message = GoogleAPIErrorFormatter.userMessage(
            statusCode: 403,
            body: body,
            auth: .apiKey("unused")
        )
        XCTAssertTrue(message.contains("REDACTED"), message)
        XCTAssertFalse(message.contains("AIzaSyDummyTestKeyNotReal000000000000"))
    }

    func testServiceAccountHintMentionsIAM() {
        let message = GoogleAPIErrorFormatter.userMessage(
            statusCode: 403,
            googleMessage: "Permission denied on resource",
            googleStatus: "PERMISSION_DENIED",
            auth: .serviceAccount(URL(fileURLWithPath: "/tmp/sa.json"))
        )
        XCTAssertTrue(message.localizedCaseInsensitiveContains("Cloud Vision"), message)
        XCTAssertTrue(message.localizedCaseInsensitiveContains("service account") || message.contains("SA"), message)
    }

    func testBillingHint() {
        let message = GoogleAPIErrorFormatter.userMessage(
            statusCode: 403,
            googleMessage: "This API method requires billing to be enabled.",
            googleStatus: "PERMISSION_DENIED",
            auth: .apiKey("x")
        )
        XCTAssertTrue(message.localizedCaseInsensitiveContains("billing"), message)
    }
}

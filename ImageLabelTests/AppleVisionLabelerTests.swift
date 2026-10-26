import AppKit
import XCTest
@testable import ImageLabel

final class AppleVisionLabelerTests: XCTestCase {
    func testHumanizeIdentifierReplacesUnderscores() {
        XCTAssertEqual(AppleVisionLabeler.humanizeIdentifier("golden_retriever"), "golden retriever")
        XCTAssertEqual(AppleVisionLabeler.humanizeIdentifier("Dog"), "Dog")
    }

    func testLocalLabelerReturnsLabelsOrClearError() async throws {
        let url = try Self.writeSolidJPEG()
        defer { try? FileManager.default.removeItem(at: url) }

        let labeler = AppleVisionLabeler(minimumConfidence: 0.01, weakFallbackConfidence: 0.001)
        do {
            let labels = try await labeler.detectLabels(imageURL: url, maxResults: 5)
            XCTAssertFalse(labels.isEmpty)
            XCTAssertGreaterThan(labels[0].score, 0)
            XCTAssertFalse(labels[0].description.isEmpty)
            // Scores must not be embedded in the description used for rename.
            XCTAssertFalse(labels[0].description.contains("%"))
        } catch let error as VisionError {
            // Solid-color JPEGs may yield no confident classes — error must be user-facing, not a crash.
            let text = error.localizedDescription
            XCTAssertFalse(text.isEmpty)
            XCTAssertTrue(
                text.localizedCaseInsensitiveContains("Apple Vision")
                    || text.localizedCaseInsensitiveContains("No labels"),
                text
            )
        }
    }

    func testBasenameFromLocalStyleLabelHasNoScore() {
        let base = FilenameSanitizer.basename(from: "Golden Retriever")
        XCTAssertEqual(base, "golden_retriever")
        XCTAssertFalse(base.contains("0."))
    }

    private static func writeSolidJPEG() throws -> URL {
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        else {
            throw NSError(domain: "AppleVisionLabelerTests", code: 1)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageLabel-local-\(UUID().uuidString).jpg")
        try data.write(to: url)
        return url
    }
}

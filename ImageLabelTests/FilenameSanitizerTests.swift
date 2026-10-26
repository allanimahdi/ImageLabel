import XCTest
@testable import ImageLabel

final class FilenameSanitizerTests: XCTestCase {
    func testBasenameLowercasesAndUnderscores() {
        XCTAssertEqual(FilenameSanitizer.basename(from: "Golden Retriever"), "golden_retriever")
    }

    func testBasenameStripsPunctuation() {
        XCTAssertEqual(FilenameSanitizer.basename(from: "Dog / Cat!"), "dog_cat")
    }

    func testEmptyBecomesUntitled() {
        XCTAssertEqual(FilenameSanitizer.basename(from: "!!!"), "untitled")
    }

    func testUniqueURLAllowsSelf() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageLabelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let existing = dir.appendingPathComponent("golden_retriever.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: existing)

        var reserved = Set<String>()
        let dest = FilenameSanitizer.uniqueURL(
            directory: dir,
            basename: "golden_retriever",
            ext: "jpg",
            reserved: &reserved,
            allowing: existing
        )
        XCTAssertEqual(dest.lastPathComponent, "golden_retriever.jpg")
    }

    func testUniqueURLSuffixesOnCollision() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageLabelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let existing = dir.appendingPathComponent("cat.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: existing)

        var reserved = Set<String>()
        let other = dir.appendingPathComponent("other.jpg")
        let dest = FilenameSanitizer.uniqueURL(
            directory: dir,
            basename: "cat",
            ext: "jpg",
            reserved: &reserved,
            allowing: other
        )
        XCTAssertEqual(dest.lastPathComponent, "cat_2.jpg")
    }
}

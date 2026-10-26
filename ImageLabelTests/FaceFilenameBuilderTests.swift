import XCTest
@testable import ImageLabel

final class FaceFilenameBuilderTests: XCTestCase {
    func testBasenameJoinsPeopleWithHyphen() {
        XCTAssertEqual(
            FaceFilenameBuilder.basename(fromPersonNames: ["Mahdi", "Marija"]),
            "Mahdi-Marija"
        )
    }

    func testSanitizeRemovesIllegalCharacters() {
        XCTAssertEqual(FaceFilenameBuilder.sanitizePersonName("Mary Jane"), "MaryJane")
        XCTAssertEqual(FaceFilenameBuilder.sanitizePersonName(" ann "), "ann")
        XCTAssertEqual(FaceFilenameBuilder.sanitizePersonName("Bob/../"), "Bob")
    }

    func testDedupesCaseInsensitive() {
        XCTAssertEqual(
            FaceFilenameBuilder.basename(fromPersonNames: ["Mahdi", "mahdi", "Pedro"]),
            "Mahdi-Pedro"
        )
    }

    func testUniqueURLUsesNumericSuffix() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FaceRename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data([0xFF]).write(to: dir.appendingPathComponent("Mahdi.jpg"))
        var reserved: Set<String> = ["mahdi.jpg"]
        let dest = FaceFilenameBuilder.uniqueURL(
            directory: dir,
            basename: "Mahdi",
            ext: "jpg",
            reserved: &reserved,
            allowing: nil
        )
        XCTAssertEqual(dest.lastPathComponent, "Mahdi-002.jpg")
    }

    func testClusteringMergesClosePairs() {
        // Distance matrix via closure: 0-1 close, 2 far
        let clusters = FaceClusteringService.cluster(count: 3, threshold: 0.5) { i, j in
            let pair = Set([i, j])
            if pair == Set([0, 1]) { return 0.2 }
            return 0.9
        }
        XCTAssertEqual(clusters.count, 2)
        XCTAssertTrue(clusters.contains([0, 1]))
        XCTAssertTrue(clusters.contains([2]))
    }
}

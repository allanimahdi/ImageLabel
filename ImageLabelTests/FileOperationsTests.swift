import XCTest
@testable import ImageLabel

final class FileOperationsTests: XCTestCase {
    func testRenamePlansUseTopLabelWithoutScore() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = dir.appendingPathComponent("IMG_001.jpg")
        let b = dir.appendingPathComponent("photo.png")
        try Data([0xFF, 0xD8, 0xFF]).write(to: a)
        try Data([0x89, 0x50]).write(to: b)

        let items = [
            ImageItem(
                id: a,
                url: a,
                labels: [
                    VisionLabel(description: "Golden Retriever", score: 0.97),
                    VisionLabel(description: "Dog", score: 0.5)
                ],
                status: .labeled
            ),
            ImageItem(
                id: b,
                url: b,
                labels: [VisionLabel(description: "Cat / Kitten!", score: 0.88)],
                status: .labeled
            )
        ]

        let plans = FileOperations.buildRenamePlans(for: items)
        XCTAssertEqual(plans.count, 2)
        XCTAssertEqual(plans[0].destination.lastPathComponent, "golden_retriever.jpg")
        XCTAssertEqual(plans[1].destination.lastPathComponent, "cat_kitten.png")
        XCTAssertFalse(plans[0].destination.lastPathComponent.contains("0.97"))
        XCTAssertTrue(plans[0].changesName)
    }

    func testRenamePlansCollisionSuffixes() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = dir.appendingPathComponent("a.jpg")
        let b = dir.appendingPathComponent("b.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: a)
        try Data([0xFF, 0xD8, 0xFF]).write(to: b)

        let dog = VisionLabel(description: "Dog", score: 0.9)
        let items = [
            ImageItem(id: a, url: a, labels: [dog], status: .labeled),
            ImageItem(id: b, url: b, labels: [dog], status: .labeled)
        ]
        let plans = FileOperations.buildRenamePlans(for: items)
        let names = Set(plans.map { $0.destination.lastPathComponent })
        XCTAssertEqual(names, ["dog.jpg", "dog_2.jpg"])
    }

    func testApplyRenamesMovesFilesOnDisk() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("raw.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: source)
        var item = ImageItem(
            id: source,
            url: source,
            labels: [VisionLabel(description: "Beach", score: 0.91)],
            status: .labeled
        )
        let plans = FileOperations.buildRenamePlans(for: [item])
        let applied = try FileOperations.applyRenames(plans)
        XCTAssertEqual(applied.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: plans[0].destination.path))
        XCTAssertEqual(plans[0].destination.lastPathComponent, "beach.jpg")

        // Keep compiler happy if we later mutate item in session-style updates.
        item.status = .renamed
        XCTAssertEqual(item.status, .renamed)
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageLabelRename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

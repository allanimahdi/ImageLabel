import XCTest
@testable import ImageLabel

final class MainCategoryMapperTests: XCTestCase {
    func testFineAnimalLabelMapsToAnimals() {
        let labels = [
            VisionLabel(description: "Golden Retriever", score: 0.96),
            VisionLabel(description: "Dog", score: 0.9),
            VisionLabel(description: "Pet", score: 0.7)
        ]
        let assignment = MainCategoryMapper.assign(labels: labels)
        XCTAssertEqual(assignment?.category, .animals)
    }

    func testFoodBeatsWeakerNature() {
        let labels = [
            VisionLabel(description: "Pizza", score: 0.92),
            VisionLabel(description: "Plant", score: 0.2)
        ]
        let assignment = MainCategoryMapper.assign(labels: labels)
        XCTAssertEqual(assignment?.category, .food)
        XCTAssertEqual(assignment?.matchedLabel, "Pizza")
    }

    func testUnmatchedGoesToOther() {
        let labels = [VisionLabel(description: "Xyzzy Unknown Widget", score: 0.8)]
        let assignment = MainCategoryMapper.assign(labels: labels)
        XCTAssertEqual(assignment?.category, .other)
        XCTAssertEqual(assignment?.matchedLabel, "Xyzzy Unknown Widget")
    }

    func testPeoplePortrait() {
        let labels = [VisionLabel(description: "Portrait", score: 0.85)]
        XCTAssertEqual(MainCategoryMapper.assign(labels: labels)?.category, .people)
    }

    func testAutoGroupPlansCreateCategoryFolders() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageLabelAutoGroup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let dog = dir.appendingPathComponent("a.jpg")
        let pie = dir.appendingPathComponent("b.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: dog)
        try Data([0xFF, 0xD8, 0xFF]).write(to: pie)

        let items = [
            ImageItem(
                id: dog,
                url: dog,
                labels: [VisionLabel(description: "Golden Retriever", score: 0.9)],
                status: .labeled
            ),
            ImageItem(
                id: pie,
                url: pie,
                labels: [VisionLabel(description: "Pizza", score: 0.88)],
                status: .labeled
            )
        ]

        let plans = FileOperations.buildAutoGroupPlans(for: items, root: dir)
        XCTAssertEqual(plans.count, 2)
        let topics = Set(plans.map(\.topic))
        XCTAssertEqual(topics, ["Animals", "Food"])

        let applied = try FileOperations.applyGroups(plans)
        XCTAssertEqual(applied.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Animals/a.jpg").path)
            || FileManager.default.fileExists(atPath: dir.appendingPathComponent("Animals").path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Animals").appendingPathComponent("a.jpg").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Food").appendingPathComponent("b.jpg").path
            )
        )
    }

    func testCategoryCountIsSmall() {
        // Guard against accidentally exploding into many niche folders.
        XCTAssertLessThanOrEqual(MainCategory.allCases.count, 12)
    }
}

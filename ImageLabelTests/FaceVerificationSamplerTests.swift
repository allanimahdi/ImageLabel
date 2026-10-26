import XCTest
@testable import ImageLabel

final class FaceVerificationSamplerTests: XCTestCase {
    func testSampleSizeSmallAlbumUsesTwentyPercentRoundedUp() {
        // Spec: 80 photos, 120 faces → ceil(24) = 24
        XCTAssertEqual(
            FaceVerificationSampler.requiredSampleSize(photoCount: 80, uniqueFaceCount: 120),
            24
        )
    }

    func testSampleSizeLargeAlbumUsesFivePercentRoundedUp() {
        // Spec: 300 photos, 450 faces → ceil(22.5) = 23
        XCTAssertEqual(
            FaceVerificationSampler.requiredSampleSize(photoCount: 300, uniqueFaceCount: 450),
            23
        )
    }

    func testSampleSizeBoundaryAt100PhotosStillTwentyPercent() {
        XCTAssertEqual(
            FaceVerificationSampler.requiredSampleSize(photoCount: 100, uniqueFaceCount: 10),
            2
        )
        XCTAssertEqual(
            FaceVerificationSampler.requiredSampleSize(photoCount: 101, uniqueFaceCount: 10),
            1
        )
    }

    func testSampleSizeZeroFaces() {
        XCTAssertEqual(
            FaceVerificationSampler.requiredSampleSize(photoCount: 50, uniqueFaceCount: 0),
            0
        )
    }

    func testSampleSizeCountsFacesNotPhotos() {
        // 50 photos but 7 faces → ceil(1.4) = 2
        XCTAssertEqual(
            FaceVerificationSampler.requiredSampleSize(photoCount: 50, uniqueFaceCount: 7),
            2
        )
    }

    func testSelectionCoversGroupsAndSkipsNearDuplicates() {
        let g1 = UUID()
        let g2 = UUID()
        let faces = (0..<6).map { _ in UUID() }
        let candidates = [
            FaceVerificationSampler.Candidate(
                faceID: faces[0], groupID: g1, uncertainty: 1.0, diversityBucket: 1, nearDuplicateKey: 0
            ),
            FaceVerificationSampler.Candidate(
                faceID: faces[1], groupID: g1, uncertainty: 0.9, diversityBucket: 1, nearDuplicateKey: 0
            ), // near-dupe of 0 — should drop
            FaceVerificationSampler.Candidate(
                faceID: faces[2], groupID: g1, uncertainty: 0.5, diversityBucket: 2, nearDuplicateKey: 1
            ),
            FaceVerificationSampler.Candidate(
                faceID: faces[3], groupID: g2, uncertainty: 0.8, diversityBucket: 3, nearDuplicateKey: 2
            ),
            FaceVerificationSampler.Candidate(
                faceID: faces[4], groupID: g2, uncertainty: 0.2, diversityBucket: 4, nearDuplicateKey: 3
            ),
            FaceVerificationSampler.Candidate(
                faceID: faces[5], groupID: g2, uncertainty: 0.1, diversityBucket: 5, nearDuplicateKey: 4
            ),
        ]

        let selected = FaceVerificationSampler.selectFaceIDs(from: candidates, limit: 3)
        XCTAssertEqual(selected.count, 3)
        XCTAssertFalse(selected.contains(faces[1]), "Near-duplicate should not both be asked")
        XCTAssertTrue(selected.contains(faces[0]), "Higher-uncertainty near-dupe survivor")
        // Both groups represented when limit allows
        let selectedSet = Set(selected)
        let g1Hit = selectedSet.contains(faces[0]) || selectedSet.contains(faces[2])
        let g2Hit = selectedSet.contains(faces[3]) || selectedSet.contains(faces[4]) || selectedSet.contains(faces[5])
        XCTAssertTrue(g1Hit && g2Hit)
    }

    func testSelectionIsDeterministic() {
        let g = UUID()
        let faces = (0..<5).map { _ in UUID() }
        let candidates = faces.enumerated().map { index, id in
            FaceVerificationSampler.Candidate(
                faceID: id,
                groupID: g,
                uncertainty: Float(5 - index) / 5,
                diversityBucket: index,
                nearDuplicateKey: index
            )
        }
        let a = FaceVerificationSampler.selectFaceIDs(from: candidates, limit: 3)
        let b = FaceVerificationSampler.selectFaceIDs(from: candidates, limit: 3)
        XCTAssertEqual(a, b)
    }
}

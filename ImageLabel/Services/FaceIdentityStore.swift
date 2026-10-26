import AppKit
import Foundation
import Vision

/// Optional on-device persistence of named people (representative face crop + name). Never uploaded.
@MainActor
final class FaceIdentityStore: ObservableObject {
    struct StoredIdentity: Identifiable, Codable, Equatable {
        let id: UUID
        var name: String
        /// Relative filename under Application Support faces directory.
        var thumbnailFileName: String
        var updatedAt: Date
    }

    @Published private(set) var identities: [StoredIdentity] = []

    private let fileManager = FileManager.default
    private var directoryURL: URL
    private var indexURL: URL

    init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ImageLabel", isDirectory: true)
            .appendingPathComponent("FaceIdentities", isDirectory: true)
        directoryURL = base
        indexURL = base.appendingPathComponent("identities.json")
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([StoredIdentity].self, from: data)
        else {
            identities = []
            return
        }
        identities = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(identities) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    func thumbnail(for identity: StoredIdentity) -> NSImage? {
        let url = directoryURL.appendingPathComponent(identity.thumbnailFileName)
        return NSImage(contentsOf: url)
    }

    func upsert(name: String, thumbnail: NSImage) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let index = identities.firstIndex(where: { $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
            var updated = identities[index]
            if let fileName = writeThumbnail(thumbnail, id: updated.id) {
                updated.thumbnailFileName = fileName
            }
            updated.name = trimmed
            updated.updatedAt = Date()
            identities[index] = updated
        } else {
            let id = UUID()
            guard let fileName = writeThumbnail(thumbnail, id: id) else { return }
            identities.append(
                StoredIdentity(id: id, name: trimmed, thumbnailFileName: fileName, updatedAt: Date())
            )
        }
        save()
    }

    func deleteAll() {
        for identity in identities {
            let url = directoryURL.appendingPathComponent(identity.thumbnailFileName)
            try? fileManager.removeItem(at: url)
        }
        identities = []
        try? fileManager.removeItem(at: indexURL)
        save()
    }

    /// Best matching saved identity for a new face print, if within `threshold`.
    func bestMatch(
        to featurePrint: VNFeaturePrintObservation,
        threshold: Float
    ) -> (identity: StoredIdentity, distance: Float)? {
        var best: (StoredIdentity, Float)?
        for identity in identities {
            let url = directoryURL.appendingPathComponent(identity.thumbnailFileName)
            guard let image = NSImage(contentsOf: url),
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let cg = rep.cgImage,
                  let storedPrint = try? FaceDetectionService.featurePrint(for: cg)
            else { continue }
            let d = FaceDetectionService.distance(featurePrint, storedPrint)
            if d <= threshold {
                if best == nil || d < best!.1 {
                    best = (identity, d)
                }
            }
        }
        return best.map { (identity: $0.0, distance: $0.1) }
    }

    private func writeThumbnail(_ image: NSImage, id: UUID) -> String? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        else { return nil }
        let name = "\(id.uuidString).jpg"
        let url = directoryURL.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }
}

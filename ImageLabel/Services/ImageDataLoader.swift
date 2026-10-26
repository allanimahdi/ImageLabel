import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageDataLoader {
    /// Loads bytes for Vision. Re-encodes HEIC/HEIF (and other non-JPEG/PNG/GIF/WEBP/BMP/TIFF)
    /// to JPEG so the API accepts them.
    static func dataForVision(at url: URL) throws -> Data {
        let ext = url.pathExtension.lowercased()
        let native: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "webp", "tif", "tiff"]
        if native.contains(ext) {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else { throw VisionError.invalidImageData }
            return data
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw VisionError.invalidImageData
        }

        let mutable = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutable,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw VisionError.invalidImageData
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.92]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw VisionError.invalidImageData
        }
        return mutable as Data
    }
}

import AppKit
import Foundation
import ImageIO
import Vision

/// On-device face detection + feature-print embeddings (no network).
enum FaceDetectionService {
    /// Fast presence check: rectangles only (no crops / embeddings).
    static func imageContainsFaces(at imageURL: URL) throws -> Bool {
        guard let cgImage = loadCGImage(url: imageURL) else {
            throw VisionError.labeling("Could not read image for face detection: \(imageURL.lastPathComponent)")
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let faceRequest = VNDetectFaceRectanglesRequest()
        faceRequest.revision = VNDetectFaceRectanglesRequestRevision3
        try handler.perform([faceRequest])
        return !(faceRequest.results ?? []).isEmpty
    }

    /// Detect faces and compute `VNFeaturePrintObservation` embeddings on each crop.
    static func detectFaces(in imageURL: URL) throws -> [DetectedFace] {
        guard let cgImage = loadCGImage(url: imageURL) else {
            throw VisionError.labeling("Could not read image for face detection: \(imageURL.lastPathComponent)")
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let faceRequest = VNDetectFaceRectanglesRequest()
        faceRequest.revision = VNDetectFaceRectanglesRequestRevision3
        try handler.perform([faceRequest])

        let observations = faceRequest.results ?? []
        guard !observations.isEmpty else { return [] }

        var faces: [DetectedFace] = []
        for observation in observations {
            let box = observation.boundingBox
            guard let crop = cropFace(cgImage: cgImage, normalizedBox: box, padding: 0.25) else { continue }
            guard let printObs = try? featurePrint(for: crop) else { continue }
            let thumb = NSImage(cgImage: crop, size: NSSize(width: crop.width, height: crop.height))
            let midX = box.origin.x + box.size.width / 2
            faces.append(
                DetectedFace(
                    imageURL: imageURL,
                    boundingBox: box,
                    midX: midX,
                    thumbnail: thumb,
                    featurePrint: printObs,
                    captureQuality: nil
                )
            )
        }
        return faces
    }

    static func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float {
        var value: Float = .greatestFiniteMagnitude
        do {
            try a.computeDistance(&value, to: b)
            return value
        } catch {
            return .greatestFiniteMagnitude
        }
    }

    static func featurePrint(for cgImage: CGImage) throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        guard let result = request.results?.first as? VNFeaturePrintObservation else {
            throw VisionError.labeling("Could not compute face embedding.")
        }
        return result
    }

    // MARK: - Image helpers

    private static func loadCGImage(url: URL) -> CGImage? {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return image
        }
        guard let ns = NSImage(contentsOf: url),
              let tiff = ns.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage
        else { return nil }
        return cg
    }

    private static func cropFace(cgImage: CGImage, normalizedBox: CGRect, padding: CGFloat) -> CGImage? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        // Vision: origin bottom-left → CoreGraphics top-left
        var rect = CGRect(
            x: normalizedBox.origin.x * width,
            y: (1 - normalizedBox.origin.y - normalizedBox.height) * height,
            width: normalizedBox.width * width,
            height: normalizedBox.height * height
        )
        let padX = rect.width * padding
        let padY = rect.height * padding
        rect = rect.insetBy(dx: -padX, dy: -padY)
        rect = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard rect.width > 8, rect.height > 8 else { return nil }
        return cgImage.cropping(to: rect.integral)
    }
}

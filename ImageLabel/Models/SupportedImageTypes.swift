import UniformTypeIdentifiers

enum SupportedImageTypes {
    static let pathExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "tif", "tiff", "bmp"
    ]

    static let contentTypes: [UTType] = [
        .jpeg, .png, .heic, .heif, .webP, .gif, .tiff, .bmp
    ]

    static func isSupported(url: URL) -> Bool {
        pathExtensions.contains(url.pathExtension.lowercased())
    }
}

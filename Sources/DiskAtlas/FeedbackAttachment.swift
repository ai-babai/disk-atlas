import AtlasCore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct FeedbackAttachment: Sendable {
    let data: Data
    let width: Int
    let height: Int

    static func load(_ url: URL) throws -> Self {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= 10_000_000 else {
            throw AttachmentError.invalid
        }
        let bytes = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard bytes.count <= 10_000_000, let source = CGImageSourceCreateWithData(bytes as CFData, nil),
            let type = CGImageSourceGetType(source) as String?,
            [UTType.png.identifier, UTType.jpeg.identifier].contains(type), acceptableDimensions(source),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1600,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary)
        else { throw AttachmentError.invalid }
        try Task.checkCancellation()
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw AttachmentError.invalid }
        // Re-encode pixels only: no source EXIF, file name or original metadata.
        guard let pixels = sRGBPixels(image) else { throw AttachmentError.invalid }
        CGImageDestinationAddImage(
            destination, pixels, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= 2_000_000 else { throw AttachmentError.invalid }
        try Task.checkCancellation()
        return Self(data: output as Data, width: image.width, height: image.height)
    }
    private static func acceptableDimensions(_ source: CGImageSource) -> Bool {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0,
            width <= 40_000_000 / height
        else { return false }
        return true
    }
    private static func sRGBPixels(_ image: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.draw(image, in: bounds)
        return context.makeImage()
    }

}

enum AttachmentError: LocalizedError {
    case invalid
    var errorDescription: String? {
        L10n.text("Выбери PNG или JPEG до 10 МБ. Изображение не удалось подготовить — текст сохранён.")
    }
}

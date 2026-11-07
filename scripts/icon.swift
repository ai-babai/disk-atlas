import AppKit

@main struct IconCommand {
    static func draw(_ pixels: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        NSColor(srgbRed: 0.94, green: 0.97, blue: 0.94, alpha: 1).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: p * 0.04, y: p * 0.04, width: p * 0.92, height: p * 0.92), xRadius: p * 0.21,
            yRadius: p * 0.21
        ).fill()
        let blocks: [(CGFloat, CGFloat, CGFloat, CGFloat, NSColor)] = [
            (0.20, 0.20, 0.30, 0.60, NSColor(srgbRed: 0.31, green: 0.50, blue: 0.38, alpha: 1)),
            (0.54, 0.48, 0.26, 0.32, NSColor(srgbRed: 0.44, green: 0.64, blue: 0.53, alpha: 1)),
            (0.54, 0.20, 0.26, 0.24, NSColor(srgbRed: 0.67, green: 0.78, blue: 0.68, alpha: 1)),
        ]
        for (x, y, w, h, color) in blocks {
            color.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: x * p, y: y * p, width: w * p, height: h * p), xRadius: p * 0.035,
                yRadius: p * 0.035
            ).fill()
        }
        image.unlockFocus()
        return image
    }

    static func png(_ image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
            let data = rep.representation(using: .png, properties: [:])
        else { throw NSError(domain: "Cannot encode icon", code: 1) }
        return data
    }

    static func generate(_ output: URL) throws {
        let iconset = output.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: iconset) }
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let suffix = scale == 2 ? "@2x" : ""
                let file = iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
                try png(draw(size * scale)).write(to: file)
            }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw NSError(domain: "iconutil failed", code: 1) }
    }

    static func main() {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(Data("Usage: icon OUTPUT_DIRECTORY\n".utf8))
            exit(2)
        }
        do { try generate(URL(fileURLWithPath: CommandLine.arguments[1])) } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}

import AppKit

let output = CommandLine.arguments[1]
let iconset = output + "/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        NSColor(srgbRed: 0.94, green: 0.97, blue: 0.94, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.04, y: p * 0.04, width: p * 0.92, height: p * 0.92), xRadius: p * 0.21, yRadius: p * 0.21).fill()
        let blocks: [(CGFloat, CGFloat, CGFloat, CGFloat, NSColor)] = [
            (0.20, 0.20, 0.30, 0.60, NSColor(srgbRed: 0.31, green: 0.50, blue: 0.38, alpha: 1)),
            (0.54, 0.48, 0.26, 0.32, NSColor(srgbRed: 0.44, green: 0.64, blue: 0.53, alpha: 1)),
            (0.54, 0.20, 0.26, 0.24, NSColor(srgbRed: 0.67, green: 0.78, blue: 0.68, alpha: 1))
        ]
        for (x, y, w, h, color) in blocks {
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: x * p, y: y * p, width: w * p, height: h * p), xRadius: p * 0.035, yRadius: p * 0.035).fill()
        }
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(iconset)/icon_\(size)x\(size)\(suffix).png"))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset, "-o", output + "/AppIcon.icns"]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(1) }
try FileManager.default.removeItem(atPath: iconset)

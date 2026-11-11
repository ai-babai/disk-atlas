import AtlasCore
import SwiftUI

/// Draw inside the exact rectangles used by the tile painter; never reconstruct their positions.
enum DuplicateMapHighlight {
    static func draw(_ rect: CGRect, copies: Int, radius: CGFloat, context: inout GraphicsContext) {
        guard copies > 0, rect.width > 3, rect.height > 3 else { return }
        context.fill(
            Path(roundedRect: rect, cornerRadius: radius), with: .color(Palette.duplicateHighlight.opacity(0.12)))
        let halo = rect.insetBy(dx: 1.5, dy: 1.5)
        context.stroke(
            Path(roundedRect: halo, cornerRadius: max(0, radius - 1.5)), with: .color(Palette.paper.opacity(0.8)),
            lineWidth: 3)
        let border = rect.insetBy(dx: 0.75, dy: 0.75)
        context.stroke(
            Path(roundedRect: border, cornerRadius: max(0, radius - 0.75)), with: .color(Palette.duplicateHighlight),
            lineWidth: 1.5)
        badge(rect, copies: copies, context: &context)
    }
    private static func badge(_ rect: CGRect, copies: Int, context: inout GraphicsContext) {
        guard copies > 1, rect.width >= 28, rect.height >= 22 else { return }
        let text = context.resolve(
            Text("×\(copies)").font(.system(size: 9, weight: .semibold)).foregroundColor(Palette.paper))
        let size = text.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
        let badge = CGRect(x: rect.maxX - size.width - 11, y: rect.minY + 4, width: size.width + 8, height: 15)
        context.fill(Path(roundedRect: badge, cornerRadius: 3), with: .color(Palette.duplicateHighlight))
        context.draw(text, at: CGPoint(x: badge.midX, y: badge.midY), anchor: .center)
    }
}

struct DuplicateTileHighlight: View {
    let copies: Int
    let radius: CGFloat
    var body: some View {
        Canvas { context, size in
            DuplicateMapHighlight.draw(
                CGRect(origin: .zero, size: size), copies: copies, radius: radius, context: &context)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

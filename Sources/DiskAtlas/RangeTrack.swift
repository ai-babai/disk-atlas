import SwiftUI
import AppKit
import AtlasCore

/// Native drawing/drag tracking stays local. Expensive consumers receive mouse-up only.
struct RangeTrack: NSViewRepresentable {
    var lower: Double
    var upper: Double
    var preview: (Double, Double) -> Void
    var commit: (Double, Double) -> Void
    @Environment(\.colorScheme) private var scheme
    func makeNSView(context: Context) -> RangeTrackView { RangeTrackView() }
    func updateNSView(_ view: RangeTrackView, context: Context) {
        view.preview = preview; view.commit = commit
        if !view.tracking { view.lower = lower; view.upper = upper }
        view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        view.needsDisplay = true
    }
}

final class RangeTrackView: NSView {
    var lower = 0.0, upper = 1.0
    var tracking = false
    var preview: ((Double, Double) -> Void)?
    var commit: ((Double, Double) -> Void)?
    private var activeUpper = false
    private var lastPreview = Date.distantPast
    private lazy var lowerAX = RangeThumbAccessibility(owner: self, upper: false)
    private lazy var upperAX = RangeThumbAccessibility(owner: self, upper: true)
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func accessibilityChildren() -> [Any]? { [lowerAX, upperAX] }
    private var trackWidth: CGFloat { max(1, bounds.width - 20) }
    override func draw(_ dirtyRect: NSRect) {
        let line = NSRect(x: 10, y: 12, width: trackWidth, height: 3)
        NSColor(Palette.line).setFill(); NSBezierPath(roundedRect: line, xRadius: 1.5, yRadius: 1.5).fill()
        NSColor(Palette.accent).setFill()
        NSBezierPath(roundedRect: NSRect(x: 10 + lower * trackWidth, y: 12, width: max(0, (upper - lower) * trackWidth), height: 3), xRadius: 1.5, yRadius: 1.5).fill()
        for (position, selected) in [(lower, !activeUpper), (upper, activeUpper)] {
            let rect = NSRect(x: 3 + position * trackWidth, y: 6, width: 14, height: 14)
            NSColor(Palette.paper).setFill(); NSBezierPath(ovalIn: rect).fill()
            NSColor(Palette.accent).setStroke(); let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)); circle.lineWidth = 2; circle.stroke()
            if selected && window?.firstResponder === self {
                NSColor(Palette.accent).withAlphaComponent(0.25).setStroke()
                let focus = NSBezierPath(ovalIn: rect.insetBy(dx: -3, dy: -3)); focus.lineWidth = 2; focus.stroke()
            }
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8), .foregroundColor: NSColor(Palette.sub)]
        for (position, text) in [(0.2,"KB"),(0.4,"MB"),(0.6,"GB"),(0.8,"TB")] {
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: NSPoint(x: 10 + position * trackWidth - size.width / 2, y: 27), withAttributes: attributes)
        }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = min(1, max(0, (convert(event.locationInWindow, from: nil).x - 10) / trackWidth))
        activeUpper = abs(p - upper) < abs(p - lower); tracking = true; update(p)
    }
    override func mouseDragged(with event: NSEvent) { update(min(1, max(0, (convert(event.locationInWindow, from: nil).x - 10) / trackWidth))) }
    override func mouseUp(with event: NSEvent) {
        update(min(1, max(0, (convert(event.locationInWindow, from: nil).x - 10) / trackWidth)))
        tracking = false; preview?(lower, upper); commit?(lower, upper)
        NSAccessibility.post(element: activeUpper ? upperAX : lowerAX, notification: .valueChanged)
    }
    private func update(_ value: Double) {
        if activeUpper { upper = max(lower, value) } else { lower = min(upper, value) }
        needsDisplay = true
        if Date().timeIntervalSince(lastPreview) > 1.0 / 60 { preview?(lower, upper); lastPreview = Date() }
    }
    func describe(upper handle: Bool) -> String {
        let p = handle ? upper : lower
        if handle && p >= 0.999 { return L10n.text("Без ограничения") }
        if !handle && p <= 0 { return L10n.text("Без минимума") }
        return byteString(p <= 0 ? 0 : Int64(pow(10, p * 15).rounded()))
    }
    func adjust(upper handle: Bool, amount: Double) {
        activeUpper = handle; update(min(1, max(0, (handle ? upper : lower) + amount)))
        preview?(lower, upper); commit?(lower, upper)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 123 || event.keyCode == 124 { adjust(upper: activeUpper, amount: event.keyCode == 124 ? 0.02 : -0.02) }
        else if event.keyCode == 49 { activeUpper.toggle(); needsDisplay = true }
        else { super.keyDown(with: event) }
    }
    func thumbFrame(upper handle: Bool) -> NSRect {
        let rect = NSRect(x: 3 + (handle ? upper : lower) * trackWidth, y: 6, width: 14, height: 14)
        return window?.convertToScreen(convert(rect, to: nil)) ?? rect
    }
}

private final class RangeThumbAccessibility: NSAccessibilityElement {
    weak var owner: RangeTrackView?
    let upper: Bool
    init(owner: RangeTrackView, upper: Bool) {
        self.owner = owner; self.upper = upper; super.init()
        setAccessibilityRole(.slider); setAccessibilityParent(owner); setAccessibilityEnabled(true)
    }
    override func accessibilityLabel() -> String? { L10n.text(upper ? "Максимальный размер" : "Минимальный размер") }
    override func accessibilityValue() -> Any? { NSNumber(value: upper ? owner?.upper ?? 1 : owner?.lower ?? 0) }
    override func accessibilityValueDescription() -> String? { owner?.describe(upper: upper) }
    override func setAccessibilityValue(_ value: Any?) { if let n = value as? NSNumber { owner?.adjust(upper: upper, amount: n.doubleValue - (upper ? owner?.upper ?? 1 : owner?.lower ?? 0)) } }
    override func accessibilityMinValue() -> Any? { NSNumber(value: 0) }
    override func accessibilityMaxValue() -> Any? { NSNumber(value: 1) }
    override func accessibilityFrame() -> NSRect { owner?.thumbFrame(upper: upper) ?? .zero }
    override func accessibilityPerformIncrement() -> Bool { owner?.adjust(upper: upper, amount: 0.02); return true }
    override func accessibilityPerformDecrement() -> Bool { owner?.adjust(upper: upper, amount: -0.02); return true }
}

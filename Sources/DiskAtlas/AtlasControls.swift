import SwiftUI

/// One surface for actions, active filters and mode choices, based on the inspector actions.
struct AtlasButtonStyle: ButtonStyle {
    var emphasized = false
    var grouped = false
    func makeBody(configuration: Configuration) -> some View {
        AtlasButtonSurface(configuration: configuration, emphasized: emphasized, grouped: grouped)
    }
}

private struct AtlasButtonSurface: View {
    let configuration: ButtonStyleConfiguration
    let emphasized: Bool
    let grouped: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.controlSize) private var size
    @State private var hovered = false
    private var fill: Color {
        guard enabled else { return grouped ? .clear : Palette.soft }
        if grouped { return configuration.isPressed || hovered ? Palette.line.opacity(0.2) : .clear }
        return emphasized || configuration.isPressed
            ? Palette.mark : hovered ? Palette.mark.opacity(0.65) : Palette.soft
    }
    private var border: Color {
        if grouped { return .clear }
        if focused && enabled { return Palette.accent }
        return emphasized && enabled ? Palette.accent.opacity(0.45) : Palette.line.opacity(enabled ? 0.6 : 0.4)
    }
    var body: some View {
        configuration.label.font(.system(size: 11)).foregroundStyle(
            enabled
                ? (grouped
                    ? (emphasized ? Palette.selectedText : Palette.sub) : (emphasized ? Palette.accent : Palette.ink))
                : Palette.sub.opacity(0.65)
        ).padding(.horizontal, 10).padding(.vertical, 4).frame(minHeight: grouped ? 28 : size == .large ? 32 : 28)
            .background(fill, in: RoundedRectangle(cornerRadius: 6)).overlay {
                RoundedRectangle(cornerRadius: 6).strokeBorder(
                    border, lineWidth: !grouped && focused && enabled ? 2 : 1)
            }.contentShape(RoundedRectangle(cornerRadius: 6)).onHover { hovered = $0 }
    }
}

/// Real buttons keep keyboard/VoiceOver actions; arrow keys move within the mutually exclusive group.
struct AtlasSegments<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let values: [Value]
    let label: (Value) -> String
    @FocusState private var focused: Bool
    @State private var pillFrame = CGRect.zero
    @State private var displayedSelection: Value?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 2) {
            ForEach(values, id: \.self) { value in
                Button {
                    selection = value
                    focused = true
                } label: {
                    Text(label(value)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                }.buttonStyle(AtlasButtonStyle(emphasized: selection == value, grouped: true)).anchorPreference(
                    key: AtlasSegmentBounds<Value>.self, value: .bounds
                ) { [value: $0] }.accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }.padding(2).backgroundPreferenceValue(AtlasSegmentBounds<Value>.self) { anchors in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8).fill(Palette.soft).overlay {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line.opacity(0.6))
                    }
                    RoundedRectangle(cornerRadius: 6).fill(Palette.mark).overlay {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(
                            focused ? Palette.accent : Palette.accent.opacity(0.6), lineWidth: focused ? 1.5 : 1)
                    }.frame(width: pillFrame.width, height: pillFrame.height).offset(
                        x: pillFrame.minX, y: pillFrame.minY
                    ).opacity(pillFrame.isEmpty ? 0 : 1)
                }.allowsHitTesting(false).onChange(of: anchors[selection].map { geometry[$0] } ?? .zero, initial: true)
                { _, rect in
                    guard !rect.isEmpty else { return }
                    let animate = !pillFrame.isEmpty && displayedSelection != selection && !reduceMotion
                    withAnimation(animate ? .easeInOut(duration: 0.24) : nil) { pillFrame = rect }
                    displayedSelection = selection
                }
            }
        }.fixedSize().focusable().focusEffectDisabled().focused($focused).accessibilityElement(children: .contain)
            .accessibilityLabel(title).onKeyPress(.space) { return .handled }.onKeyPress(.leftArrow) {
                move(-1)
                return .handled
            }.onKeyPress(.rightArrow) {
                move(1)
                return .handled
            }
    }
    private func move(_ offset: Int) {
        guard let index = values.firstIndex(of: selection), values.indices.contains(index + offset) else { return }
        selection = values[index + offset]
        focused = true
    }
}

/// Measure all segments once; the single persistent pill moves between their actual bounds.
private struct AtlasSegmentBounds<Value: Hashable>: PreferenceKey {
    static var defaultValue: [Value: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [Value: Anchor<CGRect>], nextValue: () -> [Value: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

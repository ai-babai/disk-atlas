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
        if grouped { return configuration.isPressed ? Palette.mark : hovered ? Palette.mark.opacity(0.4) : .clear }
        return emphasized || configuration.isPressed
            ? Palette.mark : hovered ? Palette.mark.opacity(0.65) : Palette.soft
    }
    private var border: Color {
        if focused && enabled { return Palette.accent }
        if grouped { return .clear }
        return emphasized && enabled ? Palette.accent.opacity(0.45) : Palette.line.opacity(enabled ? 0.6 : 0.4)
    }
    var body: some View {
        configuration.label.font(.system(size: 11)).foregroundStyle(
            enabled ? (emphasized ? Palette.accent : Palette.ink) : Palette.sub.opacity(0.65)
        ).padding(.horizontal, 10).padding(.vertical, 4).frame(minHeight: grouped ? 24 : size == .large ? 32 : 28)
            .background(fill, in: RoundedRectangle(cornerRadius: 6)).overlay {
                RoundedRectangle(cornerRadius: 6).strokeBorder(border, lineWidth: focused && enabled ? 2 : 1)
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
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 2) {
            ForEach(values, id: \.self) { value in
                Button {
                    selection = value
                    focused = true
                } label: {
                    Text(label(value)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                }.buttonStyle(AtlasButtonStyle(emphasized: selection == value, grouped: true)).background {
                    if selection == value {
                        RoundedRectangle(cornerRadius: 6).fill(Palette.mark).overlay {
                            RoundedRectangle(cornerRadius: 6).strokeBorder(
                                focused ? Palette.accent : Palette.accent.opacity(0.45), lineWidth: focused ? 2 : 1)
                        }.matchedGeometryEffect(id: "selection", in: highlight)
                    }
                }.accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }.padding(2).background(Palette.soft, in: RoundedRectangle(cornerRadius: 8)).overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line.opacity(0.6))
        }.fixedSize().animation(reduceMotion ? nil : .easeInOut(duration: Motion.quick), value: selection).focusable()
            .focusEffectDisabled().focused($focused).accessibilityElement(children: .contain).accessibilityLabel(title)
            .onKeyPress(.space) { return .handled }.onKeyPress(.leftArrow) {
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

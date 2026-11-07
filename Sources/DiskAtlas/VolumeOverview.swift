import AtlasCore
import SwiftUI

struct VolumeOverview: View {
    let volume: VolumeCapacity
    private var summary: String {
        L10n.text("Свободно") + " " + byteString(volume.available) + L10n.text(" из ") + byteString(volume.total)
    }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "internaldrive").font(.system(size: 21, weight: .light)).foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(volume.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 12)
                    Text(summary).font(.system(size: 11)).foregroundStyle(Palette.sub).monospacedDigit().lineLimit(1)
                }
                GeometryReader { geometry in
                    Capsule().fill(Palette.line).overlay(alignment: .leading) {
                        Capsule().fill(Palette.accent).frame(
                            width: geometry.size.width
                                * max(0, 1 - Double(volume.available) / Double(max(1, volume.total))))
                    }
                }.frame(height: 3).accessibilityHidden(true)
            }
        }.frame(maxWidth: 620, alignment: .leading).accessibilityElement(children: .combine)
    }
}

struct SizeModeControl: View {
    @Binding var logical: Bool
    var body: some View {
        HStack(spacing: 4) {
            Picker(L10n.text("Как считается размер"), selection: $logical) {
                Text(L10n.text("На диске")).tag(false)
                Text(L10n.text("Размер файлов")).tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 210)
            SizeInfo()
        }
    }
}

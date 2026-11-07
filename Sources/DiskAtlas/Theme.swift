import SwiftUI
import AtlasCore

enum Palette {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((rgb >> 16) & 255) / 255,
                           green: Double((rgb >> 8) & 255) / 255,
                           blue: Double(rgb & 255) / 255, alpha: 1)
        })
    }
    static let paper = adaptive(0xffffff, 0x17201b)
    static let soft = adaptive(0xf3f6f3, 0x202d25)
    static let ink = adaptive(0x223329, 0xe8efe9)
    static let sub = adaptive(0x58695d, 0xadbfaf)
    static let line = adaptive(0xdce4de, 0x3a4d40)
    static let accent = adaptive(0x4e7f60, 0x9ec4a8)
    static let mark = adaptive(0xdcebe0, 0x2e4b37)
}

extension FileKind {
    var tint: Color {
        switch self {
        case .folder: return Palette.accent
        case .video: return Palette.adaptive(0x738bba, 0x738bba)
        case .audio: return Palette.adaptive(0xab82a7, 0xab82a7)
        case .image: return Palette.adaptive(0xc19167, 0xc19167)
        case .document: return Palette.adaptive(0x749b86, 0x749b86)
        case .archive: return Palette.adaptive(0xb99e59, 0xb99e59)
        case .code: return Palette.adaptive(0x639e9d, 0x639e9d)
        case .other: return Palette.adaptive(0x8d9691, 0x8d9691)
        case .link: return Palette.adaptive(0x9c919e, 0x9c919e)
        }
    }
    var symbol: String {
        switch self {
        case .folder: return "folder"
        case .video: return "film"
        case .audio: return "waveform"
        case .image: return "photo"
        case .document: return "doc.text"
        case .archive: return "archivebox"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .other: return "doc"
        case .link: return "link"
        }
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(Palette.sub)
    }
}

struct AtlasMark: View {
    var body: some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 3).fill(Palette.accent).frame(width: 13)
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 3).fill(Palette.accent.opacity(0.7))
                RoundedRectangle(cornerRadius: 3).fill(Palette.accent.opacity(0.4))
            }.frame(width: 12)
        }.frame(width: 28, height: 28).accessibilityHidden(true)
    }
}

struct LanguagePicker: View {
    @ObservedObject var store: AtlasStore
    var body: some View {
        Menu {
            Picker("Language / Язык", selection: $store.language) {
                Text("Русский").tag("ru")
                Text("English").tag("en")
            }.pickerStyle(.inline)
        } label: {
            Text(store.language.uppercased()).font(.system(size: 11, weight: .medium))
        }.fixedSize().help("Language / Язык")
            .accessibilityLabel("Language / Язык")
    }
}

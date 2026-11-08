import AtlasCore
import SwiftUI

enum Palette {
    static func adaptive(_ light: UInt32, _ dark: UInt32, contrastLight: UInt32? = nil, contrastDark: UInt32? = nil)
        -> Color
    {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [
                    .accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua, .darkAqua, .aqua,
                ])
                let rgb: UInt32
                switch match {
                case .accessibilityHighContrastAqua: rgb = contrastLight ?? light
                case .accessibilityHighContrastDarkAqua: rgb = contrastDark ?? dark
                case .darkAqua: rgb = dark
                default: rgb = light
                }
                return NSColor(
                    srgbRed: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255,
                    blue: Double(rgb & 255) / 255, alpha: 1)
            })
    }
    static let paper = adaptive(0xffffff, 0x17201b)
    static let soft = adaptive(0xf3f6f3, 0x202d25)
    static let ink = adaptive(0x223329, 0xe8efe9)
    static let sub = adaptive(0x58695d, 0xadbfaf, contrastLight: 0x314d3b, contrastDark: 0xd0e0d3)
    static let line = adaptive(0xdce4de, 0x3a4d40, contrastLight: 0x708478, contrastDark: 0x91ac99)
    static let accent = adaptive(0x426f52, 0x9ec4a8)
    static let selectedText = adaptive(0x315b40, 0xd6eddb)
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
            .lineLimit(1).minimumScaleFactor(0.75)
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
        }.fixedSize().help("Language / Язык").accessibilityLabel("Language / Язык")
    }
}

/// Shared timing for small, interruptible UI changes.
enum Motion { static let quick = 0.16 }

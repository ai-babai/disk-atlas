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
    static let duplicateHighlight = adaptive(0x18796c, 0x7de0c3, contrastLight: 0x0c5d52, contrastDark: 0xb1f3d9)
    static let destructive = adaptive(0xb3261e, 0xff9a91, contrastLight: 0x8f1812, contrastDark: 0xffc2bb)
    static let destructiveFill = adaptive(0xfce9e7, 0x452524)
    static let selectedText = adaptive(0x315b40, 0xd6eddb)
    static let mark = adaptive(0xdcebe0, 0x2e4b37)
}

/// Opaque map colors: a file's category never changes with its containing folder.
/// Tableau 10 hues, lightened 45% for light mode and another 8% for dark mode.
enum MapPalette {
    static let fileText = Palette.adaptive(0x223329, 0x223329)
    static let folderLine = Palette.adaptive(0xd6dde2, 0x4a555b, contrastLight: 0x657780, contrastDark: 0xb8c8ce)
    static func folder(depth: Int = 0) -> Color {
        switch depth {
        case 0: return Palette.adaptive(0xf1f4f5, 0x242e32)
        case 1: return Palette.adaptive(0xe8edf0, 0x2a353b)
        default: return Palette.adaptive(0xe1e7eb, 0x303d43)
        }
    }
    static func fill(_ kind: FileKind) -> Color {
        switch kind {
        case .folder: return folder()
        case .video: return Palette.adaptive(0x9eb5cf, 0xa6bbd3)
        case .image: return Palette.adaptive(0xf8c18b, 0xf9c694)
        case .audio: return Palette.adaptive(0xd3b6cb, 0xd7bccf)
        case .document: return Palette.adaptive(0xa4cb9e, 0xabcfa6)
        case .archive: return Palette.adaptive(0xf5e19b, 0xf6e3a3)
        case .code: return Palette.adaptive(0xb4d7d5, 0xbadad8)
        case .other, .link: return Palette.adaptive(0xd9d4d1, 0xdcd7d5)
        }
    }
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
            Text(store.language.uppercased()).font(.system(size: 12)).foregroundStyle(Palette.sub)
        }.fixedSize().help("Language / Язык").accessibilityLabel("Language / Язык")
    }
}

struct AppearancePicker: View {
    @ObservedObject var store: AtlasStore
    var body: some View {
        Menu {
            Picker(L10n.text("Оформление"), selection: $store.appearance) {
                Text(L10n.text("Как в системе")).tag("system")
                Text(L10n.text("Светлая")).tag("light")
                Text(L10n.text("Тёмная")).tag("dark")
            }.pickerStyle(.inline)
        } label: {
            Image(systemName: "circle.lefthalf.filled").font(.system(size: 12))
        }.menuIndicator(.hidden).fixedSize().help(L10n.text("Оформление")).accessibilityLabel(
            L10n.text("Оформление приложения"))
    }
}

/// Shared timing for small, interruptible UI changes.
enum Motion { static let quick = 0.16 }

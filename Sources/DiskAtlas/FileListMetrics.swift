import AppKit
import AtlasCore
import SwiftUI

/// Shared native-list proportions; duplicate paths can grow beyond the two-line minimum.
enum FileListMetrics {
    static let rowHeight: CGFloat = 33
    static let pathRowHeight: CGFloat = 43
    static let headerHeight: CGFloat = 28
    static let checkWidth: CGFloat = 44
    static let dateWidth: CGFloat = 92
    static let sizeWidth: CGFloat = 100
    static let iconWidth: CGFloat = 16
    static let iconTextSpacing: CGFloat = 9
    static let nameFontSize: CGFloat = 12
    static let dateFontSize: CGFloat = 10
    @MainActor static var nameFont: NSFont { .systemFont(ofSize: nameFontSize, weight: .medium) }
    @MainActor static var secondaryFont: NSFont { .systemFont(ofSize: dateFontSize) }
    @MainActor static var dateFont: NSFont { .monospacedDigitSystemFont(ofSize: dateFontSize, weight: .regular) }
    @MainActor static var sizeFont: NSFont { .monospacedDigitSystemFont(ofSize: 11, weight: .regular) }
    @MainActor static var headerFont: NSFont { .systemFont(ofSize: dateFontSize, weight: .medium) }
}

/// Fit even wide symbols (such as code) inside the same bounds as AppKit's file icons.
struct FileTypeIcon: View {
    let kind: FileKind
    var body: some View {
        Image(systemName: kind.symbol).resizable().scaledToFit().frame(
            width: FileListMetrics.iconWidth, height: FileListMetrics.iconWidth
        ).foregroundStyle(kind.tint).accessibilityHidden(true)
    }
}

struct DuplicateTableColumns {
    var created = true
    var modified = true
    static let nameWidth: CGFloat = 180
    static let copiesWidth: CGFloat = 52
    static let actionsWidth: CGFloat = 88
    var minimumWidth: CGFloat {
        FileListMetrics.checkWidth + Self.nameWidth + Self.copiesWidth + FileListMetrics.sizeWidth + Self.actionsWidth
            + 16 + (created ? FileListMetrics.dateWidth : 0) + (modified ? FileListMetrics.dateWidth : 0)
    }
    @MainActor func date(_ value: Date?) -> some View {
        Text(
            value.map {
                $0.formatted(
                    Date.FormatStyle(
                        date: .numeric, time: .omitted,
                        locale: Locale(identifier: L10n.language == "en" ? "en_US" : "ru_RU")))
            } ?? "—"
        ).font(Font(FileListMetrics.dateFont)).foregroundStyle(Palette.sub).padding(.top, 5).padding(.horizontal, 6)
            .frame(width: FileListMetrics.dateWidth, alignment: .leading)
    }
}

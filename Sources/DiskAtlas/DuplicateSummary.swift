import AtlasCore
import SwiftUI

struct DuplicateSummary: View {
    enum Style { case metric, detail, inline }
    let entry: Entry
    let store: AtlasStore
    @ObservedObject var session: DuplicateSession
    var style: Style = .metric
    private var count: Int {
        guard session.snapshotCreated == store.snapshot?.created, let lookup = session.lookup else { return 0 }
        if store.isVirtual(entry) { return lookup.byPath.count }
        if entry.isDirectory { return lookup.count(in: entry.path, directory: true) }
        guard let groupID = lookup.byPath[entry.path], let group = lookup.groups[groupID] else { return 0 }
        return max(0, group.files.count - 1)
    }
    var body: some View {
        if count > 0 {
            Button {
                store.openDuplicateScope(entry)
            } label: {
                label.contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(Palette.accent).help(
                L10n.text("Файлы с подтверждёнными копиями, включая вложенные папки")
            ).accessibilityLabel(
                L10n.text(entry.isDirectory ? "Файлов с копиями: " : "Других копий: ") + count.formatted())
        }
    }
    @ViewBuilder private var label: some View {
        switch style {
        case .metric:
            VStack(alignment: .leading, spacing: 6) {
                Text(count.formatted()).font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit()
                Label(L10n.text("Файлы с копиями"), systemImage: "chevron.right").font(.system(size: 10)).lineLimit(2)
            }.frame(maxWidth: 130, alignment: .leading)
        case .detail:
            HStack {
                Text(L10n.text(entry.isDirectory ? "Дубликаты внутри" : "Дубликаты"))
                Spacer()
                Text(count.formatted()).monospacedDigit()
                Image(systemName: "chevron.right").font(.system(size: 8))
            }.font(.system(size: 10))
        case .inline:
            Label(L10n.text("Файлов с копиями: ") + count.formatted(), systemImage: "doc.on.doc").font(
                .system(size: 11))
        }
    }
}

struct SizeInfo: View {
    @State private var open = false
    private var explanation: String {
        L10n.text(
            "На диске — выделенные файлу блоки. Размер файлов — длина содержимого. Сжатие и разреженные файлы уменьшают место на диске; APFS-копии могут разделять блоки."
        )
    }
    var body: some View {
        Button {
            open.toggle()
        } label: {
            Image(systemName: "info.circle").font(.system(size: 11)).frame(width: 20, height: 28)
        }.buttonStyle(.plain).foregroundStyle(Palette.sub).help(explanation).accessibilityLabel(
            L10n.text("Как считается размер")
        ).popover(isPresented: $open) {
            Text(explanation).font(.system(size: 12)).padding(16).frame(width: 290).foregroundStyle(Palette.ink)
                .background(Palette.paper)
        }
    }
}

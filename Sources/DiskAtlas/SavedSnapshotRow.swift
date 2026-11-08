import AtlasCore
import SwiftUI

enum SnapshotColumns {
    static let gap: CGFloat = 12
    static let snapshot: CGFloat = 84
    static let report: CGFloat = 120
    static let open: CGFloat = 60
    static let trash: CGFloat = 24
}

struct SavedSnapshotRow: View {
    @ObservedObject var store: AtlasStore
    let record: ScanHistoryRecord
    let selected: Bool
    let select: () -> Void
    let open: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var openDisabled: Bool {
        store.scanning || store.preparing || store.deletingHistory || store.fileTrash.busy
    }
    var body: some View {
        HStack(spacing: SnapshotColumns.gap) {
            Button(action: select) {
                HStack(spacing: SnapshotColumns.gap) {
                    identity
                    size(record.archiveBytes).frame(width: SnapshotColumns.snapshot, alignment: .trailing)
                    size(record.duplicateBytes).frame(width: SnapshotColumns.report, alignment: .trailing)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help(record.roots.joined(separator: "\n")).accessibilityLabel(
                store.historyTitle(record)
            ).accessibilityValue(accessibleDetails).accessibilityAddTraits(selected ? [.isSelected] : [])
            Button(action: open) {
                Text(L10n.text("Открыть")).font(.system(size: 11, weight: .medium)).frame(
                    width: SnapshotColumns.open, height: 26
                ).background(Palette.soft, in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain).foregroundStyle(Palette.accent).disabled(openDisabled).accessibilityLabel(
                L10n.text("Открыть снимок") + " " + store.historyTitle(record))
            SnapshotDeleteButton(store: store, record: record).frame(width: SnapshotColumns.trash)
        }.padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 56).foregroundStyle(
            selected ? Palette.selectedText : Palette.ink
        ).background(selected ? Palette.mark : hovered ? Palette.soft : .clear, in: RoundedRectangle(cornerRadius: 6))
            .onHover { hovered = $0 }.animation(reduceMotion ? nil : .easeOut(duration: Motion.quick), value: hovered)
    }
    private var accessibleDetails: String {
        let snapshot = record.archiveBytes.map(byteString) ?? L10n.text("Не сохранён")
        let report = record.duplicateBytes.map(byteString) ?? L10n.text("Не сохранён")
        return [
            L10n.historyDate(record.created), L10n.text("Вес снимка") + ": " + snapshot,
            L10n.text("Отчёт о дубликатах") + ": " + report,
        ].joined(separator: ", ")
    }
    private var identity: some View {
        HStack(spacing: 8) {
            Group {
                if store.loadingHistoryID == record.id {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: record.cancelled ? "clock.badge.exclamationmark" : "archivebox").font(
                        .system(size: 15))
                }
            }.frame(width: 20).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.historyTitle(record)).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(
                    .middle)
                Text(L10n.historyDate(record.created)).font(.system(size: 10)).foregroundStyle(Palette.sub).lineLimit(1)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func size(_ bytes: Int64?) -> some View {
        Text(bytes.map(byteString) ?? "—").font(.system(size: 12)).monospacedDigit().foregroundStyle(Palette.sub).help(
            bytes == nil ? L10n.text("Не сохранён") : "")
    }
}

struct SnapshotDeleteButton: View {
    @ObservedObject var store: AtlasStore
    let record: ScanHistoryRecord
    var body: some View {
        Button(role: .destructive) {
            store.requestHistoryDeletion(record)
        } label: {
            Image(systemName: "trash").font(.system(size: 11)).frame(width: 24, height: 24).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(Palette.sub).disabled(store.historyBusy).help(
            L10n.text("Удалить сохранённый снимок и его отчёт. Исходные файлы останутся на месте.")
        ).accessibilityLabel(L10n.text("Удалить снимок") + " " + store.historyTitle(record))
    }
}

import AtlasCore
import SwiftUI

/// Recent snapshots are navigation. Storage sizes and deletion live in the manager window.
struct HistoryRow: View {
    @ObservedObject var store: AtlasStore
    let record: ScanHistoryRecord
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var highlighted: Bool { store.activeHistoryID == record.id || store.loadingHistoryID == record.id }
    var body: some View {
        Button {
            store.openHistory(record)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                if store.loadingHistoryID == record.id {
                    ProgressView().controlSize(.mini).frame(width: 14, height: 16)
                } else {
                    Image(systemName: record.cancelled ? "clock.badge.exclamationmark" : "clock").frame(
                        width: 14, height: 16)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.historyTitle(record)).font(.system(size: 12, weight: highlighted ? .semibold : .medium))
                        .lineLimit(1).truncationMode(.middle)
                    Text(L10n.historyDate(record.created)).font(.system(size: 10)).foregroundStyle(Palette.sub)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(store.scanning || store.preparing || store.deletingHistory).padding(8)
            .background(highlighted ? Palette.mark : .clear, in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(
                highlighted ? Palette.selectedText : Palette.ink
            ).animation(reduceMotion ? nil : .easeInOut(duration: Motion.quick), value: highlighted).help(
                record.roots.joined(separator: "\n") + "\n" + L10n.date(record.created))
    }
}

struct HistoryWindow: View {
    @ObservedObject var store: AtlasStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("Сохранённые снимки")).font(.title2.weight(.semibold))
                Text(
                    L10n.text(
                        "Открывай готовые результаты без нового анализа. Здесь показан вес сохранённых данных, а не размер исходных папок."
                    )
                ).font(.callout).foregroundStyle(Palette.sub).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                storageMetric("Всего в истории", bytes: store.historyStorageBytes)
                storageMetric("Снимки", bytes: store.historyRecords.reduce(0) { $0 + ($1.archiveBytes ?? 0) })
                storageMetric(
                    "Отчёты о дубликатах", bytes: store.historyRecords.reduce(0) { $0 + ($1.duplicateBytes ?? 0) })
            }
            Table(store.historyRecords) {
                TableColumn(L10n.text("Название")) { record in
                    Button {
                        store.openHistory(record)
                        openWindow(id: "main")
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.historyTitle(record)).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                            Text(L10n.historyDate(record.created)).font(.caption).foregroundStyle(Palette.sub)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5).contentShape(
                            Rectangle())
                    }.buttonStyle(.plain).help(record.roots.joined(separator: "\n")).disabled(
                        store.scanning || store.preparing || store.deletingHistory)
                }.width(min: 180, ideal: 260)
                TableColumn(L10n.text("Снимок")) { record in sizeLabel(record.archiveBytes) }.width(90)
                TableColumn(L10n.text("Отчёт о дубликатах")) { record in sizeLabel(record.duplicateBytes) }.width(140)
                TableColumn("") { record in
                    Button(role: .destructive) {
                        store.requestHistoryDeletion(record)
                    } label: {
                        Image(systemName: "trash")
                    }.buttonStyle(.borderless).disabled(store.historyBusy).help(L10n.text("Удалить снимок…"))
                        .accessibilityLabel(L10n.text("Удалить снимок") + " " + store.historyTitle(record))
                }.width(32)
            }.overlay {
                if store.historyRecords.isEmpty {
                    ContentUnavailableView(L10n.text("История пуста"), systemImage: "clock")
                }
            }
            HStack {
                Button(L10n.text("Очистить историю…"), role: .destructive) { store.requestHistoryDeletion() }.disabled(
                    store.historyBusy || (store.historyRecords.isEmpty && store.historyStorageBytes == 0))
                if store.deletingHistory { ProgressView().controlSize(.small) }
                Spacer()
                Toggle(
                    L10n.text("Подтверждать удаление"),
                    isOn: Binding(
                        get: { !store.skipHistoryDeleteConfirmation },
                        set: { store.skipHistoryDeleteConfirmation = !$0 })
                ).toggleStyle(.checkbox).disabled(store.deletingHistory)
            }.controlSize(.small)
        }.padding(24).frame(minWidth: 700, minHeight: 430).background(Palette.paper).foregroundStyle(Palette.ink)
    }
    private func storageMetric(_ title: String, bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(byteString(bytes)).font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit()
            Text(L10n.text(title)).font(.caption).foregroundStyle(Palette.sub)
        }
    }
    private func sizeLabel(_ bytes: Int64?) -> some View {
        Text(bytes.map(byteString) ?? "—").monospacedDigit().foregroundStyle(Palette.sub).help(
            bytes == nil ? L10n.text("Не сохранён") : "")
    }
}

struct RecentScans: View {
    @ObservedObject var store: AtlasStore
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(text: L10n.text("Последние снимки")).padding(.horizontal, 8).padding(.bottom, 3)
            ForEach(store.historyRecords.prefix(4)) { HistoryRow(store: store, record: $0) }
            Button(L10n.text("Сохранённые снимки…")) { store.showHistory = true }.font(.system(size: 11)).buttonStyle(
                .plain
            ).foregroundStyle(Palette.accent).padding(8)
        }.padding(12).background(Palette.soft, in: RoundedRectangle(cornerRadius: 10))
    }
}

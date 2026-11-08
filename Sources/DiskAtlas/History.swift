import AtlasCore
import SwiftUI

struct HistoryRow: View {
    @ObservedObject var store: AtlasStore
    let record: ScanHistoryRecord
    var showsStorageControls = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var highlighted: Bool { store.activeHistoryID == record.id || store.loadingHistoryID == record.id }
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Button {
                store.openHistory(record)
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    statusIcon.frame(width: 14, height: 16)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.historyTitle(record)).font(
                            .system(size: 12, weight: highlighted ? .semibold : .medium)
                        ).lineLimit(1).truncationMode(.middle)
                        metadata
                    }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(
                store.scanning || store.preparing || store.deletingHistory || store.fileTrash.busy)
            if showsStorageControls { SnapshotDeleteButton(store: store, record: record) }
        }.padding(8).background(highlighted ? Palette.mark : .clear, in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(highlighted ? Palette.selectedText : Palette.ink).animation(
                reduceMotion ? nil : .easeInOut(duration: Motion.quick), value: highlighted
            ).help(record.roots.joined(separator: "\n") + "\n" + L10n.date(record.created))
    }
    @ViewBuilder private var statusIcon: some View {
        if store.loadingHistoryID == record.id {
            ProgressView().controlSize(.mini)
        } else {
            Image(systemName: record.cancelled ? "clock.badge.exclamationmark" : "clock")
        }
    }
    private var metadata: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                date
                if showsStorageControls {
                    Text("·")
                    storage
                }
            }.fixedSize()
            VStack(alignment: .leading, spacing: 2) {
                date
                if showsStorageControls { storage }
            }
        }.font(.system(size: 10)).foregroundStyle(Palette.sub)
    }
    private var date: some View { Text(L10n.historyDate(record.created)).lineLimit(1) }
    private var storage: some View {
        Text(record.archiveBytes.map { L10n.text("Снимок") + " " + byteString($0) } ?? "—").monospacedDigit()
            .fixedSize().help(L10n.text("Вес сжатого снимка. Отчёт о дубликатах хранится отдельно."))
    }
}

struct HistoryWindow: View {
    @ObservedObject var store: AtlasStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("Сохранённые снимки")).font(.system(size: 26, weight: .semibold, design: .rounded))
                Text(L10n.text("Открывай снимки без повторного сканирования. Здесь указан вес сохранённых данных."))
                    .font(.system(size: 12)).foregroundStyle(Palette.sub).fixedSize(horizontal: false, vertical: true)
            }
            storageSummary
            snapshotList
            footer
        }.padding(24).frame(minWidth: 700, minHeight: 430).background(Palette.paper).foregroundStyle(Palette.ink)
    }
    private var storageSummary: some View {
        HStack(spacing: 12) {
            storageMetric("Всего в истории", symbol: "internaldrive", bytes: store.historyStorageBytes)
            storageMetric(
                "Снимки", symbol: "archivebox", bytes: store.historyRecords.reduce(0) { $0 + ($1.archiveBytes ?? 0) })
            storageMetric(
                "Отчёты о дубликатах", symbol: "doc.on.doc",
                bytes: store.historyRecords.reduce(0) { $0 + ($1.duplicateBytes ?? 0) })
        }
    }
    private var snapshotList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(store.historyRecords) { record in
                        SavedSnapshotRow(store: store, record: record) {
                            store.openHistory(record)
                            openWindow(id: "main")
                        }
                        Divider().overlay(Palette.line).padding(.horizontal, 12)
                    }
                } header: {
                    columnsHeader.background(Palette.paper)
                }
            }.padding(4)
        }.overlay {
            if store.historyRecords.isEmpty { ContentUnavailableView(L10n.text("История пуста"), systemImage: "clock") }
        }.background(Palette.paper).clipShape(RoundedRectangle(cornerRadius: 10)).overlay(
            RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line))
    }
    private var columnsHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: SnapshotColumns.gap) {
                Text(L10n.text("Название")).padding(.leading, 28).frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.text("Вес снимка")).frame(width: SnapshotColumns.snapshot, alignment: .trailing)
                Text(L10n.text("Отчёт о дубликатах")).frame(width: SnapshotColumns.report, alignment: .trailing)
                Color.clear.frame(width: SnapshotColumns.open)
                Color.clear.frame(width: SnapshotColumns.trash)
            }.font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.sub).padding(.horizontal, 12).frame(
                height: 32)
            Divider().overlay(Palette.line)
        }
    }
    private var footer: some View {
        HStack {
            Button(role: .destructive) {
                store.requestHistoryDeletion()
            } label: {
                Label(L10n.text("Очистить историю…"), systemImage: "trash")
            }.disabled(store.historyBusy || (store.historyRecords.isEmpty && store.historyStorageBytes == 0))
            if store.deletingHistory { ProgressView().controlSize(.small) }
            Spacer()
            Toggle(
                L10n.text("Подтверждать удаление"),
                isOn: Binding(
                    get: { !store.skipHistoryDeleteConfirmation }, set: { store.skipHistoryDeleteConfirmation = !$0 })
            ).toggleStyle(.checkbox).disabled(store.deletingHistory)
        }.font(.system(size: 11)).controlSize(.small)
    }
    private func storageMetric(_ title: String, symbol: String, bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.text(title), systemImage: symbol).font(.system(size: 10, weight: .medium)).foregroundStyle(
                Palette.sub)
            Text(byteString(bytes)).font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit()
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(
            Palette.soft, in: RoundedRectangle(cornerRadius: 10))
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

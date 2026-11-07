import SwiftUI
import AtlasCore

struct HistoryRow: View {
    @ObservedObject var store: AtlasStore
    let record: ScanHistoryRecord
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var highlighted: Bool { store.activeHistoryID == record.id || store.loadingHistoryID == record.id }
    private var helpText: String {
        let size = record.archiveBytes.map(byteString) ?? "—"
        return record.roots.joined(separator: "\n") + "\n" + L10n.date(record.created) + "\n" + L10n.text("Снимок") + ": " + size
    }
    var body: some View {
        HStack(spacing: 4) { openButton; deleteButton }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlighted ? Palette.mark : .clear, in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(highlighted ? Palette.accent : Palette.ink)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: highlighted)
            .contextMenu {
                Button(L10n.text("Удалить снимок…"), role: .destructive) { store.requestHistoryDeletion(record) }.disabled(store.historyBusy)
            }
    }
    private var openButton: some View {
        Button { store.openHistory(record) } label: {
            HStack(spacing: 8) {
                statusIcon.frame(width: 14)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(store.historyTitle(record)).font(.system(size: 11, weight: highlighted ? .semibold : .medium)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        if let bytes = record.archiveBytes {
                            Text(byteString(bytes)).font(.system(size: 9)).foregroundStyle(Palette.sub).fixedSize()
                        }
                    }
                    Text(L10n.historyDate(record.created)).font(.system(size: 9)).foregroundStyle(Palette.sub).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(store.scanning || store.preparing || store.deletingHistory).help(helpText)
    }
    @ViewBuilder private var statusIcon: some View {
        if store.loadingHistoryID == record.id { ProgressView().controlSize(.mini) }
        else { Image(systemName: record.cancelled ? "clock.badge.exclamationmark" : "clock").font(.system(size: 11)) }
    }
    private var deleteButton: some View {
        Button(role: .destructive) { store.requestHistoryDeletion(record) } label: {
            Image(systemName: "trash").font(.system(size: 10)).foregroundStyle(Palette.sub).frame(width: 18, height: 26)
        }.buttonStyle(.plain).disabled(store.historyBusy)
            .help(L10n.text("Удалить снимок…"))
            .accessibilityLabel(L10n.text("Удалить снимок") + " " + store.historyTitle(record) + " " + L10n.historyDate(record.created))
    }

}

struct HistorySheet: View {
    @ObservedObject var store: AtlasStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("История сканов")).font(.system(size: 23, weight: .semibold))
            Text(L10n.text("Сохранённые результаты. Открытие не запускает новый анализ."))
                .font(.system(size: 12)).foregroundStyle(Palette.sub)
            HStack {
                Text(L10n.text("Снимков: ") + "\(store.historyRecords.count)")
                Spacer()
                Text(L10n.text("На диске") + ": " + byteString(store.historyStorageBytes))
            }.font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.sub)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.historyRecords) { HistoryRow(store: store, record: $0) }
                    if store.historyRecords.isEmpty {
                        Text(L10n.text("История пуста")).font(.system(size: 13)).foregroundStyle(Palette.sub).padding(.top, 40)
                    }
                }
            }
            Toggle(L10n.text("Подтверждать удаление"), isOn: Binding(get: { !store.skipHistoryDeleteConfirmation }, set: { store.skipHistoryDeleteConfirmation = !$0 }))
                .font(.system(size: 11)).disabled(store.deletingHistory)
            HStack {
                Button(L10n.text("Очистить историю…"), role: .destructive) { store.requestHistoryDeletion() }
                    .disabled(store.historyBusy || (store.historyRecords.isEmpty && store.historyStorageBytes == 0))
                if store.deletingHistory { ProgressView().controlSize(.small) }
                Spacer()
                Button(L10n.text("Готово")) { store.showHistory = false }.keyboardShortcut(.defaultAction).disabled(store.deletingHistory)
            }
        }.padding(26).frame(width: 500, height: 500).background(Palette.paper).foregroundStyle(Palette.ink)
    }
}

struct RecentScans: View {
    @ObservedObject var store: AtlasStore
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionLabel(text: L10n.text("Последние сканы"))
                Spacer()
                Text(L10n.text("Снимок")).font(.system(size: 9)).foregroundStyle(Palette.sub)
            }.padding(.horizontal, 8).padding(.bottom, 3)
            ForEach(store.historyRecords.prefix(4)) { HistoryRow(store: store, record: $0) }
            Button(L10n.text("Вся история…")) { store.showHistory = true }
                .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Palette.accent).padding(8)
        }.padding(12).background(Palette.soft, in: RoundedRectangle(cornerRadius: 10))
    }
}

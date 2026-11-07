import SwiftUI
import AtlasCore

struct HistoryRow: View {
    @ObservedObject var store: AtlasStore
    let record: ScanHistoryRecord
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var highlighted: Bool { store.activeHistoryID == record.id || store.loadingHistoryID == record.id }
    var body: some View {
        Button { store.openHistory(record) } label: {
            HStack(spacing: 8) {
                Group {
                    if store.loadingHistoryID == record.id { ProgressView().controlSize(.mini) }
                    else { Image(systemName: record.cancelled ? "clock.badge.exclamationmark" : "clock").font(.system(size: 11)) }
                }.frame(width: 14)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(store.historyTitle(record)).font(.system(size: 11, weight: highlighted ? .semibold : .medium)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        Text(byteString(store.logical ? record.logicalBytes : record.bytes)).font(.system(size: 9)).foregroundStyle(Palette.sub).fixedSize()
                    }
                    Text(L10n.historyDate(record.created)).font(.system(size: 9)).foregroundStyle(Palette.sub).lineLimit(1)
                }
            }.padding(.horizontal, 8).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
                .background(highlighted ? Palette.mark : .clear, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(highlighted ? Palette.accent : Palette.ink)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: highlighted)
        }.buttonStyle(.plain).disabled(store.scanning || store.preparing)
            .help(record.roots.joined(separator: "\n") + "\n" + L10n.date(record.created))
    }
}

struct HistorySheet: View {
    @ObservedObject var store: AtlasStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("История сканов")).font(.system(size: 23, weight: .semibold))
            Text(L10n.text("Сохранённые результаты. Открытие не запускает новый анализ."))
                .font(.system(size: 12)).foregroundStyle(Palette.sub)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.historyRecords) { HistoryRow(store: store, record: $0) }
                }
            }
            HStack { Spacer(); Button(L10n.text("Готово")) { store.showHistory = false }.keyboardShortcut(.defaultAction) }
        }.padding(26).frame(width: 500, height: 500).background(Palette.paper).foregroundStyle(Palette.ink)
    }
}

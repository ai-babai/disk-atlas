import AtlasCore
import SwiftUI

/// This slot remains mounted at a fixed height, including with no checked items.
struct TrashSelectionBar: View {
    let count: Int
    let bytes: Int64?
    let sizeHelp: String
    let busy: Bool
    var notice: String? = nil
    let clear: () -> Void
    let review: () -> Void
    let stop: () -> Void
    var compact = false
    var body: some View {
        Group {
            ViewThatFits(in: .horizontal) {
                actions(labels: true)
                actions(labels: false)
            }
        }.font(.system(size: 11)).padding(.horizontal, compact ? 6 : 10).frame(height: compact ? 28 : 40).background(
            Palette.soft.opacity(count > 0 || busy ? 1 : 0), in: RoundedRectangle(cornerRadius: 6))
    }
    private func actions(labels: Bool) -> some View {
        HStack(spacing: compact ? 6 : 10) {
            selectionSummary(labels: labels)
            Button(action: clear) {
                if labels { Text(L10n.text("Снять выбор")) } else { Image(systemName: "xmark.circle") }
            }.buttonStyle(.plain).opacity(count > 0 ? 1 : 0).disabled(count == 0 || busy).accessibilityHidden(
                count == 0
            ).accessibilityLabel(L10n.text("Снять выбор"))
            if compact {
                Image(systemName: "info.circle").frame(width: 14).opacity(notice == nil ? 0 : 1).help(notice ?? "")
                    .accessibilityHidden(notice == nil)
            } else {
                Text(notice ?? "").foregroundStyle(Palette.sub).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
            }
            trashAction(labels: labels)
        }.fixedSize(horizontal: compact, vertical: false)
    }
    private func selectionSummary(labels: Bool) -> some View {
        let amount = bytes.map(byteString) ?? "…"
        return Text(count > 0 ? (labels ? L10n.text("Выбрано: ") : "") + count.formatted() + " · " + amount : "")
            .monospacedDigit().lineLimit(1).frame(width: labels ? 170 : 120, alignment: .leading).help(sizeHelp)
            .accessibilityLabel(L10n.text("Выбрано: ") + count.formatted() + " · " + amount + ". " + sizeHelp)
    }
    @ViewBuilder private func trashAction(labels: Bool) -> some View {
        if busy {
            ProgressView().controlSize(.mini)
            Button(L10n.text("Остановить"), action: stop)
        } else {
            Button(action: review) {
                if labels { Label(L10n.text("В корзину…"), systemImage: "trash") } else { Image(systemName: "trash") }
            }.disabled(count == 0).accessibilityLabel(L10n.text("В корзину…")).help(L10n.text("В корзину…"))
        }
    }

}

struct FileTrashControls: View {
    @ObservedObject var session: FileTrashSession
    let store: AtlasStore
    var compact = false
    @State private var total: Int64?
    @State private var calculated: SummaryRequest?
    private struct SummaryRequest: Hashable {
        let selected: Set<Int>
        let snapshot: Date?
        let logical: Bool
    }
    private var request: SummaryRequest {
        SummaryRequest(selected: session.selected, snapshot: store.snapshot?.created, logical: store.logical)
    }
    var body: some View {
        TrashSelectionBar(
            count: session.selected.count, bytes: calculated == request ? total : nil,
            sizeHelp: L10n.text(store.logical ? "Размер файлов" : "На диске") + ". "
                + L10n.text("По снимку. Папки учтены целиком, вложенные выбранные объекты не считаются повторно."),
            busy: session.busy, notice: session.message, clear: { session.selected = [] },
            review: { store.reviewFileTrash() }, stop: session.stop, compact: compact
        ).task(id: request) {
            let key = request
            guard let snapshot = store.snapshot else { return }
            let value = await Task.detached(priority: .utility) {
                FileTrashSelection.bytes(in: snapshot, selected: key.selected, logical: key.logical)
            }.value
            guard !Task.isCancelled else { return }
            total = value
            calculated = key
        }.sheet(item: $session.review) { plan in
            FileTrashReview(plan: plan, cancel: { session.review = nil }) {
                session.move(plan, applied: store.applyFileTrash)
            }
        }.alert(
            L10n.text("Не удалось выполнить действие"),
            isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })
        ) {
            Button(L10n.text("Понятно")) { session.error = nil }
        } message: {
            Text(session.error ?? "")
        }
    }
}

private struct FileTrashReview: View {
    let plan: FileTrashPlan
    let cancel: () -> Void
    let confirm: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L10n.text("Переместить в Корзину?"), systemImage: "trash").font(.title2.weight(.semibold))
            Text(L10n.text("Объектов: ") + plan.items.count.formatted() + " · " + byteString(plan.bytes)).font(
                .system(size: 13)
            ).monospacedDigit()
            Text(L10n.text("Проверь список. Объекты можно восстановить через Finder.")).font(.system(size: 11))
                .foregroundStyle(Palette.sub)
            if plan.hasFolders {
                Label(L10n.text("Папки будут перемещены целиком, со всем содержимым."), systemImage: "folder").font(
                    .system(size: 11, weight: .medium))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(plan.items) { item in
                        HStack(alignment: .top) {
                            Image(systemName: item.entry.kind.symbol)
                            Text(item.entry.path).frame(maxWidth: .infinity, alignment: .leading).textSelection(
                                .enabled)
                            Text(byteString(item.entry.bytes)).monospacedDigit()
                        }.font(.system(size: 11))
                    }
                }.padding(12)
            }.background(Palette.soft, in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Spacer()
                Button(L10n.text("Отмена"), action: cancel).keyboardShortcut(.cancelAction)
                Button(L10n.text("Переместить в Корзину"), role: .destructive, action: confirm).buttonStyle(
                    .borderedProminent)
            }
        }.padding(24).frame(width: 650, height: min(570, 300 + CGFloat(plan.items.count) * 45)).background(
            Palette.paper
        ).foregroundStyle(Palette.ink)
    }
}

struct MapGroupInspector: View {
    let group: MapGroup
    let parent: String
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLabel(text: L10n.text("Подробности"))
            Image(systemName: "square.stack.3d.up").font(.system(size: 29, weight: .light)).foregroundStyle(Palette.sub)
            Text(group.title).font(.system(size: 18, weight: .semibold))
            Text(parent).font(.system(size: 10)).foregroundStyle(Palette.sub).lineLimit(3)
            Text(byteString(group.bytes)).font(.system(size: 24)).monospacedDigit()
            Text(L10n.text("Состав области — в списке под картой.")).font(.system(size: 11)).foregroundStyle(
                Palette.sub)
            Spacer()
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Palette.paper)
    }
}

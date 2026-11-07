import AtlasCore
import SwiftUI

/// This slot remains mounted at a fixed height, including with no checked items.
struct TrashSelectionBar: View {
    let count: Int
    let busy: Bool
    var notice: String? = nil
    let clear: () -> Void
    let review: () -> Void
    let stop: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Text(count > 0 ? L10n.text("Выбрано: ") + count.formatted() : "").monospacedDigit().lineLimit(1).frame(
                width: 110, alignment: .leading)
            Button(L10n.text("Снять выбор"), action: clear).buttonStyle(.plain).opacity(count > 0 ? 1 : 0).disabled(
                count == 0 || busy
            ).accessibilityHidden(count == 0)
            Text(notice ?? "").foregroundStyle(Palette.sub).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if busy {
                ProgressView().controlSize(.mini)
                Button(L10n.text("Остановить"), action: stop)
            } else {
                Button(L10n.text("В корзину…"), systemImage: "trash", action: review).disabled(count == 0)
            }
        }.font(.system(size: 11)).padding(.horizontal, 10).frame(height: 40).background(
            Palette.soft.opacity(count > 0 || busy ? 1 : 0), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct FileTrashControls: View {
    @ObservedObject var session: FileTrashSession
    let store: AtlasStore
    var body: some View {
        TrashSelectionBar(
            count: session.selected.count, busy: session.busy, notice: session.message,
            clear: { session.selected = [] }, review: { store.reviewFileTrash() }, stop: session.stop
        ).sheet(item: $session.review) { plan in
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

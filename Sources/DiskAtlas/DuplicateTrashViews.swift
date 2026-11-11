import AtlasCore
import SwiftUI

struct DuplicateTrashReview: View {
    let plan: DuplicateTrashPlan
    let cancel: () -> Void
    let confirm: () -> Void
    private var reviewHeight: CGFloat {
        min(
            620,
            max(
                330,
                230 + CGFloat(plan.files.count) * 44 + CGFloat(plan.batches.count) * 54
                    + (plan.removesWholeGroups ? 44 : 0)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(L10n.text("Переместить в Корзину?"), systemImage: "trash").font(.title2.weight(.semibold))
            Text(L10n.text("Файлов: ") + plan.files.count.formatted() + " · " + byteString(plan.bytes)).font(
                .system(size: 13)
            ).monospacedDigit()
            Text(
                L10n.text(
                    "Проверь список. Выбранные файлы будут перемещены в Корзину; их можно восстановить через Finder.")
            ).font(.system(size: 11)).foregroundStyle(Palette.sub)
            if plan.removesWholeGroups {
                Label(L10n.text("В некоторых группах не останется копий"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.orange)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(plan.batches, id: \.groupID) { batch in
                        Section {
                            ForEach(batch.files) { file in
                                let kind = FileKind.classify(URL(fileURLWithPath: file.path))
                                HStack(alignment: .top) {
                                    FileTypeIcon(kind: kind)
                                    Text(file.path).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(byteString(file.bytes)).monospacedDigit()
                                }.font(.system(size: 11)).textSelection(.enabled)
                            }
                            Divider()
                        } header: {
                            VStack(alignment: .leading, spacing: 6) {
                                if let keeper = batch.keeper {
                                    Label(L10n.text("Останется"), systemImage: "checkmark.shield").foregroundStyle(
                                        Palette.accent)
                                    Text(keeper.path).foregroundStyle(Palette.sub)
                                } else {
                                    Label(L10n.text("Все копии выбраны"), systemImage: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    Text(URL(fileURLWithPath: batch.reference.path).lastPathComponent).foregroundStyle(
                                        Palette.sub)
                                }
                            }.font(.system(size: 11)).textSelection(.enabled)
                        }
                    }
                }.padding(12)
            }.background(Palette.soft, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                Button(L10n.text("Отмена"), action: cancel).keyboardShortcut(.cancelAction)
                Button(L10n.text("Переместить в Корзину"), role: .destructive, action: confirm).buttonStyle(
                    AtlasButtonStyle(emphasized: true))
            }
        }.padding(24).frame(width: 650, height: reviewHeight).background(Palette.paper).foregroundStyle(Palette.ink)
    }
}

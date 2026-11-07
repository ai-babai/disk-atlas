import AtlasCore
import SwiftUI

struct SnapshotLoadingView: View {
    let title: String
    let stage: String
    var body: some View {
        ZStack {
            Palette.paper.opacity(0.7).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.regular)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.text(stage)).font(.system(size: 16, weight: .semibold))
                        Text(title).font(.system(size: 12)).foregroundStyle(Palette.sub).lineLimit(2).truncationMode(
                            .middle)
                    }
                }
                ProgressView().progressViewStyle(.linear).tint(Palette.accent)
                Text(L10n.text("Сохранённые данные · без повторного анализа")).font(.system(size: 10)).foregroundStyle(
                    Palette.sub)
            }.padding(24).frame(width: 350, alignment: .leading).background(
                Palette.paper, in: RoundedRectangle(cornerRadius: 14)
            ).overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 1)).shadow(
                color: .black.opacity(0.08), radius: 22, y: 8)
        }.accessibilityElement(children: .combine)
    }
}

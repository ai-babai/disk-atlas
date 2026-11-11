import AppKit
import AtlasCore
import SwiftUI

/// Optional guidance only. macOS owns consent; never probe protected files to infer permission.
struct FileAccessHelpButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button(L10n.text("Доступ к файлам…"), systemImage: "lock.shield") { openWindow(id: "file-access") }.buttonStyle(
            AtlasButtonStyle())
    }
}

struct FileAccessHelp: View {
    @Environment(\.dismissWindow) private var dismissWindow
    private func dismiss() { dismissWindow(id: "file-access") }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(L10n.text("Доступ к файлам"), systemImage: "lock.shield").font(.title2.weight(.semibold))
            Text(
                L10n.text(
                    "Обычно достаточно запросов macOS при обращении к защищённым папкам. Ты можешь разрешить или отклонить каждый запрос. Недоступные папки будут пропущены и показаны в отчёте."
                )
            ).font(.callout)
            VStack(alignment: .leading, spacing: 10) {
                accessCard
                Text(
                    L10n.text(
                        "Если хочешь меньше отдельных запросов, открой Системные настройки → Конфиденциальность и безопасность → Полный доступ к диску. Добавь Disk Atlas кнопкой «+» и включи переключатель."
                    )
                ).font(.callout).fixedSize(horizontal: false, vertical: true)
                Text(
                    L10n.text(
                        "Это широкое системное разрешение, а не режим «только чтение». Disk Atlas анализирует метаданные; содержимое читает при поиске дубликатов и Quick Look. Перенос в Корзину требует отдельного подтверждения. Доступ можно отозвать в тех же настройках."
                    )
                ).font(.system(size: 11)).foregroundStyle(Palette.sub).fixedSize(horizontal: false, vertical: true)
                Text(
                    L10n.text(
                        "После изменения доступа перезапусти приложение и повтори анализ. macOS может снова запросить разрешение после обновления приложения."
                    )
                ).font(.system(size: 11)).foregroundStyle(Palette.sub).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(L10n.text("Показать приложение")) {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
                Spacer()
                Button(L10n.text("Готово"), action: dismiss).keyboardShortcut(.cancelAction)
            }.controlSize(.small)
        }.padding(24).frame(width: 600).fixedSize(horizontal: false, vertical: true).background(Palette.paper)
            .foregroundStyle(Palette.ink).navigationTitle(L10n.text("Доступ к файлам"))
    }
    private var accessCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield").font(.system(size: 22)).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("Полный доступ к диску — по желанию")).font(.headline)
                Text(
                    L10n.text(
                        "Почта, Сообщения и данные других приложений могут быть недоступны. Пропущенные папки не входят в подсчитанный размер."
                    )
                ).font(.callout).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(L10n.text("Открыть системные настройки")) {
                        if let url = URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
                        {
                            NSWorkspace.shared.open(url)
                        }
                    }.buttonStyle(AtlasButtonStyle(emphasized: true))
                    Button(L10n.text("Не сейчас"), action: dismiss)
                }.controlSize(.small)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(
            .orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10)
        ).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.orange.opacity(0.35)))
    }
}

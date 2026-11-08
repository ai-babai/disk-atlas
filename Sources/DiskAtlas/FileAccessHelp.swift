import AppKit
import AtlasCore
import SwiftUI

/// Optional guidance only. macOS owns consent; never probe protected files to infer permission.
struct FileAccessHelpButton: View {
    @State private var presented = false
    var body: some View {
        Button(L10n.text("Доступ к файлам…"), systemImage: "lock.shield") { presented = true }.buttonStyle(.plain).font(
            .system(size: 10)
        ).foregroundStyle(Palette.sub).sheet(isPresented: $presented) { FileAccessHelp { presented = false } }
    }
}

private struct FileAccessHelp: View {
    let dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(L10n.text("Доступ к файлам"), systemImage: "lock.shield").font(.title2.weight(.semibold))
            Text(
                L10n.text(
                    "Обычно достаточно запросов macOS при обращении к защищённым папкам. Ты можешь разрешить или отклонить каждый запрос. Недоступные папки будут пропущены и показаны в отчёте."
                )
            ).font(.callout)
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("Полный доступ к диску — по желанию")).font(.headline)
                Text(
                    L10n.text(
                        "Если хочешь меньше отдельных запросов, открой Системные настройки → Конфиденциальность и безопасность → Полный доступ к диску. Добавь Disk Atlas кнопкой «+» и включи переключатель."
                    )
                ).font(.callout)
                Text(
                    L10n.text(
                        "Это широкое системное разрешение, а не режим «только чтение». Disk Atlas анализирует метаданные; содержимое читает при поиске дубликатов и Quick Look. Перенос в Корзину требует отдельного подтверждения. Доступ можно отозвать в тех же настройках."
                    )
                ).font(.system(size: 11)).foregroundStyle(Palette.sub)
                Text(
                    L10n.text(
                        "После изменения доступа перезапусти приложение и повтори анализ. macOS может снова запросить разрешение после обновления приложения."
                    )
                ).font(.system(size: 11)).foregroundStyle(Palette.sub)
            }.padding(16).background(Palette.soft, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button(L10n.text("Открыть системные настройки")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
                    {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button(L10n.text("Показать приложение")) {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
                Spacer()
                Button(L10n.text("Готово"), action: dismiss).keyboardShortcut(.cancelAction)
            }.controlSize(.small)
        }.padding(24).frame(width: 600).background(Palette.paper).foregroundStyle(Palette.ink)
    }
}

import AtlasCore
import SwiftUI

struct AtlasHelpView: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(L10n.text("Справка Disk Atlas")).font(.system(size: 24, weight: .semibold))
                section("Начало работы") {
                    Text(
                        L10n.text("Добавь папки и нажми «Анализировать». Выбор папки сам по себе не запускает анализ."))
                    Text(
                        L10n.text(
                            "Один щелчок по карте показывает подробности. Двойной щелчок открывает папку; стрелки в списке раскрывают её содержимое."
                        ))
                    Text(
                        L10n.text(
                            "«Крупные файлы» помогает найти самые большие объекты. «Дубликаты» показывает подтверждённые одинаковые копии; фильтры стоят слева от поиска."
                        ))
                }
                section("Размеры и дубликаты") {
                    Text(
                        L10n.text(
                            "«На диске» — выделенные файлу блоки, «Размер файлов» — длина содержимого. APFS может разделять блоки между копиями: повторный объём не равен гарантированно освобождаемому месту."
                        ))
                    Text(
                        L10n.text(
                            "Обычный анализ читает метаданные. Поиск дубликатов читает содержимое только после галочки «Найти дубликаты» или явного запуска проверки."
                        ))
                }
                section("Данные и Корзина") {
                    Text(
                        L10n.text(
                            "Анализ и снимки остаются на Mac. Автоматическая телеметрия не отправляется. Обратная связь передаётся в Sentry только по кнопке «Отправить»."
                        ))
                    Text(
                        L10n.text(
                            "Перенос файлов в Корзину всегда требует проверки списка и подтверждения. Восстановить файлы можно через Finder. Удаление сохранённого снимка не удаляет исходные файлы."
                        ))
                    FileAccessHelpButton()
                }
                section("Горячие клавиши") {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        shortcut("Новый анализ…", "⌘N")
                        shortcut("Открыть снимок…", "⌘O")
                        shortcut("Сохранить снимок…", "⌘S")
                        shortcut("Найти…", "⌘F")
                        shortcut("Быстрый просмотр", L10n.text("Пробел"))
                        shortcut("Показать подробности", "⌥⌘I")
                    }
                }
                HStack(spacing: 12) {
                    Button(L10n.text("Сообщить об ошибке…"), systemImage: "ladybug") { openWindow(id: "feedback") }
                    Link(L10n.text("Релизы и обновления…"), destination: AtlasLinks.releases)
                }
            }.font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(
                24)
        }.frame(width: 600, height: 650).background(Palette.paper).foregroundStyle(Palette.ink).navigationTitle(
            L10n.text("Справка Disk Atlas"))
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text(title)).font(.system(size: 15, weight: .semibold))
            content()
        }
    }
    private func shortcut(_ title: String, _ keys: String) -> some View {
        GridRow {
            Text(L10n.text(title))
            Text(keys).foregroundStyle(Palette.sub).gridColumnAlignment(.trailing)
        }
    }
}

enum AtlasLinks {
    static let releases = URL(string: "https://github.com/ai-babai/disk-atlas/releases/latest")!
    static let repository = URL(string: "https://github.com/ai-babai/disk-atlas")!
}

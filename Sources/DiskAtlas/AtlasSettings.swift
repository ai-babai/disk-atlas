import AtlasCore
import SwiftUI

struct AtlasSettings: View {
    @AppStorage("atlas.column.created") private var created = true
    @AppStorage("atlas.column.modified") private var modified = true
    @AppStorage("atlas.column.share") private var share = true
    @ObservedObject var store: AtlasStore
    @ObservedObject private var diagnostics = AppDiagnostics.shared
    var body: some View {
        Form {
            Picker("Language / Язык", selection: $store.language) {
                Text("Русский").tag("ru")
                Text("English").tag("en")
            }
            Picker(L10n.text("Оформление"), selection: $store.appearance) {
                Text(L10n.text("Как в системе")).tag("system")
                Text(L10n.text("Светлая")).tag("light")
                Text(L10n.text("Тёмная")).tag("dark")
            }
            Section(L10n.text("Столбцы списка")) {
                Toggle(L10n.text("Создан"), isOn: $created)
                Toggle(L10n.text("Изменён"), isOn: $modified)
                Toggle(L10n.text("Доля"), isOn: $share)
                Text(L10n.text("Ширину столбцов можно менять, перетаскивая границы заголовков.")).font(.caption)
                    .foregroundStyle(Palette.sub)
            }
            Section(L10n.text("Приватность")) {
                AtlasRowToggle(
                    state: diagnostics.enabled ? .on : .off, label: L10n.text("Отправлять диагностику приложения"),
                    showsLabel: true
                ) { diagnostics.enabled.toggle() }
                Text(
                    L10n.text(
                        "Версии приложения и macOS, время анализа и проверки дубликатов, число объектов и коды ошибок отправляются в Sentry (США). Без имён, путей, содержимого файлов и идентификатора устройства."
                    )
                ).font(.caption).foregroundStyle(Palette.sub)
                Text(
                    L10n.text(
                        "Выключение прекращает отправку; уже отправленные сведения остаются в сервисе. Ручная обратная связь работает отдельно."
                    )
                ).font(.caption).foregroundStyle(Palette.sub)
            }
            FileAccessHelpButton()
        }.formStyle(.grouped).padding(12).frame(width: 430)
    }
}

private struct AtlasAppearance: ViewModifier {
    @ObservedObject var store: AtlasStore
    func body(content: Content) -> some View {
        content.buttonStyle(AtlasButtonStyle()).id(store.language).environment(
            \.locale, Locale(identifier: store.language)
        ).tint(Palette.accent).preferredColorScheme(
            store.appearance == "light" ? .light : store.appearance == "dark" ? .dark : nil)
    }
}
extension View { func atlasAppearance(_ store: AtlasStore) -> some View { modifier(AtlasAppearance(store: store)) } }

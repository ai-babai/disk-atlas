import AtlasCore
import SwiftUI

struct AtlasSettings: View {
    @AppStorage("atlas.column.created") private var created = true
    @AppStorage("atlas.column.modified") private var modified = true
    @AppStorage("atlas.column.share") private var share = true
    @ObservedObject var store: AtlasStore
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
            FileAccessHelpButton()
        }.formStyle(.grouped).padding(12).frame(width: 430)
    }
}

private struct AtlasAppearance: ViewModifier {
    @ObservedObject var store: AtlasStore
    func body(content: Content) -> some View {
        content.id(store.language).environment(\.locale, Locale(identifier: store.language)).tint(Palette.accent)
            .preferredColorScheme(store.appearance == "light" ? .light : store.appearance == "dark" ? .dark : nil)
    }
}
extension View { func atlasAppearance(_ store: AtlasStore) -> some View { modifier(AtlasAppearance(store: store)) } }

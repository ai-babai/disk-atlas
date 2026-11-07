import AtlasCore
import SwiftUI

struct AtlasToolbar: ToolbarContent {
    @ObservedObject var store: AtlasStore
    var body: some ToolbarContent {
        navigation
        path
        actions
        language
        inspector
    }
    private var navigation: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if store.canReturnToWorkspace {
                Button(action: store.returnToWorkspace) {
                    Label(L10n.text("Назад к ") + store.returnTitle, systemImage: "chevron.left").lineLimit(1)
                        .truncationMode(.middle)
                }.help(L10n.text("Вернуться к снимку"))
            } else if store.snapshot != nil {
                Button {
                    store.sidebarVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                }.help(L10n.text(store.sidebarVisible ? "Скрыть навигацию · ⌘B" : "Показать навигацию · ⌘B"))
                    .accessibilityLabel(L10n.text(store.sidebarVisible ? "Скрыть навигацию" : "Показать навигацию"))
            }
        }
    }
    private var path: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if store.snapshot != nil {
                HStack(spacing: 9) {
                    Button {
                        store.up()
                    } label: {
                        Image(systemName: "arrow.up")
                    }.disabled(store.folder?.parent == nil).help(L10n.text("На уровень выше · ⌘↑"))
                    HStack(spacing: 5) {
                        ForEach(store.breadcrumbs.suffix(3)) { entry in
                            if entry.parent != nil {
                                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(Palette.sub)
                            }
                            Button(store.name(entry)) { store.navigate(entry.id) }.buttonStyle(.plain).foregroundStyle(
                                entry.id == store.folderID ? Palette.ink : Palette.sub)
                        }
                    }.font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                }.frame(maxWidth: 440, alignment: .leading).disabled(store.preparing)
            }
        }
    }
    private var actions: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if store.snapshot != nil {
                if store.showDuplicates { duplicateActions } else { scanActions }
                Button(L10n.text("Новый анализ"), systemImage: "plus") { store.beginSelection() }.disabled(
                    store.scanning || store.preparing
                ).labelStyle(.titleAndIcon)

            }
        }
    }
    private var language: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) { LanguagePicker(store: store) }
    }
    private var inspector: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if store.snapshot != nil {
                if !store.showDuplicates {
                    Button {
                        store.inspectorVisible.toggle()
                    } label: {
                        Image(systemName: "sidebar.right")
                    }.help(
                        L10n.text(store.inspectorVisible ? "Скрыть подробности · ⌥⌘I" : "Показать подробности · ⌥⌘I")
                    ).accessibilityLabel(
                        L10n.text(store.inspectorVisible ? "Скрыть подробности" : "Показать подробности"))
                }
            }
        }
    }
    @ViewBuilder private var duplicateActions: some View {
        if store.duplicates.busy {
            Button {
                store.duplicates.stop()
            } label: {
                Image(systemName: "stop.circle")
            }.help(L10n.text("Остановить"))
        } else {
            Button {
                store.prepareDuplicates()
            } label: {
                Image(systemName: "arrow.clockwise")
            }.help(L10n.text("Проверить снова")).disabled(store.preparing)
        }
        Button {
            store.duplicates.export()
        } label: {
            Image(systemName: "square.and.arrow.up")
        }.help(L10n.text("Экспорт отчёта…")).disabled(store.duplicates.busy || store.duplicates.report == nil)
    }
    @ViewBuilder private var scanActions: some View {

        if store.scanning {
            Button {
                store.cancel()
            } label: {
                Image(systemName: "stop.circle")
            }.help(L10n.text("Остановить"))
        } else {
            Button {
                if let roots = store.snapshot?.scanRoots { store.scan(roots) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }.help(L10n.text("Повторить сканирование · ⌘R")).disabled(store.preparing)
        }
        Button {
            store.exportSnapshot()
        } label: {
            Image(systemName: "square.and.arrow.up")
        }.help(L10n.text("Сохранить снимок · ⌘S")).disabled(store.preparing)
    }
}

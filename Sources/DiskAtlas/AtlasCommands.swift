import AtlasCore
import SwiftUI

struct AtlasCommands: Commands {
    @ObservedObject var store: AtlasStore
    var body: some Commands {
        workspace
        files
        scanning
        CommandGroup(after: .textEditing) {
            Button(L10n.text("Найти…")) { store.searchRequest &+= 1 }.keyboardShortcut("f").disabled(
                store.snapshot == nil)
            Button(L10n.text("Найти в списке…")) { store.searchRequest &+= 1 }.keyboardShortcut(
                "f", modifiers: [.command, .option]
            ).disabled(store.snapshot == nil)
        }
    }
    private var workspace: some Commands {
        CommandGroup(after: .sidebar) {
            Button(L10n.text("Вернуться к снимку")) { store.returnToWorkspace() }.keyboardShortcut(
                "[", modifiers: .command
            ).disabled(!store.canReturnToWorkspace)
            Button(L10n.text(store.sidebarVisible ? "Скрыть навигацию" : "Показать навигацию")) {
                store.sidebarVisible.toggle()
            }.keyboardShortcut("b").disabled(store.snapshot == nil)
            Button(L10n.text(store.inspectorVisible ? "Скрыть подробности" : "Показать подробности")) {
                store.inspectorVisible.toggle()
            }.keyboardShortcut("i", modifiers: [.command, .option]).disabled(store.snapshot == nil)
            Button(L10n.text("Сохранённые снимки…")) { store.showHistory = true }
            Button(L10n.text("Дубликаты")) { store.openDuplicates() }.disabled(store.snapshot == nil)
        }
    }
    private var files: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L10n.text("Новый анализ…")) { store.beginSelection() }.keyboardShortcut("n").disabled(
                store.scanning || store.preparing)
            Button(L10n.text("Открыть снимок…")) { store.importSnapshot() }.keyboardShortcut("o", modifiers: .command)
                .disabled(store.scanning || store.preparing)
            Button(L10n.text(store.showDuplicates ? "Экспорт отчёта…" : "Сохранить снимок…")) {
                if store.showDuplicates { store.duplicates.export() } else { store.exportSnapshot() }
            }.keyboardShortcut("s").disabled(
                store.scanning || store.preparing || store.snapshot == nil
                    || (store.showDuplicates && (store.duplicates.busy || store.duplicates.report == nil)))
        }
    }
    private var scanning: some Commands {
        CommandMenu(L10n.text("Сканирование")) {
            Button(L10n.text("Повторить")) {
                if store.showDuplicates {
                    store.prepareDuplicates()
                } else if let roots = store.snapshot?.scanRoots {
                    store.scan(roots)
                }
            }.keyboardShortcut("r").disabled(
                store.scanning || store.snapshot == nil || (store.showDuplicates && store.duplicates.busy))
            Button(L10n.text("Остановить")) {
                if store.duplicates.busy { store.duplicates.stop() }
                store.cancel()
            }.keyboardShortcut(".").disabled(!store.scanning && !store.duplicates.busy)
            Button(L10n.text("На уровень выше")) { store.up() }.keyboardShortcut(.upArrow, modifiers: .command)

        }
    }
}

import AtlasCore
import SwiftUI

struct AtlasCommands: Commands {
    @ObservedObject var store: AtlasStore
    var body: some Commands {
        workspace
        files
        scanning
    }
    private var workspace: some Commands {
        CommandGroup(after: .sidebar) {
            Button(L10n.text(store.sidebarVisible ? "Скрыть навигацию" : "Показать навигацию")) {
                store.sidebarVisible.toggle()
            }.keyboardShortcut("b").disabled(store.snapshot == nil)
            Button(L10n.text(store.inspectorVisible ? "Скрыть подробности" : "Показать подробности")) {
                store.inspectorVisible.toggle()
            }.keyboardShortcut("i", modifiers: [.command, .option]).disabled(store.snapshot == nil)
            Button(L10n.text("История сканов…")) { store.showHistory = true }
            Button(L10n.text("Дубликаты")) { store.openDuplicates() }.disabled(store.snapshot == nil)
        }
    }
    private var files: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L10n.text("Новый анализ…")) { store.beginSelection() }.keyboardShortcut("o").disabled(
                store.scanning || store.preparing)
            Button(L10n.text("Открыть снимок…")) { store.importSnapshot() }.keyboardShortcut(
                "o", modifiers: [.command, .shift]
            ).disabled(store.scanning || store.preparing)
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
            Button(L10n.text("Контекст для агента")) { store.copyContext() }.keyboardShortcut(
                "c", modifiers: [.command, .shift]
            ).disabled(store.snapshot == nil)
        }
    }
}

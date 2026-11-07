import SwiftUI
import Combine
import AtlasCore

@main struct DiskAtlasApp: App {
    @StateObject private var store = AtlasStore()
    @NSApplicationDelegateAdaptor(AtlasAppDelegate.self) private var appDelegate
    var body: some Scene {
        Window("Disk Atlas", id: "main") {
            MainView(store: store)
                .environment(\.locale, Locale(identifier: store.language))
                .frame(minWidth: 1080, minHeight: 730)
                .preferredColorScheme(store.appearance == "light" ? .light : store.appearance == "dark" ? .dark : nil)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        if store.snapshot != nil {
                            Button { store.sidebarVisible.toggle() } label: { Image(systemName: "sidebar.left") }
                                .help(L10n.text(store.sidebarVisible ? "Скрыть навигацию · ⌘B" : "Показать навигацию · ⌘B"))
                                .accessibilityLabel(L10n.text(store.sidebarVisible ? "Скрыть навигацию" : "Показать навигацию"))
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        if store.snapshot != nil {
                            HStack(spacing: 9) {
                                Button { store.up() } label: { Image(systemName: "arrow.up") }
                                    .disabled(store.folder?.parent == nil).help(L10n.text("На уровень выше · ⌘↑"))
                                HStack(spacing: 5) {
                                    ForEach(store.breadcrumbs.suffix(3)) { entry in
                                        if entry.parent != nil { Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(Palette.sub) }
                                        Button(store.name(entry)) { store.navigate(entry.id) }.buttonStyle(.plain)
                                            .foregroundStyle(entry.id == store.folderID ? Palette.ink : Palette.sub)
                                    }
                                }.font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                            }.frame(maxWidth: 440, alignment: .leading).disabled(store.preparing)
                        }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        if store.snapshot != nil {
                            if store.showDuplicates {
                                if store.duplicates.busy {
                                    Button { store.duplicates.stop() } label: { Image(systemName: "stop.circle") }.help(L10n.text("Остановить")).disabled(store.duplicates.savingReport)
                                } else {
                                    Button { store.prepareDuplicates() } label: { Image(systemName: "arrow.clockwise") }.help(L10n.text("Проверить снова")).disabled(store.preparing)
                                }
                                Button { store.duplicates.export() } label: { Image(systemName: "square.and.arrow.up") }
                                    .help(L10n.text("Экспорт отчёта…")).disabled(store.duplicates.busy || store.duplicates.report == nil)
                            } else {
                                if store.scanning {
                                    Button { store.cancel() } label: { Image(systemName: "stop.circle") }.help(L10n.text("Остановить"))
                                } else {
                                    Button { if let roots = store.snapshot?.scanRoots { store.scan(roots) } } label: { Image(systemName: "arrow.clockwise") }
                                        .help(L10n.text("Повторить сканирование · ⌘R")).disabled(store.preparing)
                                }
                                Button { store.exportSnapshot() } label: { Image(systemName: "square.and.arrow.up") }
                                    .help(L10n.text("Сохранить снимок · ⌘S")).disabled(store.preparing)
                            }
                            Button(L10n.text("Новый анализ"), systemImage: "plus") { store.beginSelection() }
                                .disabled(store.scanning || store.preparing).labelStyle(.titleAndIcon)
                            if !store.showDuplicates {
                            Button { store.inspectorVisible.toggle() } label: { Image(systemName: "sidebar.right") }
                                .help(L10n.text(store.inspectorVisible ? "Скрыть подробности · ⌥⌘I" : "Показать подробности · ⌥⌘I"))
                                .accessibilityLabel(L10n.text(store.inspectorVisible ? "Скрыть подробности" : "Показать подробности"))
                            }
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        LanguagePicker(store: store)
                    }
                }
                .onOpenURL { store.openSnapshot($0) }
                .onAppear {
                    appDelegate.store = store
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    let args = CommandLine.arguments
                    if let index = args.firstIndex(of: "--scan"), index + 1 < args.count, store.snapshot == nil {
                        store.scan(args[index + 1])
                    }
                }
        }
        .defaultSize(width: 1380, height: 900)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after: .sidebar) {
                Button(L10n.text(store.sidebarVisible ? "Скрыть навигацию" : "Показать навигацию")) { store.sidebarVisible.toggle() }
                    .keyboardShortcut("b").disabled(store.snapshot == nil)
                Button(L10n.text(store.inspectorVisible ? "Скрыть подробности" : "Показать подробности")) { store.inspectorVisible.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option]).disabled(store.snapshot == nil)
                Button(L10n.text("История сканов…")) { store.showHistory = true }
                Button(L10n.text("Дубликаты")) { store.openDuplicates() }.disabled(store.snapshot == nil)
            }
            CommandGroup(replacing: .newItem) {
                Button(L10n.text("Новый анализ…")) { store.beginSelection() }.keyboardShortcut("o").disabled(store.scanning || store.preparing)
                Button(L10n.text("Открыть снимок…")) { store.importSnapshot() }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(store.scanning || store.preparing)
                Button(L10n.text(store.showDuplicates ? "Экспорт отчёта…" : "Сохранить снимок…")) { if store.showDuplicates { store.duplicates.export() } else { store.exportSnapshot() } }.keyboardShortcut("s").disabled(store.scanning || store.preparing || store.snapshot == nil || (store.showDuplicates && (store.duplicates.busy || store.duplicates.report == nil)))
            }
            CommandMenu(L10n.text("Сканирование")) {
                Button(L10n.text("Повторить")) { if store.showDuplicates { store.prepareDuplicates() } else if let roots = store.snapshot?.scanRoots { store.scan(roots) } }.keyboardShortcut("r").disabled(store.scanning || store.snapshot == nil || (store.showDuplicates && store.duplicates.busy))
                Button(L10n.text("Остановить")) { if store.duplicates.busy { store.duplicates.stop() }; store.cancel() }.keyboardShortcut(".").disabled(!store.scanning && !store.duplicates.busy)
                Button(L10n.text("На уровень выше")) { store.up() }.keyboardShortcut(.upArrow, modifiers: .command)
                Button(L10n.text("Контекст для агента")) { store.copyContext() }.keyboardShortcut("c", modifiers: [.command, .shift]).disabled(store.snapshot == nil)
            }
        }
    }
}

@MainActor final class AtlasAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: AtlasStore?
    private var termination: AnyCancellable?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.savingHistory > 0 || store.deletingHistory || store.duplicates.busy else { return .terminateNow }
        store.duplicates.stop()
        termination = store.$savingHistory.combineLatest(store.$deletingHistory, store.duplicates.$busy).filter { $0 == 0 && !$1 && !$2 }.first().sink { _ in
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

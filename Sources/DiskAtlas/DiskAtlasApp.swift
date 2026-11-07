import AtlasCore
import SwiftUI

@main struct DiskAtlasApp: App {
    @StateObject private var store = AtlasStore()
    @NSApplicationDelegateAdaptor(AtlasAppDelegate.self) private var appDelegate
    var body: some Scene {
        Window("Disk Atlas", id: "main") {
            MainView(store: store).environment(\.locale, Locale(identifier: store.language)).frame(
                minWidth: 1080, minHeight: 730
            ).preferredColorScheme(store.appearance == "light" ? .light : store.appearance == "dark" ? .dark : nil)
                .toolbar { AtlasToolbar(store: store) }.onOpenURL { store.openSnapshot($0) }.onAppear {
                    appDelegate.store = store
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    let args = CommandLine.arguments
                    if let index = args.firstIndex(of: "--scan"), index + 1 < args.count, store.snapshot == nil {
                        store.scan(args[index + 1])
                    }
                }
        }.defaultSize(width: 1380, height: 900).windowStyle(.titleBar).windowToolbarStyle(.unifiedCompact).commands {
            AtlasCommands(store: store)
        }
    }
}

@MainActor final class AtlasAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: AtlasStore?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        store?.cancel()
        store?.fileTrash.stop()
        store?.duplicates.stop()
        return .terminateNow
    }
}

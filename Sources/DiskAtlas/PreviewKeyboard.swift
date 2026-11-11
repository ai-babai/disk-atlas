import AppKit

extension NSEvent {
    var isQuickLookKey: Bool {
        keyCode == 49 && modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
    }
}

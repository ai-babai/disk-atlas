import AtlasCore
import SwiftUI

/// Reserve the indicator's bounds; quick work finishes without a spinner flashing.
struct DelayedActivity: View {
    let active: Bool
    let title: String
    @State private var visible = false
    var body: some View {
        ProgressView().controlSize(.mini).frame(width: 16, height: 16).opacity(active && visible ? 1 : 0)
            .accessibilityLabel(title).accessibilityHidden(!active || !visible).help(title).task(id: active) {
                visible = false
                guard active else { return }
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                guard !Task.isCancelled else { return }
                visible = true
            }
    }
}

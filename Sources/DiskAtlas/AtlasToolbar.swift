import AtlasCore
import SwiftUI

struct AtlasToolbar: ToolbarContent {
    @ObservedObject var store: AtlasStore
    var body: some ToolbarContent {
        navigation
        actions
        path
        language
        inspector
    }
    private var navigation: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Group {
                if store.canReturnToWorkspace {
                    Button(action: store.returnToWorkspace) {
                        Label(L10n.text("Назад к ") + store.returnTitle, systemImage: "chevron.left").lineLimit(1)
                            .truncationMode(.middle)
                    }.help(L10n.text("Вернуться к снимку"))
                } else if store.snapshot != nil {
                    Button {
                        store.sidebarVisible.toggle()
                    } label: {
                        Label(
                            L10n.text(store.sidebarVisible ? "Скрыть навигацию" : "Показать навигацию"),
                            systemImage: "sidebar.left"
                        ).labelStyle(.iconOnly)
                    }.help(L10n.text(store.sidebarVisible ? "Скрыть навигацию · ⌘B" : "Показать навигацию · ⌘B"))
                        .accessibilityLabel(L10n.text(store.sidebarVisible ? "Скрыть навигацию" : "Показать навигацию"))
                }
            }.buttonStyle(.borderless).foregroundStyle(Palette.sub)
        }
    }
    private var path: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if store.snapshot != nil {
                HStack(spacing: 8) {
                    Button {
                        store.up()
                    } label: {
                        Label(L10n.text("На уровень выше"), systemImage: "arrow.up").labelStyle(.iconOnly)
                    }.disabled(store.folder?.parent == nil).help(L10n.text("На уровень выше · ⌘↑"))
                    HStack(spacing: 4) {
                        let visible = store.breadcrumbs.suffix(3)
                        ForEach(visible) { entry in
                            if entry.id != visible.first?.id {
                                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(Palette.sub)
                            }
                            Button(store.name(entry)) { store.navigate(entry.id) }.buttonStyle(.plain).foregroundStyle(
                                entry.id == store.folderID ? Palette.ink : Palette.sub
                            ).fontWeight(entry.id == store.folderID ? .medium : .regular).help(entry.path)
                        }
                    }.font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                }.buttonStyle(.borderless).foregroundStyle(Palette.sub).frame(maxWidth: 440, alignment: .leading)
                    .disabled(store.preparing)
            } else {
                // Preserve native trailing placement when Home has no breadcrumb.
                Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
            }
        }
    }
    private var actions: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Group {
                if store.snapshot != nil {
                    separator
                    Button(L10n.text("Новый анализ"), systemImage: "plus") { store.beginSelection() }.disabled(
                        store.scanning || store.preparing || store.fileTrash.busy
                    ).labelStyle(.titleAndIcon).help(L10n.text("Новый анализ") + " · ⌘N")
                    separator
                    if store.showDuplicates { duplicateActions } else { scanActions }
                }
            }.buttonStyle(.borderless).foregroundStyle(Palette.sub)
        }
    }
    private var separator: some View {
        Rectangle().fill(Palette.line).frame(width: 1, height: 16).padding(.horizontal, 2).allowsHitTesting(false)
            .accessibilityHidden(true)
    }
    private var language: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            LanguagePicker(store: store).menuStyle(.borderlessButton).foregroundStyle(Palette.sub)
            AppearancePicker(store: store).menuStyle(.borderlessButton).foregroundStyle(Palette.sub)
        }
    }
    private var inspector: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Group {
                if store.snapshot != nil {
                    if !store.showDuplicates {
                        Button {
                            store.inspectorVisible.toggle()
                        } label: {
                            Label(
                                L10n.text(store.inspectorVisible ? "Скрыть подробности" : "Показать подробности"),
                                systemImage: "sidebar.right"
                            ).labelStyle(.iconOnly)
                        }.help(
                            L10n.text(
                                store.inspectorVisible ? "Скрыть подробности · ⌥⌘I" : "Показать подробности · ⌥⌘I")
                        ).accessibilityLabel(
                            L10n.text(store.inspectorVisible ? "Скрыть подробности" : "Показать подробности"))
                    }
                }
            }.buttonStyle(.borderless).foregroundStyle(Palette.sub)
        }
    }
    @ViewBuilder private var duplicateActions: some View {
        if store.duplicates.busy {
            Button {
                store.duplicates.stop()
            } label: {
                Label(L10n.text("Остановить"), systemImage: "stop.circle").labelStyle(.iconOnly)
            }.help(L10n.text("Остановить"))
        } else {
            Button {
                store.prepareDuplicates()
            } label: {
                Label(L10n.text("Проверить снова"), systemImage: "arrow.clockwise").labelStyle(.iconOnly)
            }.help(L10n.text("Проверить снова")).disabled(store.preparing)
        }
        separator
        Button {
            store.duplicates.export()
        } label: {
            Label(L10n.text("Экспорт отчёта…"), systemImage: "square.and.arrow.up").labelStyle(.iconOnly)
        }.help(L10n.text("Экспорт отчёта…")).disabled(store.duplicates.busy || store.duplicates.report == nil)
    }
    @ViewBuilder private var scanActions: some View {

        if store.scanning {
            Button {
                store.cancel()
            } label: {
                Label(L10n.text("Остановить"), systemImage: "stop.circle").labelStyle(.iconOnly)
            }.help(L10n.text("Остановить"))
        } else {
            Button {
                if let roots = store.snapshot?.scanRoots { store.scan(roots) }
            } label: {
                Label(L10n.text("Повторить"), systemImage: "arrow.clockwise").labelStyle(.iconOnly)
            }.help(L10n.text("Повторить сканирование · ⌘R")).disabled(store.preparing)
        }
        separator
        Button {
            store.exportSnapshot()
        } label: {
            SnapshotSaveIcon()
        }.accessibilityLabel(L10n.text("Сохранить снимок…")).help(L10n.text("Сохранить снимок · ⌘S")).disabled(
            store.preparing)
    }
}

/// Diskette silhouette keeps Save distinct from Share in the compact toolbar.
private struct SnapshotSaveIcon: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 2, y: 1))
            path.addLines([
                CGPoint(x: 11, y: 1), CGPoint(x: 15, y: 5), CGPoint(x: 15, y: 15), CGPoint(x: 1, y: 15),
                CGPoint(x: 1, y: 2),
            ])
            path.closeSubpath()
            path.addRect(CGRect(x: 4, y: 1, width: 6, height: 5))
            path.addRect(CGRect(x: 4, y: 9, width: 8, height: 6))
        }.stroke(style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)).frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }
}

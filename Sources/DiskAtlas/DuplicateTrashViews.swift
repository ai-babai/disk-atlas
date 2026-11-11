import AtlasCore
import QuickLook
import SwiftUI

struct DuplicateTrashReview: View {
    let plan: DuplicateTrashPlan
    let cancel: () -> Void
    let confirm: () -> Void
    private var reviewHeight: CGFloat {
        min(
            620,
            max(
                330,
                230 + CGFloat(plan.files.count) * 44 + CGFloat(plan.batches.count) * 54
                    + (plan.removesWholeGroups ? 44 : 0)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(L10n.text("Переместить в Корзину?"), systemImage: "trash").font(.title2.weight(.semibold))
            Text(L10n.text("Файлов: ") + plan.files.count.formatted() + " · " + byteString(plan.bytes)).font(
                .system(size: 13)
            ).monospacedDigit()
            Text(
                L10n.text(
                    "Проверь список. Выбранные файлы будут перемещены в Корзину; их можно восстановить через Finder.")
            ).font(.system(size: 11)).foregroundStyle(Palette.sub)
            if plan.removesWholeGroups {
                Label(L10n.text("В некоторых группах не останется копий"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.orange)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(plan.batches, id: \.groupID) { batch in
                        Section {
                            ForEach(batch.files) { file in
                                let kind = FileKind.classify(URL(fileURLWithPath: file.path))
                                HStack(alignment: .top) {
                                    FileTypeIcon(kind: kind)
                                    Text(file.path).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(byteString(file.bytes)).monospacedDigit()
                                }.font(.system(size: 11)).textSelection(.enabled)
                            }
                            Divider()
                        } header: {
                            VStack(alignment: .leading, spacing: 6) {
                                if let keeper = batch.keeper {
                                    Label(L10n.text("Останется"), systemImage: "checkmark.shield").foregroundStyle(
                                        Palette.accent)
                                    Text(keeper.path).foregroundStyle(Palette.sub)
                                } else {
                                    Label(L10n.text("Все копии выбраны"), systemImage: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    Text(URL(fileURLWithPath: batch.reference.path).lastPathComponent).foregroundStyle(
                                        Palette.sub)
                                }
                            }.font(.system(size: 11)).textSelection(.enabled)
                        }
                    }
                }.padding(12)
            }.background(Palette.soft, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                Button(L10n.text("Отмена"), action: cancel).keyboardShortcut(.cancelAction)
                Button(L10n.text("Переместить в Корзину"), role: .destructive, action: confirm).buttonStyle(
                    AtlasButtonStyle(emphasized: true))
            }
        }.padding(24).frame(width: 650, height: reviewHeight).background(Palette.paper).foregroundStyle(Palette.ink)
    }
}

struct DuplicateGroupRow: View {
    let group: DuplicateGroup
    @ObservedObject var session: DuplicateSession
    @Binding var expanded: Bool
    var columns = DuplicateTableColumns()
    var select: (() -> Void)? = nil
    var selected = false
    var selectedPath: String?
    var selectFile: ((DuplicateFile) -> Void)?
    @State private var previewURL: URL?
    @State private var focusedFile: String?
    private var selectedCount: Int {
        session.trashSelection.paths.isEmpty ? 0 : session.trashSelection.count(in: group)
    }
    private var representative: DuplicateFile? { group.files.first }
    var body: some View {
        // Keep copies in the parent's lazy stack, including when the group header scrolls offscreen.
        Section {
            if expanded { files }
        } header: {
            header
        } footer: {
            Divider().overlay(Palette.line)
        }.quickLookPreview($previewURL, in: group.files.prefix(200).map { URL(fileURLWithPath: $0.path) }).onChange(
            of: previewURL
        ) { previous, current in restorePreviewFocus(previous, current: current) }.onChange(of: expanded) { _, value in
            if !value { previewURL = nil }
        }.onDisappear { previewURL = nil }
    }
    private var header: some View {
        HStack(spacing: 0) {
            groupCheckbox.frame(width: FileListMetrics.checkWidth)
            disclosureButton
            expandButton
            HStack(spacing: 0) {
                Color.clear.frame(width: 64)
                Button {
                    session.reviewTrash(group)
                } label: {
                    Image(systemName: "trash").frame(width: 24, height: 28)
                }.buttonStyle(.plain).disabled(session.busy).help(L10n.text("В корзину группу…")).accessibilityLabel(
                    L10n.text("В корзину копии группы") + ": " + (group.displayName ?? ""))
            }.frame(width: DuplicateTableColumns.actionsWidth)
        }.padding(.horizontal, 8).frame(minHeight: FileListMetrics.pathRowHeight).background {
            RoundedRectangle(cornerRadius: 5).fill(selected ? Palette.mark : .clear).padding(.horizontal, 2).padding(
                .vertical, 1)
        }.accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var groupCheckbox: some View {
        Button {
            session.trashSelection.toggle(group)
        } label: {
            Image(
                systemName: selectedCount == 0
                    ? "square" : selectedCount == group.files.count ? "checkmark.square.fill" : "minus.square.fill"
            ).frame(width: 24, height: 28)
        }.buttonStyle(.plain).disabled(session.busy).help(L10n.text("Выбрать все копии группы для корзины"))
            .accessibilityLabel(L10n.text("Выбрать все копии группы") + ": " + (group.displayName ?? ""))
    }
    private func restorePreviewFocus(_ previous: URL?, current: URL?) {
        guard current == nil, let previous, expanded else { return }
        Task { @MainActor in
            await Task.yield()
            if expanded { focusedFile = previous.path }
        }
    }
    private var groupSelectionStatus: String {
        if selectedCount == group.files.count { return L10n.text("Все копии выбраны") }
        return L10n.text("Останется: ") + String(group.files.count - selectedCount)
    }
    private var expandButton: some View {
        Button {
            if let select { select() } else { toggleExpanded() }
        } label: {
            HStack(spacing: 0) {
                groupName
                if columns.created { columns.date(nil) }
                if columns.modified { columns.date(nil) }
                Text("\(group.files.count)").font(Font(FileListMetrics.sizeFont)).frame(
                    width: DuplicateTableColumns.copiesWidth, alignment: .trailing)
                Text(byteString(group.repeatedBytes)).font(Font(FileListMetrics.sizeFont)).padding(.horizontal, 6)
                    .frame(width: FileListMetrics.sizeWidth, alignment: .trailing)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).help(
            select == nil ? L10n.text("Показать все копии") : L10n.text("На карте: ") + (group.displayName ?? ""))
    }
    private var disclosureButton: some View {
        Button(action: toggleExpanded) {
            Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .semibold))
                .frame(width: 16, height: 28).padding(.trailing, 8)
        }.buttonStyle(.plain).accessibilityLabel(L10n.text("Показать все копии") + ": " + (group.displayName ?? ""))
    }
    private func toggleExpanded() { expanded.toggle() }
    private var groupName: some View {
        let kind = representative.map { FileKind.classify(URL(fileURLWithPath: $0.path)) } ?? .other
        return HStack(spacing: FileListMetrics.iconTextSpacing) {
            FileTypeIcon(kind: kind)
            VStack(alignment: .leading, spacing: 3) {
                Text(group.displayName ?? representative.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? "")
                    .font(Font(FileListMetrics.nameFont)).lineLimit(1).truncationMode(.middle)
                ZStack(alignment: .leading) {
                    Text((group.locations ?? []).joined(separator: " · ")).opacity(selectedCount == 0 ? 1 : 0)
                        .accessibilityHidden(selectedCount > 0)
                    Text(groupSelectionStatus).foregroundStyle(
                        selectedCount == group.files.count ? .orange : Palette.accent
                    ).opacity(selectedCount > 0 ? 1 : 0).accessibilityHidden(selectedCount == 0)
                }.font(Font(FileListMetrics.secondaryFont)).foregroundStyle(Palette.sub).lineLimit(1)
            }
        }.padding(.vertical, 4).padding(.trailing, 8).frame(
            minWidth: DuplicateTableColumns.nameWidth - 24, maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var files: some View {
        let groupHasSelection = selectedCount > 0
        ForEach(group.files.prefix(200)) { file in
            DuplicateFileRow(
                file: file, group: group, session: session, focusedFile: $focusedFile, columns: columns,
                groupHasSelection: groupHasSelection, mapSelected: selectedPath == file.path,
                select: selectFile.map { action in { action(file) } }
            ) { previewURL = URL(fileURLWithPath: file.path) }.background(Palette.soft.opacity(0.6))
        }
        if group.files.count > 200 {
            Text(L10n.text("Остальные копии доступны в экспорте.")).font(.caption).foregroundStyle(Palette.sub)
        }
    }
}

private struct DuplicateFileRow: View {
    let file: DuplicateFile
    let group: DuplicateGroup
    @ObservedObject var session: DuplicateSession
    @Binding var focusedFile: String?
    let columns: DuplicateTableColumns
    let groupHasSelection: Bool
    let mapSelected: Bool
    let select: (() -> Void)?
    let preview: () -> Void
    @FocusState private var checkboxFocused: Bool
    private var focused: Bool { focusedFile == file.path }
    private var selected: Bool { session.trashSelection.paths.contains(file.path) }
    private var keeper: Bool { !selected && groupHasSelection }
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            checkbox.frame(width: FileListMetrics.checkWidth, height: 28)
            fileName
            if columns.created { columns.date(file.created.timeIntervalSince1970 == 0 ? nil : file.created) }
            if columns.modified { columns.date(file.modified) }
            Color.clear.frame(width: DuplicateTableColumns.copiesWidth, height: 1)
            Text(byteString(file.bytes)).font(Font(FileListMetrics.sizeFont)).padding(.top, 5).padding(.horizontal, 6)
                .frame(width: FileListMetrics.sizeWidth, alignment: .trailing)
            actions
        }.padding(.horizontal, 8).padding(.vertical, 4).frame(minHeight: FileListMetrics.pathRowHeight).background(
            (select == nil ? focused : mapSelected) ? Palette.mark.opacity(0.5) : .clear
        ).contentShape(Rectangle()).onTapGesture(count: 2) { session.reveal(file) }.contextMenu {
            Button(L10n.text("Быстрый просмотр"), action: openPreview)
            Button(L10n.text("Показать в Finder")) { session.reveal(file) }
            Button(L10n.text("Скопировать путь")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            }
        }
    }
    private var checkbox: some View {
        Toggle(L10n.text("Выбрать для корзины"), isOn: Binding(get: { selected }, set: { _ in toggleTrashSelection() }))
            .labelsHidden().toggleStyle(.checkbox).focusable().focusEffectDisabled().focused($checkboxFocused)
            .onKeyPress(.space) {
                toggleTrashSelection()
                return .handled
            }.disabled(session.busy).help(L10n.text("Выбрать для корзины")).accessibilityLabel(
                L10n.text("Выбрать для корзины") + ": " + URL(fileURLWithPath: file.path).lastPathComponent)
    }
    private var fileName: some View {
        let kind = FileKind.classify(URL(fileURLWithPath: file.path))
        return HStack(alignment: .top, spacing: FileListMetrics.iconTextSpacing) {
            FileTypeIcon(kind: kind).padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(URL(fileURLWithPath: file.path).lastPathComponent).font(Font(FileListMetrics.nameFont))
                        .lineLimit(1)
                    Text(L10n.text("Останется")).font(Font(FileListMetrics.secondaryFont)).foregroundStyle(
                        Palette.accent
                    ).opacity(keeper ? 1 : 0).accessibilityHidden(!keeper)
                }
                Text(file.path).font(Font(FileListMetrics.secondaryFont)).foregroundStyle(Palette.sub).lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.top, 3)
        }.padding(.leading, 24).padding(.trailing, 8).frame(
            minWidth: DuplicateTableColumns.nameWidth, maxWidth: .infinity, alignment: .leading
        ).contentShape(Rectangle()).onTapGesture {
            focusedFile = file.path
            select?()
        }.background(
            PreviewKeyboard(active: focused, preview: openPreview, blurred: { if focused { focusedFile = nil } }))
    }
    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: openPreview) { Image(systemName: "eye").frame(width: 24, height: 28) }.buttonStyle(.plain)
                .help(L10n.text("Быстрый просмотр · Пробел")).accessibilityLabel(
                    L10n.text("Быстрый просмотр") + ": " + URL(fileURLWithPath: file.path).lastPathComponent)
            Button {
                session.reveal(file)
            } label: {
                Image(systemName: "arrow.up.forward.square").frame(width: 24, height: 28)
            }.buttonStyle(.plain).help(L10n.text("Показать в Finder"))
            Button {
                session.reviewTrash([file.path])
            } label: {
                Image(systemName: "trash").frame(width: 24, height: 28)
            }.buttonStyle(.plain).disabled(session.busy).help(L10n.text("В корзину…")).accessibilityLabel(
                L10n.text("В корзину") + ": " + URL(fileURLWithPath: file.path).lastPathComponent)
        }.frame(width: DuplicateTableColumns.actionsWidth)
    }
    private func toggleTrashSelection() {
        guard !session.busy else { return }
        focusedFile = nil
        checkboxFocused = true
        session.trashSelection.toggle(file, in: group)
    }
    private func openPreview() {
        checkboxFocused = false
        focusedFile = file.path
        preview()
    }
}

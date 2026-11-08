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
                                HStack(alignment: .top) {
                                    Image(systemName: "trash").foregroundStyle(Palette.sub)
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
                    .borderedProminent)
            }
        }.padding(24).frame(width: 650, height: reviewHeight).background(Palette.paper).foregroundStyle(Palette.ink)
    }
}

struct DuplicateGroupRow: View {
    let group: DuplicateGroup
    @ObservedObject var session: DuplicateSession
    @Binding var expanded: Bool
    @State private var previewURL: URL?
    @State private var focusedFile: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var selectedCount: Int { session.trashSelection.count(in: group) }
    private var representative: DuplicateFile? { group.files.first }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    session.trashSelection.toggle(group)
                } label: {
                    Image(
                        systemName: selectedCount == 0
                            ? "square"
                            : selectedCount == group.files.count ? "checkmark.square.fill" : "minus.square.fill"
                    ).frame(width: 20, height: 28)
                }.buttonStyle(.plain).disabled(session.busy).help(L10n.text("Выбрать все копии группы для корзины"))
                    .accessibilityLabel(L10n.text("Выбрать все копии группы") + ": " + (group.displayName ?? ""))
                expandButton
                Button {
                    session.reviewTrash(group)
                } label: {
                    Image(systemName: "trash").frame(width: 24, height: 28)
                }.buttonStyle(.plain).disabled(session.busy).help(L10n.text("В корзину группу…")).accessibilityLabel(
                    L10n.text("В корзину копии группы") + ": " + (group.displayName ?? ""))
            }.padding(.horizontal, 12)
            if expanded { files }
            Divider().overlay(Palette.line)
        }.quickLookPreview($previewURL, in: group.files.prefix(200).map { URL(fileURLWithPath: $0.path) }).onChange(
            of: previewURL
        ) { previous, current in restorePreviewFocus(previous, current: current) }.onChange(of: expanded) { _, value in
            if !value { previewURL = nil }
        }.onDisappear { previewURL = nil }
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
        return selectedCount > 0 ? L10n.text("Останется: ") + String(group.files.count - selectedCount) : ""
    }
    private var expandButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { expanded.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .semibold))
                    .frame(width: 8)
                Image(
                    systemName: representative.map { FileKind.classify(URL(fileURLWithPath: $0.path)).symbol } ?? "doc"
                ).font(.system(size: 14)).foregroundStyle(Palette.accent).frame(width: 14)
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        group.displayName ?? representative.map { URL(fileURLWithPath: $0.path).lastPathComponent }
                            ?? ""
                    ).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 8) {
                        Text((group.locations ?? []).joined(separator: " · ")).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(groupSelectionStatus).foregroundStyle(
                            selectedCount == group.files.count ? .orange : Palette.accent
                        ).frame(width: 125, height: 12, alignment: .trailing)
                    }.font(.system(size: 10)).foregroundStyle(Palette.sub)

                }
                Spacer(minLength: 8)
                Text("\(group.files.count)").frame(width: 52, alignment: .trailing)
                Text(byteString(group.repeatedBytes)).fontWeight(.medium).frame(width: 100, alignment: .trailing)
            }.font(.system(size: 11)).monospacedDigit().padding(.vertical, 12).contentShape(Rectangle())
        }.buttonStyle(.plain).help(L10n.text("Показать все копии"))
    }
    private var files: some View {
        VStack(spacing: 0) {
            ForEach(group.files.prefix(200)) { file in
                DuplicateFileRow(file: file, group: group, session: session, focusedFile: $focusedFile) {
                    previewURL = URL(fileURLWithPath: file.path)
                }
            }
            if group.files.count > 200 {
                Text(L10n.text("Остальные копии доступны в экспорте.")).font(.caption).foregroundStyle(Palette.sub)
            }
        }.background(Palette.soft.opacity(0.6)).padding(.bottom, 6)
    }
}

private struct DuplicateFileRow: View {
    let file: DuplicateFile
    let group: DuplicateGroup
    @ObservedObject var session: DuplicateSession
    @Binding var focusedFile: String?
    let preview: () -> Void
    @FocusState private var checkboxFocused: Bool
    private var focused: Bool { focusedFile == file.path }
    private var selected: Bool { session.trashSelection.paths.contains(file.path) }
    private var keeper: Bool { !selected && session.trashSelection.count(in: group) > 0 }
    var body: some View {
        HStack(spacing: 10) {
            Toggle(
                L10n.text("Выбрать для корзины"), isOn: Binding(get: { selected }, set: { _ in toggleTrashSelection() })
            ).labelsHidden().toggleStyle(.checkbox).focusable().focusEffectDisabled().focused($checkboxFocused)
                .onKeyPress(.space) {
                    toggleTrashSelection()
                    return .handled
                }.disabled(session.busy).help(L10n.text("Выбрать для корзины")).accessibilityLabel(
                    L10n.text("Выбрать для корзины") + ": " + URL(fileURLWithPath: file.path).lastPathComponent)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(URL(fileURLWithPath: file.path).lastPathComponent).font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Text(L10n.text("Останется")).font(.system(size: 10)).foregroundStyle(Palette.accent).frame(
                        width: 70
                    ).opacity(keeper ? 1 : 0).accessibilityHidden(!keeper)
                }
                Text(file.path).font(.system(size: 10)).foregroundStyle(Palette.sub).lineLimit(1).truncationMode(
                    .middle)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).simultaneousGesture(
                TapGesture().onEnded { focusedFile = file.path }
            ).background(
                PreviewKeyboard(active: focused, preview: openPreview, blurred: { if focused { focusedFile = nil } }))
            VStack(alignment: .trailing, spacing: 4) {
                Text(byteString(file.bytes)).font(.system(size: 10)).monospacedDigit()
                Text(L10n.date(file.modified, time: false)).font(.system(size: 10)).foregroundStyle(Palette.sub)
            }
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
        }.padding(.leading, 44).padding(.trailing, 12).padding(.vertical, 10).background(
            focused ? Palette.mark.opacity(0.5) : .clear
        ).contentShape(Rectangle()).onTapGesture(count: 2) { session.reveal(file) }.contextMenu {
            Button(L10n.text("Быстрый просмотр"), action: openPreview)
            Button(L10n.text("Показать в Finder")) { session.reveal(file) }
            Button(L10n.text("Скопировать путь")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            }
        }
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

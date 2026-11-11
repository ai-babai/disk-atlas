import AtlasCore
import SwiftUI

struct Inspector: View {
    @ObservedObject var store: AtlasStore
    var body: some View {
        if let group = store.inspectedDuplicateGroup {
            DuplicateMapInspector(group: group, focus: store.visibleDuplicateFocus, store: store)
        } else if let group = store.mapGroup, store.selection == nil {
            MapGroupInspector(group: group, parent: store.index?.snapshot.entries[group.parent].path ?? "").id(
                store.language)
        } else {
            entryInspector
        }
    }
    private var entryInspector: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 22) {
                    SectionLabel(text: L10n.text("Подробности"))
                    if let entry = store.selected {
                        selectionHeader(entry)
                        selectionFacts(entry)
                        selectionActions(entry)
                    }
                    if let entry = store.selected, entry.isDirectory {
                        Divider().overlay(Palette.line)
                        FileTypeComposition(store: store, folder: entry).id(entry.id)
                    }
                    Divider().overlay(Palette.line)
                    Text(
                        L10n.text(
                            "APFS может разделять блоки между копиями. Размер здесь не равен гарантированно освобождаемому месту."
                        )
                    ).font(.system(size: 10)).foregroundStyle(Palette.sub).lineSpacing(3)
                }.frame(width: max(0, geometry.size.width - 44), alignment: .leading).padding(22)
            }.clipped()
        }.background(Palette.paper)
    }

    private func selectionHeader(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: entry.kind.symbol).font(.system(size: 29, weight: .light)).foregroundStyle(
                entry.kind.tint
            ).frame(width: 58, height: 58).background(Palette.soft, in: RoundedRectangle(cornerRadius: 13))
            Text(store.name(entry)).font(.system(size: 18, weight: .semibold)).lineLimit(3).truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled).help(store.name(entry))
            Text(store.displayPath(entry)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.sub)
                .lineLimit(3).truncationMode(.middle).fixedSize(horizontal: false, vertical: true).frame(
                    maxWidth: .infinity, alignment: .leading
                ).textSelection(.enabled).help(store.displayPath(entry))
        }
    }
    private func selectionFacts(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 13) {
                if entry.kind != .link, let format = FileFormat.detail(entry.path, directory: entry.isDirectory) {
                    detail(L10n.text("Тип по имени"), value: format)
                }
                detail(L10n.text("На диске"), value: byteString(entry.bytes))
                detail(L10n.text("Размер файлов"), value: byteString(entry.logicalBytes))
                DuplicateSummary(entry: entry, store: store, session: store.duplicates, style: .detail).id(
                    store.language)
                if entry.isDirectory {
                    detail(L10n.text("Файлов"), value: entry.fileCount.formatted())
                    branchFacts(entry)
                }
                if !store.isVirtual(entry) {
                    if let created = entry.created { detail(L10n.text("Создан"), value: L10n.date(created)) }
                    detail(L10n.text("Изменён"), value: L10n.date(entry.modified))
                }
            }
            if entry.sharedLink {
                Text(L10n.text("Жёсткая ссылка. Размер учтён у другого имени этого файла.")).font(.system(size: 10))
                    .foregroundStyle(Palette.sub)
            }
        }
    }
    @ViewBuilder private func branchFacts(_ entry: Entry) -> some View {
        if let facts = store.index?.facts.facts(for: entry.id) {
            detail(L10n.text("Вложенных папок"), value: facts.folders.formatted())
            if facts.cloudMetadataKnown && facts.cloudFiles > 0 {
                detail(L10n.text("Только в облаке"), value: facts.cloudFiles.formatted())
            }
            if facts.partial {
                Label(L10n.text("Папка просканирована не полностью"), systemImage: "exclamationmark.triangle").font(
                    .system(size: 11)
                ).foregroundStyle(Palette.sub).help(
                    L10n.text("Анализ остановлен или часть содержимого недоступна. Размер может быть неполным."))
            }
        }
    }
    private func selectionActions(_ entry: Entry) -> some View {
        VStack(spacing: 8) {
            if entry.isDirectory, entry.id != store.folderID {
                action(L10n.text("Исследовать папку"), icon: "arrow.down.right") { store.navigate(entry.id) }
            }
            if !store.isVirtual(entry) {
                action(L10n.text("Показать в Finder"), icon: "arrow.up.forward.square") { store.reveal(entry) }
                action(L10n.text("Скопировать путь"), icon: "doc.on.doc") { store.copy(entry.path) }
            }
        }
    }

    private func detail(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 10)).foregroundStyle(Palette.sub)
            Spacer(minLength: 0)
            Text(value).font(.system(size: 10, weight: .medium, design: .monospaced)).multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func action(_ title: String, icon: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack {
                Image(systemName: icon).frame(width: 15)
                Text(title)
                Spacer()
            }
        }.buttonStyle(AtlasButtonStyle())
    }
}

struct AgentSheet: View {
    @ObservedObject var store: AtlasStore
    private var command: String { Bundle.main.bundlePath + "/Contents/MacOS/disk-atlas" }
    private var config: String {
        let value = ["mcpServers": ["disk-atlas": ["command": command, "args": ["mcp"]] as [String: Any]]]
        let data = try! JSONSerialization.data(
            withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "terminal").font(.title2).foregroundStyle(Palette.accent)
                Text(L10n.text("Один атлас. Два способа работать.")).font(.system(size: 21, weight: .semibold))
            }
            Text(
                L10n.text(
                    "Ты исследуешь карту. Агент получает те же данные через CLI или MCP и может открыть свой снимок в этом окне."
                )
            ).font(.system(size: 13)).foregroundStyle(Palette.sub).lineSpacing(4)
            SectionLabel(text: "CLI")
            Text(commands).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(15).frame(
                maxWidth: .infinity, alignment: .leading
            ).background(Palette.soft, in: RoundedRectangle(cornerRadius: 9))
            HStack {
                Button(L10n.text("Копировать команды")) { store.copy(commands) }
                Button(L10n.text("Сохранить текущий снимок…")) { store.exportSnapshot() }.disabled(
                    store.snapshot == nil)
            }
            Text(L10n.text("История доступна через history. Справка для агента — disk-atlas schema.")).font(
                .system(size: 12)
            ).foregroundStyle(Palette.sub)
            DisclosureGroup(L10n.text("Подключение MCP")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(config).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(15).frame(
                        maxWidth: .infinity, alignment: .leading
                    ).background(Palette.soft, in: RoundedRectangle(cornerRadius: 9))
                    Button(L10n.text("Копировать конфигурацию")) { store.copy(config) }
                }.padding(.vertical, 4)
            }
            Text(
                L10n.text(
                    "Снимки содержат имена, пути, размеры и даты. Поиск дубликатов читает содержимое только по твоему выбору. Команд удаления нет."
                )
            ).font(.system(size: 11)).foregroundStyle(Palette.sub)
            HStack {
                Spacer()
                Button(L10n.text("Готово")) { store.showAgent = false }.keyboardShortcut(.defaultAction)
            }
        }.padding(30).frame(width: 660).background(Palette.paper).foregroundStyle(Palette.ink)
    }
    private var commands: String {
        let quoted = "'" + command.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return """
            \(quoted) install
            disk-atlas history list --json
            disk-atlas history inspect latest --files --limit 20
            disk-atlas schema inspect
            """
    }
}

import AtlasCore
import QuickLook
import SwiftUI

struct MainView: View {
    @ObservedObject var store: AtlasStore
    @ObservedObject private var duplicateSession: DuplicateSession
    init(store: AtlasStore) {
        self.store = store
        duplicateSession = store.duplicates
    }
    @Environment(\.openWindow) private var openWindow
    @FocusState private var searchFocused: Bool
    @State private var previewURL: URL?
    @State private var previewEntries: [Entry] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if store.snapshot != nil {
                resultPanes
            } else if store.homeReady {
                VStack(spacing: 0) {
                    welcome
                    footer
                }
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.buttonStyle(AtlasButtonStyle()).onChange(of: store.index.map(ObjectIdentifier.init)) { _, _ in
            store.clearDuplicateFocus()
        }.onChange(of: duplicateSession.search) { _, _ in store.clearDuplicateFocus() }.onChange(
            of: duplicateSession.resultFilter
        ) { _, _ in store.clearDuplicateFocus() }.onChange(of: duplicateSession.trashMovedCount) { _, _ in
            store.clearDuplicateFocus()
        }.disabled(store.loadingTitle != nil).background(Palette.paper).foregroundStyle(Palette.ink).tint(
            Palette.accent
        ).overlay {
            if let title = store.loadingTitle {
                SnapshotLoadingView(title: title, stage: store.loadingStage).transition(.opacity)
            }
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: store.loadingTitle).transaction {
            if reduceMotion { $0.animation = nil }
        }.alert(
            L10n.text("Не удалось выполнить действие"),
            isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
        ) {
            Button(L10n.text("Понятно")) { store.error = nil }
        } message: {
            Text(store.error ?? "")
        }.sheet(isPresented: $store.showIssues) { issuesSheet }.sheet(isPresented: $store.showAgent) {
            AgentSheet(store: store)
        }.onChange(of: store.showHistory) { _, show in
            if show {
                openWindow(id: "history")
                store.showHistory = false
            }
        }.onChange(of: store.searchRequest) { _, _ in
            if !store.showDuplicates && !store.duplicateList { searchFocused = true }
        }.sheet(isPresented: $store.showSourcePicker) {
            VStack(alignment: .leading, spacing: 23) {
                Text(L10n.text("Что будем анализировать?")).font(.system(size: 25, weight: .semibold))
                ScanSetup(store: store)
                HStack {
                    Button(L10n.text("Отмена")) { store.showSourcePicker = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                }
            }.padding(30).frame(width: 650).background(Palette.paper).foregroundStyle(Palette.ink)
        }
    }

    private var resultPanes: some View {
        CollapsiblePane(
            isVisible: $store.sidebarVisible, kind: .navigation, pane: Sidebar(store: store),
            content: VStack(spacing: 0) {
                CollapsiblePane(
                    isVisible: Binding(
                        get: { store.inspectorVisible && !store.showDuplicates },
                        set: { if !store.showDuplicates { store.inspectorVisible = $0 } }), kind: .inspector,
                    pane: Inspector(store: store),
                    content: Group {
                        if store.showDuplicates {
                            DuplicatesView(store: store, session: store.duplicates)
                        } else {
                            workspace
                        }
                    })
                footer
            })
    }

    private var displayControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                mapHeading
                Spacer(minLength: 8)
                viewOptions
            }
            VStack(alignment: .leading, spacing: 8) {
                mapHeading
                viewOptions.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
    private var mapHeading: some View {
        HStack {
            SectionLabel(text: L10n.text("Карта папки"))
            Spacer()
            Text(L10n.text("Двойной щелчок — внутрь")).font(.system(size: 10)).foregroundStyle(Palette.sub)
        }
    }
    private var listMode: some View {
        AtlasSegments(
            title: L10n.text("Список файлов"),
            selection: Binding(
                get: { store.duplicateList ? 2 : store.largestFiles ? 1 : 0 },
                set: { mode in
                    if store.duplicateList != (mode == 2) { store.duplicateList = mode == 2 }
                    if mode != 2, store.largestFiles != (mode == 1) { store.largestFiles = mode == 1 }
                }), values: [0, 1, 2], label: { L10n.text(["Содержимое", "Крупные файлы", "Дубликаты"][$0]) }
        ).disabled(duplicateSession.trashing || duplicateSession.trashPreparing)
    }
    private var viewOptions: some View { SizeModeControl(logical: $store.logical).id(store.language) }

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading
            if store.viewFiltersEnabled {
                HStack {
                    Label(
                        L10n.text(store.viewFiltering ? "Применяем фильтр…" : "Фильтр вида"),
                        systemImage: "line.3.horizontal.decrease.circle")
                    Text(
                        "\(store.folder?.fileCount ?? 0) / \(store.snapshot?.entries[store.folderID].fileCount ?? 0) "
                            + L10n.text("файлов"))
                    if store.viewFiltering { ProgressView().controlSize(.mini) }
                    Spacer()
                    Button(L10n.text("Сбросить")) { store.viewFiltersEnabled = false }
                }.font(.system(size: 10)).foregroundStyle(Palette.sub)
            }
            if store.scanning { progressBanner }
            VSplitView {
                VStack(alignment: .leading, spacing: 10) {
                    displayControls.fixedSize(horizontal: false, vertical: true)
                    TreemapView(store: store).frame(minHeight: 120, maxHeight: .infinity)
                    mapLegend.padding(.bottom, 8)
                }.frame(minHeight: 230, idealHeight: 290).background(WorkspaceSplitConfiguration())
                fileList.frame(minHeight: 190, idealHeight: 320).padding(.top, 10)
            }
        }.padding([.top, .horizontal], 24).background {
            Color.clear.contentShape(Rectangle()).onTapGesture { store.clearMapSelection() }
        }.opacity(store.viewFiltering ? 0.65 : 1).animation(
            reduceMotion ? nil : .easeOut(duration: 0.12), value: store.viewFiltering)
    }

    private var mapLegend: some View {
        HStack(spacing: 12) {
            ForEach([FileKind.video, .image, .audio, .document, .archive, .code, .other], id: \.self) { kind in
                HStack(spacing: 4) {
                    Circle().fill(MapPalette.fill(kind)).frame(width: 5, height: 5)
                    Text(kind.title).font(.system(size: 10))
                }.foregroundStyle(Palette.sub)
            }
        }.lineLimit(1).id(store.language)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.folder.map(store.name) ?? L10n.text("Обзор")).font(
                        .system(size: 28, weight: .semibold, design: .rounded)
                    ).lineLimit(1)
                    Text(store.folder.map(store.displayPath) ?? "").font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.sub).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                Spacer()

            }
            ViewThatFits(in: .horizontal) {
                headingMetrics(duplicates: true)
                VStack(alignment: .leading, spacing: 12) {
                    headingMetrics(duplicates: false)
                    if let entry = store.folder {
                        DuplicateSummary(entry: entry, store: store, session: store.duplicates, style: .inline).id(
                            store.language)
                    }
                }
            }
        }
    }

    private func headingMetrics(duplicates: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(byteString(store.folder.map(store.size) ?? 0)).font(
                    .system(size: 33, weight: .medium, design: .rounded)
                ).monospacedDigit().contentTransition(.numericText()).animation(
                    .easeOut(duration: 0.18), value: store.logical)
                Text(store.logical ? L10n.text("размер файлов в папке") : L10n.text("занято файлами в папке")).font(
                    .system(size: 10)
                ).foregroundStyle(Palette.sub)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text((store.folder?.fileCount ?? 0).formatted()).font(
                    .system(size: 20, weight: .medium, design: .rounded)
                ).monospacedDigit()
                Text(L10n.text("файлов")).font(.system(size: 10)).foregroundStyle(Palette.sub)
            }
            if duplicates, let entry = store.folder {
                DuplicateSummary(entry: entry, store: store, session: store.duplicates).id(store.language)
            }
            Spacer(minLength: 0)
            if let snapshot = store.snapshot, !snapshot.isComposite {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(byteString(snapshot.volumeFree)).font(.system(size: 20, weight: .medium, design: .rounded))
                        .monospacedDigit()
                    Text(L10n.text("свободно на томе при сканировании")).font(.system(size: 9)).foregroundStyle(
                        Palette.sub)
                }
            }
        }
    }

    private var fileList: some View {
        ordinaryFileList.opacity(store.duplicateList ? 0 : 1).allowsHitTesting(!store.duplicateList)
            .accessibilityHidden(store.duplicateList).overlay {
                if store.duplicateList {
                    DuplicatesView(
                        store: store, session: store.duplicates, listControls: AnyView(listControlPlaceholder)
                    ).background(Palette.paper)
                }
            }.overlay(alignment: .topLeading) { listSummary }
    }
    // Preserve one mode control across both table bodies: keyboard focus and the sliding pill stay mounted.
    private var listControlPlaceholder: some View {
        listSummary.hidden().accessibilityHidden(true).allowsHitTesting(false)
    }
    private var ordinaryFileList: some View {
        VStack(spacing: 0) {
            fileListHeader
            fileTable.frame(maxHeight: .infinity)
            if !listStatus.isEmpty {
                Text(listStatus).font(.system(size: 10)).foregroundStyle(Palette.sub).frame(height: 18)
            }
        }
    }

    private var listStatus: String {
        if store.rowsLoading { return "" }
        if store.rowCount > 1000 { return L10n.text("Показаны 1 000 объектов. Уточни поиск для остальных.") }
        return store.rows.isEmpty ? L10n.text("Ничего не найдено") : ""
    }

    private var fileListHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    listControlPlaceholder
                    Spacer(minLength: 8)
                    ViewFilterButton(store: store)
                    listSearch.frame(width: 214)
                }
                VStack(alignment: .leading, spacing: 8) {
                    listControlPlaceholder
                    HStack(spacing: 10) {
                        ViewFilterButton(store: store)
                        listSearch
                    }
                }
            }
            HStack(spacing: 8) {
                listSelectionInfo.layoutPriority(1)
                if let group = store.mapGroup { Text(group.title).font(.system(size: 10)).foregroundStyle(Palette.sub) }
                typeSelection
                Spacer(minLength: 4)
                FileTrashControls(session: store.fileTrash, store: store, compact: true).id(store.language).frame(
                    maxWidth: 400, alignment: .trailing)
            }.frame(height: TrashSelectionBar.compactHeight, alignment: .leading)
        }.padding(.bottom, 6)
    }
    @ViewBuilder private var listSelectionInfo: some View {
        if store.hasMapSelection {
            Button {
                store.clearMapSelection()
            } label: {
                Label(L10n.text("Снять выделение"), systemImage: "xmark.circle.fill")
            }.buttonStyle(AtlasButtonStyle()).fixedSize()
        } else if let listHint {
            Text(L10n.text(listHint)).font(.system(size: 10)).foregroundStyle(Palette.sub).lineLimit(1)
        }
    }
    private var listHint: String? {
        if store.largestFiles { return "Файлы во вложенных папках" }
        if !store.query.isEmpty || !store.selectedKinds.isEmpty { return "Результаты фильтра" }
        return nil
    }
    private var listSummary: some View {
        HStack(spacing: 10) {
            listMode
            Text((store.duplicateList ? duplicateSession.orderedCount : store.rowCount).formatted()).font(
                .system(size: 10, design: .monospaced)
            ).foregroundStyle(Palette.sub).frame(width: 74, alignment: .leading)
        }
    }
    @ViewBuilder private var typeSelection: some View {
        if !store.selectedKinds.isEmpty {
            Button {
                store.selectedKinds = []
            } label: {
                HStack(spacing: 4) {
                    Text(
                        store.selectedExtension.map(FileFormat.extensionTitle)
                            ?? (store.selectedKinds.count == 1
                                ? (store.selectedKinds.first?.title ?? "")
                                : L10n.text("Типы: ") + String(store.selectedKinds.count)))
                    Image(systemName: "xmark").font(.system(size: 8))
                }
            }.font(.system(size: 10)).buttonStyle(AtlasButtonStyle()).help(
                store.selectedKinds.map(\.title).sorted().joined(separator: ", ")
            ).accessibilityLabel(L10n.text("Сбросить фильтр типов"))
        }
    }
    private var listSearch: some View {
        HStack(spacing: 6) {
            if store.rowsLoading {
                ProgressView().controlSize(.mini).help(L10n.text("Ищем…"))
            } else {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.sub)
            }
            TextField(L10n.text("Найти файл или папку"), text: $store.query).focused($searchFocused).textFieldStyle(
                .plain
            ).accessibilityLabel(L10n.text("Поиск по имени в текущей папке и вложенных папках"))
            if !store.query.isEmpty {
                Button {
                    store.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }.buttonStyle(.plain)
            }
        }.font(.system(size: 11)).padding(7).background(Palette.soft, in: RoundedRectangle(cornerRadius: 6))
    }

    private var fileTable: some View {
        let rows = store.rows
        return FileTable(
            trash: store.fileTrash, reviewTrash: { store.reviewFileTrash([$0]) }, trashEnabled: !store.historyBusy,
            rows: rows, index: store.index, folderID: store.folderID,
            hierarchical: !store.largestFiles && store.query.isEmpty && store.selectedKinds.isEmpty,
            logical: store.logical, folderBytes: store.folder.map(store.size) ?? 0, revision: store.rowRevision,
            language: store.language,
            showPaths: store.largestFiles || !store.query.isEmpty || !store.selectedKinds.isEmpty,
            contextID: store.mapContextID, showCreationDate: rows.contains { $0.created != nil }, sort: store.sort,
            descending: store.sortDescending, sortBy: store.sortBy,
            duplicates: store.duplicates.snapshotCreated == store.snapshot?.created ? store.duplicates.lookup : nil,
            showDuplicates: store.showDuplicateGroup, scrollRequest: store.rowsLoading ? 0 : store.rowScrollRequest,
            selection: $store.selection, open: store.activate, reveal: store.reveal, copyPath: store.copy,
            preview: preview
        ).opacity(store.rowsLoading ? 0.5 : 1).disabled(store.rowsLoading).animation(
            reduceMotion ? nil : .easeOut(duration: 0.12), value: store.rowsLoading
        ).quickLookPreview($previewURL, in: previewEntries.map { URL(fileURLWithPath: $0.path) }).onChange(
            of: previewURL
        ) { _, url in selectPreview(url) }.onChange(of: store.selection) { _, _ in updatePreview() }.onChange(
            of: store.rowRevision
        ) { _, _ in updatePreview() }.onDisappear { previewURL = nil }
    }

    private func preview(_ entry: Entry, entries: [Entry]) {
        previewEntries = entries
        let url = URL(fileURLWithPath: entry.path)
        previewURL = previewURL == url ? nil : url
    }

    private func selectPreview(_ url: URL?) {
        guard let url, let entry = previewEntries.first(where: { $0.path == url.path }) else { return }
        store.selection = entry.id
    }

    private func updatePreview() {
        guard previewURL != nil else { return }
        previewURL = previewEntries.first(where: { $0.id == store.selection }).map { URL(fileURLWithPath: $0.path) }
    }

    private var progressBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text("Сканирование…")).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(L10n.text("\(store.progressCount.formatted()) объектов · \(byteString(store.progressBytes))"))
                    .font(.system(size: 10, design: .monospaced))
            }
            ProgressView().progressViewStyle(.linear)

        }.padding(12).background(Palette.soft, in: RoundedRectangle(cornerRadius: 8))
    }

    private var welcome: some View {
        GeometryReader { geometry in
            ScrollView { welcomeContent.frame(minHeight: geometry.size.height) }.scrollBounceBehavior(.basedOnSize)
        }
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            HStack(spacing: 12) {
                AtlasMark()
                Text("Disk Atlas").font(.system(size: 20, weight: .semibold))
                Spacer()
            }.padding(.bottom, 3)
            Group {
                if let volume = store.startupVolume {
                    VolumeOverview(volume: volume).id(store.language)
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }.frame(maxWidth: 620, alignment: .leading).frame(height: 28)
            Text(store.scanning ? L10n.text("Собираем карту файлов.") : L10n.text("Что будем анализировать?")).font(
                .system(size: 31, weight: .medium, design: .rounded)
            ).tracking(-0.5)
            if store.scanning {
                progressBanner.frame(maxWidth: 620)
                Button(L10n.text("Остановить анализ")) { store.cancel() }.buttonStyle(AtlasButtonStyle())
            } else {
                HStack(alignment: .top, spacing: 26) {
                    VStack(alignment: .leading, spacing: 24) {
                        ScanSetup(store: store)
                        Button(L10n.text("Открыть сохранённый снимок…")) { store.importSnapshot() }.buttonStyle(
                            AtlasButtonStyle()
                        ).foregroundStyle(Palette.accent).font(.system(size: 12))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if !store.historyRecords.isEmpty { RecentScans(store: store).frame(width: 250) }
                }

            }
            Spacer()
            HStack(spacing: 25) {
                Label(L10n.text("Без облака"), systemImage: "internaldrive")
                Label(L10n.text("Файлы не изменяются"), systemImage: "lock.shield")
                Label("CLI + MCP", systemImage: "terminal")
            }.font(.system(size: 11)).foregroundStyle(Palette.sub).padding(.bottom, 32)
        }.task { await store.refreshStartupVolume() }.frame(
            maxWidth: store.historyRecords.isEmpty || store.scanning ? 650 : 960, alignment: .leading
        ).padding(.horizontal, 32).frame(maxWidth: .infinity)
    }

    private var footer: some View { WorkspaceStatusBar(store: store, session: store.duplicates) }

    private var issuesSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("Что не удалось прочитать")).font(.title2.weight(.semibold))
            Text(
                L10n.text(
                    "Недоступные папки не входят в итог. Для защищённых папок macOS может потребоваться полный доступ к диску в Системных настройках."
                )
            ).font(.callout).foregroundStyle(Palette.sub)
            FileAccessHelpButton().id(store.language)
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(Array((store.snapshot?.issues ?? []).enumerated()), id: \.offset) { _, issue in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(issue.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            Text(L10n.text(issue.message)).font(.system(size: 11)).foregroundStyle(Palette.sub)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text(L10n.text("Сохранены первые 200 сообщений")).font(.caption).foregroundStyle(Palette.sub)
                Spacer()
                Button(L10n.text("Готово")) { store.showIssues = false }.keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 620, height: 450).background(Palette.paper)
    }
}

import AtlasCore
import QuickLook
import SwiftUI

struct MainView: View {
    @ObservedObject var store: AtlasStore
    @State private var previewURL: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if store.snapshot != nil {
                resultPanes
            } else {
                VStack(spacing: 0) {
                    welcome
                    footer
                }
            }
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
        }.sheet(isPresented: $store.showHistory) { HistorySheet(store: store) }.sheet(
            isPresented: $store.showSourcePicker
        ) {
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
                mapMode
                Spacer(minLength: 8)
                viewOptions
            }
            VStack(alignment: .leading, spacing: 8) {
                mapMode
                viewOptions.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
    private var mapMode: some View {
        Picker(L10n.text("Отображение"), selection: $store.largestFiles) {
            Text(L10n.text("Карта")).tag(false)
            Text(L10n.text("Крупные файлы")).tag(true)
        }.pickerStyle(.segmented).labelsHidden().frame(width: 166)
    }
    private var viewOptions: some View {
        HStack(spacing: 8) {
            ViewFilterButton(store: store)
            SizeModeControl(logical: $store.logical).id(store.language)
        }
    }

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading
            displayControls
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
            if !store.largestFiles {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionLabel(text: L10n.text("Карта папки"))
                        Spacer()
                        Text(L10n.text("Двойной щелчок — внутрь")).font(.system(size: 10)).foregroundStyle(Palette.sub)
                    }
                    TreemapView(store: store).frame(minHeight: 150, idealHeight: 300, maxHeight: .infinity)
                    HStack(spacing: 13) {
                        ForEach([FileKind.video, .image, .audio, .document, .archive, .code, .other], id: \.self) {
                            kind in
                            HStack(spacing: 4) {
                                Circle().fill(kind.tint).frame(width: 5, height: 5)
                                Text(kind.title).font(.system(size: 9))
                            }.foregroundStyle(Palette.sub)
                        }
                    }.lineLimit(1).id(store.language)
                }
            }
            fileList
        }.padding(24).opacity(store.viewFiltering ? 0.65 : 1).animation(
            reduceMotion ? nil : .easeOut(duration: 0.12), value: store.viewFiltering)
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
                        DuplicateSummary(entry: entry, store: store, session: store.duplicates, style: .inline)
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
                DuplicateSummary(entry: entry, store: store, session: store.duplicates)
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
        VStack(spacing: 0) {
            fileListHeader
            fileTable
            if store.rowCount > 1000 {
                Text(L10n.text("Показаны 1 000 объектов. Уточни поиск для остальных.")).font(.system(size: 10))
                    .foregroundStyle(Palette.sub).padding(.top, 5)
            }
            if store.rows.isEmpty {
                Text(L10n.text("Ничего не найдено")).font(.system(size: 11)).foregroundStyle(Palette.sub).padding(8)
            }
        }
    }

    private var fileListHeader: some View {
        HStack(spacing: 10) {
            SectionLabel(text: store.largestFiles ? L10n.text("Крупные файлы") : L10n.text("Содержимое"))
            Text("\(store.rowCount)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.sub)
            if !store.selectedKinds.isEmpty {
                Button {
                    store.selectedKinds = []
                } label: {
                    HStack(spacing: 4) {
                        Text(
                            store.selectedKinds.count == 1
                                ? (store.selectedKinds.first?.title ?? "")
                                : L10n.text("Типы: ") + String(store.selectedKinds.count))
                        Image(systemName: "xmark").font(.system(size: 8))
                    }
                }.font(.system(size: 10)).buttonStyle(.bordered).help(
                    store.selectedKinds.map(\.title).sorted().joined(separator: ", ")
                ).accessibilityLabel(L10n.text("Сбросить фильтр типов"))
            }
            Spacer()
            HStack(spacing: 6) {
                if store.rowsLoading {
                    ProgressView().controlSize(.mini).help(L10n.text("Ищем…"))
                } else {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.sub)
                }
                TextField(L10n.text("Найти файл или папку"), text: $store.query).textFieldStyle(.plain)
                    .accessibilityLabel(L10n.text("Поиск по имени в текущей папке и вложенных папках"))
                if !store.query.isEmpty {
                    Button {
                        store.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }.buttonStyle(.plain)
                }
            }.font(.system(size: 11)).padding(7).frame(width: 214).background(
                Palette.soft, in: RoundedRectangle(cornerRadius: 6))
        }.padding(.bottom, 11)
    }

    private var fileTable: some View {
        let rows = store.rows
        return FileTable(
            rows: rows, logical: store.logical, folderBytes: store.folder.map(store.size) ?? 0,
            revision: store.rowRevision, language: store.language,
            showPaths: store.largestFiles || !store.query.isEmpty || !store.selectedKinds.isEmpty,
            contextID: store.mapContextID, showCreationDate: rows.contains { $0.created != nil }, sort: store.sort,
            descending: store.sortDescending, sortBy: store.sortBy,
            duplicates: store.duplicates.snapshotCreated == store.snapshot?.created ? store.duplicates.lookup : nil,
            showDuplicates: store.showDuplicateGroup, scrollRequest: store.rowsLoading ? 0 : store.rowScrollRequest,
            selection: $store.selection, open: store.activate, reveal: store.reveal, copyPath: store.copy,
            preview: preview
        ).frame(
            minHeight: store.largestFiles ? 260 : 130, idealHeight: store.largestFiles ? 600 : 210,
            maxHeight: store.largestFiles ? .infinity : 245
        ).opacity(store.rowsLoading ? 0.5 : 1).disabled(store.rowsLoading).animation(
            reduceMotion ? nil : .easeOut(duration: 0.12), value: store.rowsLoading
        ).quickLookPreview($previewURL, in: rows.map { URL(fileURLWithPath: $0.path) }).onChange(of: previewURL) {
            _, url in selectPreview(url)
        }.onChange(of: store.selection) { _, _ in updatePreview() }.onChange(of: store.rowRevision) { _, _ in
            updatePreview()
        }.onDisappear { previewURL = nil }
    }

    private func preview(_ entry: Entry) {
        let url = URL(fileURLWithPath: entry.path)
        previewURL = previewURL == url ? nil : url
    }

    private func selectPreview(_ url: URL?) {
        guard let url, let entry = store.rows.first(where: { $0.path == url.path }) else { return }
        store.selection = entry.id
    }

    private func updatePreview() {
        guard previewURL != nil else { return }
        previewURL = store.rows.first(where: { $0.id == store.selection }).map { URL(fileURLWithPath: $0.path) }
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
            Text(L10n.text("Снимок") + " ≈ " + byteString(store.progressMetadataBytes) + " · " + L10n.text("до сжатия"))
                .font(.system(size: 10)).monospacedDigit().foregroundStyle(Palette.sub).help(
                    L10n.text("Оценка несжатых метаданных. После сохранения появится точный размер сжатого снимка."))
            Text(store.progressPath).font(.system(size: 9, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(Palette.sub)
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
                Menu {
                    Button(L10n.text("Как в системе")) { store.appearance = "system" }
                    Button(L10n.text("Светлая")) { store.appearance = "light" }
                    Button(L10n.text("Тёмная")) { store.appearance = "dark" }
                } label: {
                    Image(systemName: "circle.lefthalf.filled")
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 28, height: 28).help(
                    L10n.text("Оформление"))
            }.padding(.bottom, 3)
            if let volume = store.startupVolume { VolumeOverview(volume: volume) }
            Text(store.scanning ? L10n.text("Собираем карту файлов.") : L10n.text("Что будем анализировать?")).font(
                .system(size: 31, weight: .medium, design: .rounded)
            ).tracking(-0.5)
            if store.scanning {
                progressBanner.frame(maxWidth: 620)
                Button(L10n.text("Остановить анализ")) { store.cancel() }.buttonStyle(.bordered)
            } else {
                HStack(alignment: .top, spacing: 26) {
                    VStack(alignment: .leading, spacing: 24) {
                        ScanSetup(store: store)
                        Button(L10n.text("Открыть сохранённый снимок…")) { store.importSnapshot() }.buttonStyle(.plain)
                            .foregroundStyle(Palette.accent).font(.system(size: 12))
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

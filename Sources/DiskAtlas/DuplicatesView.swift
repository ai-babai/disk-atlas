import AtlasCore
import SwiftUI

struct DuplicatesView: View {
    @ObservedObject var store: AtlasStore
    @ObservedObject var session: DuplicateSession
    var listControls: AnyView? = nil
    private var embedded: Bool { listControls != nil }
    @FocusState private var searchFocused: Bool
    @AppStorage("atlas.column.created") private var createdVisible = true
    @AppStorage("atlas.column.modified") private var modifiedVisible = true
    private var columns: DuplicateTableColumns {
        DuplicateTableColumns(created: createdVisible, modified: modifiedVisible)
    }
    @State private var parameters = false
    @State private var expanded = Set<String>()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var settings: Binding<DuplicateOptions> {
        Binding(
            get: { session.hasResultContext ? session.resultFilter : session.options },
            set: { value in
                if session.hasResultContext {
                    session.resultFilter = value
                } else {
                    session.options = value
                    store.prepareDuplicates(debounce: true)
                }
            })
    }
    private var visibleGroups: [DuplicateGroup] {
        var result = session.orderedGroups
        if let id = session.focusedGroupID, !result.contains(where: { $0.id == id }),
            let group = session.lookup?.groups[id]
        {
            result.insert(group, at: 0)
        }
        return result
    }
    var body: some View {
        VStack(spacing: 0) {
            if embedded { embeddedHeader }
            resultViewport
        }.onChange(of: store.searchRequest) { _, _ in searchFocused = true }.background(Palette.paper).sheet(
            item: $session.trashReview
        ) { plan in
            DuplicateTrashReview(plan: plan, cancel: { session.trashReview = nil }, confirm: { session.trash(plan) })
        }.sheet(isPresented: $store.showDuplicateSearch) {
            NewDuplicateCheckSheet(
                title: store.snapshot.map {
                    $0.scanRoots.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: " + ")
                } ?? session.title, options: session.hasResultContext ? session.resultFilter : session.options,
                confirm: store.prepareDuplicateCheck)
        }
    }
    @ViewBuilder private var resultViewport: some View { if embedded { embeddedViewport } else { fullViewport } }
    private var embeddedViewport: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    if !visibleGroups.isEmpty { groupTableHeader }
                    ScrollViewReader { reader in
                        ScrollView(.vertical) { reportContent.frame(maxWidth: .infinity, alignment: .topLeading) }
                            .onAppear { focus(reader) }.onChange(of: session.focusedGroupID) { _, _ in focus(reader) }
                    }
                }.frame(
                    width: max(visibleGroups.isEmpty ? 0 : columns.minimumWidth, geometry.size.width),
                    height: geometry.size.height)
            }
        }
    }
    private var fullViewport: some View {
        GeometryReader { geometry in
            ScrollViewReader { reader in
                ScrollView([.vertical, .horizontal]) {
                    reportContent.frame(
                        width: max(visibleGroups.isEmpty ? 0 : columns.minimumWidth, geometry.size.width - 48),
                        alignment: .leading
                    ).frame(minHeight: max(0, geometry.size.height - 48), alignment: .topLeading).padding(24)
                }.onAppear { focus(reader) }.onChange(of: session.focusedGroupID) { _, _ in focus(reader) }
            }
        }
    }
    private var reportContent: some View {
        VStack(alignment: .leading, spacing: embedded ? 12 : 20) {
            if !embedded { header }
            errorBanner
            scopeSwitch
            // Existing rows stay in place; ongoing work already has the fixed footer/header indicators.
            if !embedded || (visibleGroups.isEmpty && session.report == nil) { status }
            coverageNotice
            if !embedded {
                HStack(spacing: 8) {
                    parametersButton
                    resultSearch
                    Spacer(minLength: 0)
                }
                activeFilters
                trashSelectionBar
            }
            results
            if !embedded { reportFooter }
        }
    }
    private var embeddedHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    listControls
                    Spacer(minLength: 8)
                    parametersButton
                    resultSearch.frame(width: 214)
                }
                VStack(alignment: .leading, spacing: 8) {
                    listControls
                    HStack {
                        parametersButton
                        resultSearch
                        Spacer(minLength: 0)
                    }
                }
            }
            activeFilters
            HStack {
                if let focus = store.visibleDuplicateFocus {
                    DuplicateMapSelectionInfo(focus: focus, store: store)
                } else if store.duplicateFocusLoading {
                    HStack(spacing: 8) {
                        DelayedActivity(active: true, title: L10n.text("Готовим подсветку…"))
                        Text(L10n.text("Готовим подсветку…")).font(.system(size: 10)).foregroundStyle(Palette.sub)
                        Button {
                            store.clearDuplicateFocus()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }.buttonStyle(.plain).help(L10n.text("Остановить")).accessibilityLabel(L10n.text("Остановить"))
                    }
                }
                Spacer(minLength: 0)
                trashSelectionBar.frame(maxWidth: 400, alignment: .trailing)
            }.frame(height: TrashSelectionBar.compactHeight)
        }.padding(.bottom, 6)
    }
    @ViewBuilder private var errorBanner: some View {
        if let error = session.error {
            Label(L10n.text(error), systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(
                .orange
            ).textSelection(.enabled)
        }
    }
    @ViewBuilder private var scopeSwitch: some View {
        if session.snapshotCreated != store.snapshot?.created {
            HStack {
                Text(session.title).lineLimit(1)
                Spacer()
                Button(L10n.text("Искать в текущем снимке")) { selectCurrentScope() }.disabled(session.busy)
            }.font(.system(size: 11))
        }
    }
    private func selectCurrentScope() {
        if let snapshot = store.snapshot { session.select(snapshot, id: store.activeHistoryID, prepareIfMissing: true) }
    }
    @ViewBuilder private var results: some View {
        if !visibleGroups.isEmpty {
            Group { if embedded { groupRows } else { groupTable } }.id(store.language)
            if session.hasMoreResults {
                HStack {
                    Text("\(session.orderedGroups.count.formatted()) / \(session.orderedCount.formatted())").font(
                        .system(size: 11)
                    ).monospacedDigit().foregroundStyle(Palette.sub)
                    Button(L10n.text("Показать ещё 500 групп")) { session.loadMoreResults() }.disabled(session.sorting)
                }
            }
        } else if session.sorting {
            ProgressView(L10n.text("Фильтруем результаты…")).font(.system(size: 11)).padding(.vertical, 24)
        } else if session.report != nil {
            emptyResults
        }
    }
    private var resultSearch: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.sub)
            TextField(L10n.text("Найти по имени или пути"), text: $session.search).textFieldStyle(.plain).focused(
                $searchFocused
            ).accessibilityLabel(L10n.text("Поиск среди всех групп дубликатов"))
            if !session.search.isEmpty {
                Button {
                    session.search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }.buttonStyle(.plain)
            }
        }.font(.system(size: embedded ? 11 : 12)).padding(embedded ? 7 : 8).frame(maxWidth: 360).background(
            Palette.soft, in: RoundedRectangle(cornerRadius: 6)
        ).disabled(!session.canFilterResults)
    }
    @ViewBuilder private var activeFilters: some View {
        if session.hasResultContext && session.resultFilterActive {
            HStack(spacing: 8) {
                Text(filterSummary).font(.system(size: 11)).foregroundStyle(Palette.sub).lineLimit(1).truncationMode(
                    .middle
                ).help(filterSummary)
                Button(L10n.text("Сбросить")) { session.resultFilter = DuplicateOptions() }.buttonStyle(
                    AtlasButtonStyle())
            }.disabled(!session.canFilterResults)
        }
    }
    private var filterSummary: String {
        let options = session.resultFilter
        var parts = FileKind.allCases.filter { options.kinds.contains($0) }.map(\.title)
        if options.minimumBytes > 0 || options.maximumBytes != nil { parts.append(L10n.text("Размер")) }
        if options.modifiedAfter != nil || options.modifiedBefore != nil { parts.append(L10n.text("Изменён")) }
        return parts.joined(separator: " · ")
    }
    private var emptyResults: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                emptyResultTitle,
                systemImage: session.resultFilterActive ? "line.3.horizontal.decrease.circle" : "checkmark.circle")
            if session.resultFilterActive {
                Button(L10n.text("Сбросить фильтры")) { session.resultFilter = DuplicateOptions() }
            }
        }
    }
    private var emptyResultTitle: String {
        if session.resultFilterActive || !session.search.isEmpty { return L10n.text("Нет групп по этим фильтрам") }
        if session.report?.cancelled == true || session.report?.inputPartial == true {
            return L10n.text("Совпадения ещё не подтверждены")
        }
        return L10n.text("Совпадений не найдено")
    }
    @ViewBuilder private var coverageNotice: some View {
        if session.limitedCoverage {
            HStack {
                Text(L10n.text("Показаны только проверенные файлы")).foregroundStyle(Palette.sub)
                Button(L10n.text("Расширить проверку…")) { store.showDuplicateSearch = true }.buttonStyle(.plain)
                    .disabled(session.busy)
            }.font(.system(size: 10))
        }
    }
    private var groupTable: some View {
        VStack(spacing: 0) {
            groupTableHeader
            groupRows
        }
    }
    private var groupRows: some View { LazyVStack(spacing: 0) { ForEach(visibleGroups) { group in groupRow(group) } } }
    private var groupTableHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: FileListMetrics.checkWidth)
                sortHeading("Имя", key: .name).padding(
                    .leading, 24 + FileListMetrics.iconWidth + FileListMetrics.iconTextSpacing
                ).frame(minWidth: DuplicateTableColumns.nameWidth, maxWidth: .infinity, alignment: .leading)
                if columns.created { dateHeading("Создан") }
                if columns.modified { dateHeading("Изменён") }
                sortHeading("Копии", key: .copies).frame(width: DuplicateTableColumns.copiesWidth, alignment: .trailing)
                sortHeading("Повторы", key: .repeatedBytes).padding(.horizontal, 6).frame(
                    width: FileListMetrics.sizeWidth, alignment: .trailing
                ).help(
                    L10n.text(
                        "Повторный объём не равен гарантированно освобождаемому месту: APFS может разделять блоки."))
                DelayedActivity(active: session.sorting, title: L10n.text("Фильтруем результаты…")).frame(
                    width: DuplicateTableColumns.actionsWidth, height: 16)
            }.font(Font(FileListMetrics.headerFont)).foregroundStyle(Palette.sub).padding(.horizontal, 8).frame(
                height: FileListMetrics.headerHeight)
            Divider().overlay(Palette.line)
        }
    }
    private func dateHeading(_ label: String) -> some View {
        Text(L10n.text(label)).padding(.horizontal, 6).frame(width: FileListMetrics.dateWidth, alignment: .leading)
    }
    private func groupRow(_ group: DuplicateGroup) -> some View {
        DuplicateGroupRow(
            group: group, session: session,
            expanded: Binding(get: { expanded.contains(group.id) }, set: { setExpanded(group.id, value: $0) }),
            columns: columns, select: embedded ? { store.focusDuplicateGroup(group) } : nil,
            selected: embedded && store.duplicateSelectionID == group.id && store.duplicateSelectedFile == nil,
            selectedPath: embedded ? store.duplicateSelectedFile?.path : nil,
            selectFile: embedded ? { store.focusDuplicateFile($0, in: group) } : nil
        ).id(group.id)
    }
    private func setExpanded(_ id: String, value: Bool) {
        if value { expanded.insert(id) } else { expanded.remove(id) }
    }
    private var trashSelectionBar: some View {
        TrashSelectionBar(
            count: session.trashSelection.paths.count, bytes: session.trashSelection.bytes,
            sizeHelp: L10n.text(
                "Размер содержимого всех выбранных копий. APFS может разделять блоки; это не гарантированно освобождаемое место."
            ), busy: session.trashPreparing || session.trashing, notice: session.trashNotice,
            clear: { session.trashSelection = DuplicateTrashSelection() }, review: { session.reviewTrash() },
            stop: session.stop, compact: embedded
        ).id(store.language).disabled(session.busy && !session.trashPreparing && !session.trashing)
    }
    @ViewBuilder private var reportFooter: some View {
        if let report = session.report {
            HStack(spacing: 12) {
                Text(L10n.text("Проверено: ") + L10n.date(report.checkedAt))
                if session.metadataBytes == 0 { Text(L10n.text("Отчёт не сохранён")) }
                Spacer()
                if report.skipped > 0 {
                    Menu(L10n.text("Пропущено: ") + "\(report.skipped)") {
                        ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
                            Text(issue.path + " · " + L10n.text(issue.message))
                        }
                    }.menuStyle(.borderlessButton).fixedSize()
                }
            }.font(.system(size: 10)).foregroundStyle(Palette.sub)
        }
    }
    private func focus(_ reader: ScrollViewProxy) {
        guard let id = session.focusedGroupID else { return }
        expanded.insert(id)
        Task { @MainActor in
            await Task.yield()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { reader.scrollTo(id, anchor: .top) }
        }
    }
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text("Дубликаты")).font(.system(size: 26, weight: .semibold, design: .rounded))
                Text(session.scopePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? session.title).font(
                    .system(size: 11)
                ).foregroundStyle(Palette.sub).lineLimit(1).help(
                    (session.snapshotCreated.map { L10n.text("По снимку от ") + L10n.date($0) } ?? "") + "\n"
                        + L10n.text(
                            "Новые файлы после снимка попадут в поиск после повторного анализа. Облачные файлы без локального содержимого пропускаются."
                        ))
            }
            Spacer()
            headerActions
        }
    }
    private var headerActions: some View {
        HStack(alignment: .center, spacing: 8) {
            if session.scopePath != nil {
                Button {
                    session.scopePath = nil
                } label: {
                    Label(L10n.text("Все группы"), systemImage: "chevron.left").font(.system(size: 11)).padding(
                        .horizontal, 8
                    ).frame(height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).help(L10n.text("Все группы"))
            }
        }.lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }
    private var parametersButton: some View {
        tool(
            session.hasResultContext ? "line.3.horizontal.decrease" : "slider.horizontal.3",
            session.hasResultContext ? "Фильтры" : "Параметры",
            disabled: session.hasResultContext ? !session.canFilterResults : !session.canChangeOptions,
            active: session.hasResultContext && session.resultFilterActive
        ) { parameters.toggle() }.popover(isPresented: $parameters) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L10n.text(session.hasResultContext ? "Фильтры результатов" : "Параметры поиска")).font(
                        .system(size: 14, weight: .semibold))
                    Spacer()
                    if session.hasResultContext && session.resultFilterActive {
                        Button(L10n.text("Сбросить")) { session.resultFilter = DuplicateOptions() }.buttonStyle(.plain)
                            .font(.system(size: 10))
                    }
                }
                DuplicateOptionsControls(options: settings)
                if session.hasResultContext {
                    if !session.resultFilter.kinds.isEmpty {
                        Text(L10n.text("Все копии совпавшего файла остаются в группе.")).font(.system(size: 10))
                            .foregroundStyle(Palette.sub)
                    }
                    Divider()
                    HStack {
                        Text(L10n.text("По сохранённой проверке")).font(.system(size: 10)).foregroundStyle(Palette.sub)
                        Spacer()
                        Button(L10n.text("Новая проверка…")) {
                            parameters = false
                            store.showDuplicateSearch = true
                        }.buttonStyle(.plain).font(.system(size: 10)).disabled(session.busy)
                    }
                }
            }.padding(20).frame(width: 360).background(Palette.paper)
        }
    }

    private func sortHeading(_ label: String, key: DuplicateSort) -> some View {
        Button {
            session.sortBy(key)
        } label: {
            Text(L10n.text(label) + (session.sort == key ? (session.sortDescending ? " ↓" : " ↑") : "")).frame(
                maxWidth: .infinity, alignment: key == .name ? .leading : .trailing
            ).contentShape(Rectangle())
        }.buttonStyle(.plain).help(L10n.text("Сортировка") + ": " + key.title)
    }
    private func tool(
        _ icon: String, _ label: String, disabled: Bool, active: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) { Label(L10n.text(label), systemImage: icon) }.buttonStyle(
            AtlasButtonStyle(emphasized: active)
        ).disabled(disabled).help(L10n.text(label)).accessibilityLabel(L10n.text(label))
    }
    @ViewBuilder private var status: some View {
        if session.trashing || session.trashPreparing || session.preparing || session.loadingReport
            || session.savingReport
        {
            workingStatus
        } else if session.running {
            runningStatus
        } else if let report = session.report {
            finishedStatus(report)
        } else if let plan = session.plan {
            readyStatus(plan)
        } else {
            Button(L10n.text("Оценить проверку")) { store.prepareDuplicates() }
        }
    }
    private var workingStatus: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(session.phaseTitle)
                Spacer()
                Button(L10n.text("Остановить")) { session.stop() }
            }
            if session.trashing && session.trashProgress.total > 0 {
                ProgressView(value: Double(session.trashProgress.completed), total: Double(session.trashProgress.total))
            }
        }.font(.system(size: 11)).foregroundStyle(Palette.sub).padding(.vertical, 10)
    }
    private var runningStatus: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(session.phaseTitle)
                Spacer()
                Text(session.remaining ?? session.estimate).foregroundStyle(Palette.sub)
            }
            if session.progress.phaseTotal > 0 {
                ProgressView(value: session.fraction).animation(
                    reduceMotion ? nil : .linear(duration: Motion.quick), value: session.fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            HStack {
                Text(byteString(session.progress.phaseBytes) + " / " + byteString(session.progress.phaseTotal))
                Spacer()
                if session.progress.metadataBytes > 0 {
                    Text(L10n.text("Отчёт") + " ≈ " + byteString(session.progress.metadataBytes))
                }
                Text(L10n.text("Групп: ") + "\(session.groups.count)")
            }.font(.system(size: 10)).foregroundStyle(Palette.sub).monospacedDigit()
        }.font(.system(size: 12)).padding(.vertical, 6)
    }
    private func finishedStatus(_ report: DuplicateReport) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text(byteString(session.orderedRepeatedBytes)).font(
                    .system(size: 28, weight: .medium, design: .rounded)
                ).monospacedDigit()
                Text(L10n.text("повторных копий")).font(.system(size: 10)).foregroundStyle(Palette.sub)
            }.help(
                L10n.text("Повторный объём не равен гарантированно освобождаемому месту: APFS может разделять блоки."))
            VStack(alignment: .leading, spacing: 5) {
                Text("\(session.orderedCount)").font(.system(size: 22, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Text(L10n.text("групп")).font(.system(size: 10)).foregroundStyle(Palette.sub)
            }
            Spacer()
            DelayedActivity(active: session.sorting, title: L10n.text("Фильтруем результаты…"))
            if report.cancelled || report.inputPartial == true {
                Label(L10n.text("Неполный результат"), systemImage: "stop.circle").font(.system(size: 10))
                    .foregroundStyle(Palette.sub)
            }
        }.padding(.vertical, 4)
    }
    @ViewBuilder private func readyStatus(_ plan: DuplicatePlan) -> some View {
        if plan.candidateCount == 0 {
            Label(L10n.text("Нет кандидатов для сравнения"), systemImage: "checkmark.circle").font(.system(size: 12))
                .foregroundStyle(Palette.sub)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(plan.candidateCount.formatted()) " + L10n.text("файлов")).font(
                        .system(size: 20, weight: .medium, design: .rounded))
                    Spacer()
                    Label(session.estimate, systemImage: "clock").font(.system(size: 12)).foregroundStyle(Palette.sub)
                }
                HStack {
                    Text(L10n.text("До ") + byteString(plan.estimatedReadBytes) + L10n.text(" чтения")).font(
                        .system(size: 10)
                    ).foregroundStyle(Palette.sub).help(
                        L10n.text(
                            "Оценка грубая: зависит от диска и совпадений. Это чтение содержимого; файлы не изменяются."
                        ))
                    Spacer()
                    Button(L10n.text("Начать проверку"), systemImage: "play.fill") { session.start() }.buttonStyle(
                        AtlasButtonStyle(emphasized: true)
                    ).disabled(
                        plan.candidateCount == 0 || store.savingHistory > 0 || store.scanning || store.preparing
                            || store.viewFiltering)
                }
            }.padding(16).background(Palette.soft, in: RoundedRectangle(cornerRadius: 8))
        }
    }

}

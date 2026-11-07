import AtlasCore
import SwiftUI

struct DuplicatesView: View {
    @ObservedObject var store: AtlasStore
    @ObservedObject var session: DuplicateSession
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
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    errorBanner
                    scopeSwitch
                    status
                    coverageNotice
                    trashSelectionBar
                    results
                    reportFooter
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }.onAppear { focus(reader) }.onChange(of: session.focusedGroupID) { _, _ in focus(reader) }
        }.animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: session.sorting).background(Palette.paper)
            .sheet(item: $session.trashReview) { plan in
                DuplicateTrashReview(
                    plan: plan, cancel: { session.trashReview = nil }, confirm: { session.trash(plan) })
            }.sheet(isPresented: $store.showDuplicateSearch) {
                NewDuplicateCheckSheet(
                    title: store.snapshot.map {
                        $0.scanRoots.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: " + ")
                    } ?? session.title, options: session.hasResultContext ? session.resultFilter : session.options,
                    confirm: store.prepareDuplicateCheck)
            }
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
            groupTable.opacity(session.sorting ? 0.5 : 1).allowsHitTesting(!session.sorting)
            if session.orderedCount > 500 {
                Text(L10n.text("Показаны первые 500 групп. Полный результат доступен в экспорте.")).font(
                    .system(size: 10)
                ).foregroundStyle(Palette.sub)
            }
        } else if session.sorting {
            ProgressView(L10n.text("Фильтруем результаты…")).font(.system(size: 11)).padding(.vertical, 24)
        } else if session.report != nil {
            emptyResults
        }
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
        if session.resultFilterActive { return L10n.text("Нет групп по этим фильтрам") }
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
            HStack(spacing: 12) {
                sortHeading("Файлы", key: .name).padding(.leading, 70)
                Spacer()
                if session.sorting { ProgressView().controlSize(.mini) }
                sortHeading("Копии", key: .copies).frame(width: 52, alignment: .trailing)
                sortHeading("Повторы", key: .repeatedBytes).frame(width: 100, alignment: .trailing).help(
                    L10n.text(
                        "Повторный объём не равен гарантированно освобождаемому месту: APFS может разделять блоки."))
                Color.clear.frame(width: 24)
            }.font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.sub).padding(.horizontal, 12).padding(
                .bottom, 10)
            Divider().overlay(Palette.line)
            LazyVStack(spacing: 0) { ForEach(visibleGroups) { group in groupRow(group) } }
        }
    }
    private func groupRow(_ group: DuplicateGroup) -> some View {
        DuplicateGroupRow(
            group: group, session: session,
            expanded: Binding(get: { expanded.contains(group.id) }, set: { setExpanded(group.id, value: $0) })
        ).id(group.id)
    }
    private func setExpanded(_ id: String, value: Bool) {
        if value { expanded.insert(id) } else { expanded.remove(id) }
    }
    @ViewBuilder private var trashSelectionBar: some View {
        if !session.trashSelection.paths.isEmpty {
            HStack(spacing: 12) {
                Text(L10n.text("Выбрано: ") + String(session.trashSelection.paths.count)).monospacedDigit()
                Button(L10n.text("Снять выбор")) { session.trashSelection = DuplicateTrashSelection() }.buttonStyle(
                    .plain)
                Spacer()
                Button(L10n.text("В корзину…"), systemImage: "trash") { session.reviewTrash() }.buttonStyle(
                    .borderedProminent)
            }.font(.system(size: 11)).padding(12).background(Palette.soft, in: RoundedRectangle(cornerRadius: 8))
                .disabled(session.busy)
        }
        if let notice = session.trashNotice { Text(notice).font(.system(size: 11)).foregroundStyle(Palette.sub) }
    }
    @ViewBuilder private var reportFooter: some View {
        if let report = session.report {
            HStack(spacing: 12) {
                Text(L10n.text("Проверено: ") + L10n.date(report.checkedAt))
                Text(
                    session.metadataBytes > 0
                        ? L10n.text("Отчёт") + " " + byteString(session.metadataBytes) : L10n.text("Отчёт не сохранён"))
                Spacer()
                if report.skipped > 0 {
                    Menu(L10n.text("Пропущено: ") + "\(report.skipped)") {
                        ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
                            Text(issue.path + " · " + L10n.text(issue.message))
                        }
                    }.menuStyle(.borderlessButton).fixedSize()
                }
            }.font(.system(size: 9)).foregroundStyle(Palette.sub)
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
            parametersButton
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
        Button(action: action) {
            Label(L10n.text(label), systemImage: icon).font(.system(size: 11)).padding(.horizontal, 10).frame(
                height: 28
            ).foregroundStyle(active ? Palette.accent : Palette.ink).background(
                active ? Palette.mark : Palette.soft, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).disabled(disabled).help(L10n.text(label)).accessibilityLabel(L10n.text(label))
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
                Button(L10n.text("Остановить")) { session.stop() }.disabled(session.savingReport)
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
                    reduceMotion ? nil : .linear(duration: 0.16), value: session.fraction)
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
            }.font(.system(size: 9)).foregroundStyle(Palette.sub).monospacedDigit()
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
            if session.sorting { ProgressView().controlSize(.small).help(L10n.text("Фильтруем результаты…")) }
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
                        .borderedProminent
                    ).disabled(
                        plan.candidateCount == 0 || store.savingHistory > 0 || store.scanning || store.preparing
                            || store.viewFiltering)
                }
            }.padding(16).background(Palette.soft, in: RoundedRectangle(cornerRadius: 8))
        }
    }

}

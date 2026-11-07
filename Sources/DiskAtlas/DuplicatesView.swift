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
            get: { session.options },
            set: { value in
                session.options = value
                if !session.running { store.prepareDuplicates(debounce: true) }
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
                    trashSelectionBar
                    results
                    reportFooter
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }.onAppear { focus(reader) }.onChange(of: session.focusedGroupID) { _, _ in focus(reader) }
        }.background(Palette.paper).sheet(item: $session.trashReview) { plan in
            DuplicateTrashReview(plan: plan, cancel: { session.trashReview = nil }, confirm: { session.trash(plan) })
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
        if !session.groups.isEmpty {
            groupTable
            if session.orderedCount > 500 {
                Text(L10n.text("Показаны первые 500 групп. Полный результат доступен в экспорте.")).font(
                    .system(size: 10)
                ).foregroundStyle(Palette.sub)
            }
        } else if session.report != nil {
            ContentUnavailableView(
                L10n.text(
                    session.report?.cancelled == true ? "Совпадения ещё не подтверждены" : "Совпадений не найдено"),
                systemImage: session.report?.cancelled == true ? "stop.circle" : "checkmark.circle")
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
            if session.scopePath != nil {
                Button(L10n.text("Все группы")) { session.scopePath = nil }.font(.system(size: 11)).buttonStyle(.plain)
            }
            tool("slider.horizontal.3", "Параметры", disabled: !session.canChangeOptions) { parameters.toggle() }
                .popover(isPresented: $parameters) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L10n.text("Параметры поиска")).font(.system(size: 14, weight: .semibold))
                        FileSizeRange(options: settings)
                        HStack(spacing: 6) {
                            ForEach([FileKind.video, .image, .audio, .document, .archive, .code, .other], id: \.self) {
                                kind in
                                Button {
                                    var value = session.options
                                    if value.kinds.contains(kind) {
                                        value.kinds.remove(kind)
                                    } else {
                                        value.kinds.insert(kind)
                                    }
                                    settings.wrappedValue = value
                                } label: {
                                    Image(systemName: kind.symbol).frame(width: 28, height: 26).foregroundStyle(
                                        session.options.kinds.contains(kind) ? Palette.accent : Palette.sub
                                    ).background(
                                        session.options.kinds.contains(kind) ? Palette.mark : Palette.soft,
                                        in: RoundedRectangle(cornerRadius: 5))
                                }.buttonStyle(.plain).help(kind.title).accessibilityLabel(kind.title)
                                    .accessibilityAddTraits(session.options.kinds.contains(kind) ? .isSelected : [])
                            }
                            Spacer(minLength: 0)
                            Button(L10n.text("Все")) {
                                var value = session.options
                                value.kinds = []
                                settings.wrappedValue = value
                            }.buttonStyle(.plain).font(.system(size: 10))
                        }
                    }.padding(20).frame(width: 360).background(Palette.paper)
                }
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
    private func tool(_ icon: String, _ label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(L10n.text(label), systemImage: icon).font(.system(size: 11)).padding(.horizontal, 10).frame(
                height: 28
            ).background(Palette.soft, in: RoundedRectangle(cornerRadius: 6))
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
                Text(byteString(session.scopePath == nil ? report.repeatedBytes : session.orderedRepeatedBytes)).font(
                    .system(size: 28, weight: .medium, design: .rounded)
                ).monospacedDigit()
                Text(L10n.text("повторных копий")).font(.system(size: 10)).foregroundStyle(Palette.sub)
            }.help(
                L10n.text("Повторный объём не равен гарантированно освобождаемому месту: APFS может разделять блоки."))
            VStack(alignment: .leading, spacing: 5) {
                Text("\(session.scopePath == nil ? report.groups.count : session.orderedCount)").font(
                    .system(size: 22, weight: .medium, design: .rounded)
                ).monospacedDigit()
                Text(L10n.text("групп")).font(.system(size: 10)).foregroundStyle(Palette.sub)
            }
            Spacer()
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

struct DuplicateActivity: View {
    @ObservedObject var store: AtlasStore
    @ObservedObject var session: DuplicateSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if !session.roots.isEmpty && (session.busy || session.plan != nil || session.report != nil)
            && (!store.showDuplicates || session.running)
        {
            HStack(spacing: 10) {
                if session.busy && !session.paused && !session.foregroundPaused {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: session.report == nil ? "doc.on.doc" : "checkmark.circle").foregroundStyle(
                        Palette.accent)
                }
                Button {
                    store.showDuplicates = true
                } label: {
                    HStack(spacing: 7) {
                        Text(L10n.text("Дубликаты") + " · " + session.title).lineLimit(1).truncationMode(.middle)
                        if session.busy {
                            Text(session.phaseTitle).lineLimit(1)
                        } else if let report = session.report {
                            Text(L10n.text("Групп: ") + "\(report.groups.count)")
                        } else {
                            Text(session.estimate)
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
                if session.running {
                    Text(session.remaining ?? session.estimate).font(.system(size: 9)).lineLimit(1)
                    if session.progress.phaseTotal > 0 {
                        ProgressView(value: session.fraction).frame(width: 56).animation(
                            reduceMotion ? nil : .linear(duration: 0.16), value: session.fraction)
                    }
                    Button {
                        session.togglePause()
                    } label: {
                        Image(systemName: session.paused ? "play.fill" : "pause.fill")
                    }.help(L10n.text(session.paused ? "Продолжить" : "Пауза")).disabled(session.foregroundPaused)
                }
                if session.busy && !session.savingReport {
                    Button {
                        session.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                    }.help(L10n.text("Остановить"))
                } else {
                    Button(L10n.text("Показать")) { store.showDuplicates = true }.buttonStyle(.plain).foregroundStyle(
                        Palette.accent)
                }
            }.font(.system(size: 10)).foregroundStyle(Palette.sub).padding(.horizontal, 24).frame(height: 34)
                .background(Palette.soft).overlay(alignment: .top) { Divider().overlay(Palette.line) }
        }
    }
}

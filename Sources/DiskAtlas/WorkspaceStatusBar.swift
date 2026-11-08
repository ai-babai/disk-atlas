import AtlasCore
import SwiftUI

/// One stable-height footer. A job's result link and controls stay beside its status.
struct WorkspaceStatusBar: View {
    @ObservedObject var store: AtlasStore
    @ObservedObject var session: DuplicateSession
    private var showsDuplicates: Bool {
        !session.roots.isEmpty && (session.busy || session.plan != nil || session.report != nil)
            && (store.snapshot != nil || session.busy) && (!store.showDuplicates || session.running)
    }
    var body: some View {
        HStack(spacing: 12) {
            ScanStatus(store: store)
            if showsDuplicates {
                Rectangle().fill(Palette.line).frame(width: 1, height: 12)
                DuplicateActivity(store: store, session: session).layoutPriority(1)
            }
            Spacer(minLength: 0)
            if let notice = session.trashNotice ?? store.notice {
                Text(notice).lineLimit(1).truncationMode(.tail).help(notice).layoutPriority(-2)
            }
        }.font(.system(size: 10)).monospacedDigit().foregroundStyle(Palette.sub).padding(.horizontal, 16).frame(
            height: 30
        ).background(Palette.soft).overlay(alignment: .top) { Divider().overlay(Palette.line) }
    }
}

private struct ScanStatus: View {
    @ObservedObject var store: AtlasStore
    var body: some View {
        HStack(spacing: 7) {
            if store.preparing || store.savingHistory > 0 {
                ProgressView().controlSize(.mini)
            } else {
                Circle().fill(store.scanning ? Color.orange : Palette.accent).frame(width: 5, height: 5)
            }
            Text(title).lineLimit(1)
            if let snapshot = store.snapshot, snapshot.issueCount > 0 {
                Button(L10n.text("Пропущено: \(snapshot.issueCount)")) { store.showIssues = true }.buttonStyle(.plain)
                    .foregroundStyle(.orange)
            }
        }
    }
    private var title: String {
        if store.preparing { return L10n.text("Подготовка снимка…") }
        if store.scanning { return L10n.text("Сканирование") }
        if store.savingHistory > 0 { return L10n.text("Сохранение истории…") }
        guard let snapshot = store.snapshot else { return L10n.text("Готово к сканированию") }
        return snapshot.cancelled
            ? L10n.text("Остановлено · неполный снимок")
            : L10n.text("Анализ · \(String(format: "%.2f", snapshot.elapsed)) с")
    }
}

private struct DuplicateActivity: View {
    @ObservedObject var store: AtlasStore
    @ObservedObject var session: DuplicateSession
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 8) {
            Button {
                store.showDuplicateActivity()
            } label: {
                HStack(spacing: 6) {
                    activityIcon
                    Text(L10n.text("Дубликаты")).fixedSize()
                    if session.roots != store.snapshot?.scanRoots {
                        Text(session.title).lineLimit(1).truncationMode(.middle)
                    }
                    Text(detail).lineLimit(1).truncationMode(.tail)
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                }.padding(.horizontal, 6).frame(height: 24).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(Palette.accent).background(
                Palette.accent.opacity(hovered ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 5)
            ).onHover { hovered = $0 }.help(L10n.text("Открыть результаты поиска дубликатов") + " · " + session.title)
                .accessibilityLabel(L10n.text("Дубликаты") + " · " + detail).animation(
                    reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            DuplicateActivityControls(session: session)
        }
    }
    private var detail: String {
        if session.busy { return session.phaseTitle }
        if let report = session.report {
            let count = L10n.text("Групп: ") + "\(report.groups.count)"
            return report.cancelled ? L10n.text("Остановлено") + " · " + count : count
        }
        return session.estimate
    }
    @ViewBuilder private var activityIcon: some View {
        if session.busy && !session.paused && !session.foregroundPaused {
            ProgressView().controlSize(.mini).accessibilityHidden(true)
        } else {
            Image(systemName: "doc.on.doc")
        }
    }
}

private struct DuplicateActivityControls: View {
    @ObservedObject var session: DuplicateSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if session.running {
            if session.progress.phaseTotal > 0 {
                ProgressView(value: session.fraction).controlSize(.mini).frame(width: 48).animation(
                    reduceMotion ? nil : .linear(duration: Motion.quick), value: session.fraction)
            }
            Button {
                session.togglePause()
            } label: {
                Image(systemName: session.paused ? "play.fill" : "pause.fill").frame(width: 24, height: 24)
            }.buttonStyle(.borderless).help(L10n.text(session.paused ? "Продолжить" : "Пауза")).accessibilityLabel(
                L10n.text(session.paused ? "Продолжить" : "Пауза")
            ).disabled(session.foregroundPaused)
        }
        if session.busy {
            Button {
                session.stop()
            } label: {
                Image(systemName: "stop.fill").frame(width: 24, height: 24)
            }.buttonStyle(.borderless).help(L10n.text("Остановить")).accessibilityLabel(L10n.text("Остановить"))
        }
    }
}

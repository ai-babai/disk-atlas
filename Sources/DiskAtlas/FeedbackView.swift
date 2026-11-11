import AtlasCore
import SwiftUI

struct FeedbackView: View {
    @ObservedObject var model: FeedbackModel
    @Environment(\.dismissWindow) private var dismissWindow
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L10n.text("Обратная связь"), systemImage: "ladybug").font(.system(size: 22, weight: .semibold))
            if model.sent {
                Label(L10n.text("Спасибо! Сообщение отправлено."), systemImage: "checkmark.circle").foregroundStyle(
                    Palette.accent
                ).padding(.vertical, 24)
                HStack {
                    Button(L10n.text("Написать ещё")) {
                        model.writeAnother()
                        focused = true
                    }
                    Spacer()
                    close
                }
            } else {
                form
                if let error = model.error {
                    Text(error).font(.system(size: 11)).foregroundStyle(Palette.destructive).accessibilityLabel(error)
                        .textSelection(.enabled)
                }
                HStack {
                    if model.sending {
                        ProgressView().controlSize(.small)
                        Button(L10n.text("Остановить")) { model.cancel() }
                    } else {
                        close
                    }
                    Spacer()
                    Button(L10n.text("Отправить")) { model.send() }.buttonStyle(AtlasButtonStyle(emphasized: true))
                        .keyboardShortcut(.return, modifiers: .command).disabled(
                            model.sending || model.validation != nil)
                }
            }
        }.padding(24).frame(width: 520).fixedSize(horizontal: false, vertical: true).background(Palette.paper)
            .foregroundStyle(Palette.ink).navigationTitle(L10n.text("Обратная связь")).onAppear { focused = true }
    }
    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            AtlasSegments(
                title: L10n.text("Тип обращения"), selection: $model.kind, values: ["bug", "idea"],
                label: { L10n.text($0 == "bug" ? "Ошибка" : "Предложение") })
            Text(L10n.text("Что произошло или что можно улучшить?")).font(.system(size: 12))
            TextEditor(text: $model.message).font(.system(size: 12)).scrollContentBackground(.hidden).padding(8).frame(
                height: 136
            ).background(Palette.soft, in: RoundedRectangle(cornerRadius: 6)).overlay {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line)
            }.focused($focused).accessibilityLabel(L10n.text("Сообщение"))
            if model.length >= 3687 {
                Text("\(model.length) / 4096").font(.system(size: 10)).monospacedDigit().foregroundStyle(
                    model.length > 4096 ? Palette.destructive : Palette.sub)
            }
            if model.length > 4096 {
                Text(L10n.text("Сократи сообщение до 4096 символов.")).font(.system(size: 10)).foregroundStyle(
                    Palette.destructive)
            }
            TextField(L10n.text("Почта для ответа — необязательно"), text: $model.email).textFieldStyle(.roundedBorder)
                .accessibilityLabel(L10n.text("Почта для ответа — необязательно"))
            if !model.email.isEmpty, let validation = model.validation, model.length <= 4096,
                !model.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                Text(validation).font(.system(size: 10)).foregroundStyle(Palette.destructive)
            }
            AtlasRowToggle(
                state: model.includeDiagnostics ? .on : .off, label: L10n.text("Приложить версию приложения и macOS"),
                showsLabel: true
            ) { model.includeDiagnostics.toggle() }.fixedSize(horizontal: true, vertical: false).frame(height: 24)
            if model.includeDiagnostics {
                Text(model.diagnostics).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.sub)
                    .textSelection(.enabled)
            }
            Text(
                L10n.text(
                    "Сообщение и указанная почта отправятся в Sentry (США). Файлы, пути и снимки автоматически не прикладываются."
                )
            ).font(.system(size: 10)).foregroundStyle(Palette.sub).fixedSize(horizontal: false, vertical: true)
            Link(L10n.text("Приватность Sentry"), destination: URL(string: "https://sentry.io/privacy/")!).font(
                .system(size: 10))
        }.disabled(model.sending)
    }
    private var close: some View {
        Button(L10n.text("Закрыть")) { dismissWindow(id: "feedback") }.keyboardShortcut(.cancelAction)
    }
}

import AtlasCore
import SwiftUI
import UniformTypeIdentifiers

struct FeedbackView: View {
    @ObservedObject var model: FeedbackModel
    @ObservedObject var store: AtlasStore
    @ObservedObject private var diagnostics = AppDiagnostics.shared
    @State private var choosingImage = false
    @State private var formHeight: CGFloat = 360
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
                ScrollView {
                    form.background {
                        GeometryReader { geometry in
                            Color.clear.onAppear { formHeight = ceil(geometry.size.height) }.onChange(
                                of: geometry.size.height
                            ) { _, height in formHeight = ceil(height) }
                        }
                    }
                }.frame(height: min(460, formHeight))
                if let error = model.error {
                    Text(error).font(.system(size: 11)).foregroundStyle(Palette.destructive).accessibilityLabel(error)
                        .textSelection(.enabled)
                }
                HStack {
                    if model.sending || model.loadingAttachment {
                        ProgressView().controlSize(.small)
                        Button(L10n.text("Остановить")) { model.cancel() }
                    } else {
                        close
                    }
                    Spacer()
                    Button(L10n.text("Отправить")) { model.send(diagnostics: details) }.buttonStyle(
                        AtlasButtonStyle(emphasized: true)
                    ).keyboardShortcut(.return, modifiers: .command).disabled(
                        model.sending || model.loadingAttachment || model.validation != nil)
                }
            }
        }.padding(24).frame(width: 520).fixedSize(horizontal: false, vertical: true).background(Palette.paper)
            .foregroundStyle(Palette.ink).navigationTitle(L10n.text("Обратная связь")).onAppear { focused = true }
            .fileImporter(isPresented: $choosingImage, allowedContentTypes: [.png, .jpeg], onCompletion: imported)
    }
    private func imported(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url): model.attach(url)
        case .failure(let error): if (error as NSError).code != NSUserCancelledError { model.attachmentFailed() }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            AtlasSegments(
                title: L10n.text("Тип обращения"), selection: $model.kind, values: ["bug", "idea"],
                label: { L10n.text($0 == "bug" ? "Ошибка" : "Предложение") })
            Text(L10n.text("Что произошло или что можно улучшить?")).font(.system(size: 12))
            TextEditor(text: $model.message).font(.system(size: 12)).scrollContentBackground(.hidden).padding(8).frame(
                height: 112
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
            HStack(spacing: 12) {
                TextField(L10n.text("Почта для ответа — необязательно"), text: $model.email).textFieldStyle(
                    .roundedBorder
                ).accessibilityLabel(L10n.text("Почта для ответа — необязательно"))
                Button {
                    choosingImage = true
                } label: {
                    Label(L10n.text("Прикрепить"), systemImage: "paperclip")
                }.help(L10n.text("Выбрать скриншот PNG или JPEG"))
            }
            if !model.email.isEmpty, let validation = model.validation, model.length <= 4096,
                !model.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                Text(validation).font(.system(size: 10)).foregroundStyle(Palette.destructive)
            }
            if let attachment = model.attachment, let image = NSImage(data: attachment.data) {
                HStack(spacing: 12) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 160, height: 112).background(
                        Palette.soft, in: RoundedRectangle(cornerRadius: 6)
                    ).accessibilityLabel(L10n.text("Предпросмотр скриншота"))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("Скриншот")).font(.system(size: 12))
                        Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))
                            .font(.system(size: 10)).foregroundStyle(Palette.sub)
                        Button(L10n.text("Удалить вложение")) { model.removeAttachment() }
                    }
                    Spacer(minLength: 0)
                }
                Text(L10n.text("Проверь, что на изображении нет личных данных.")).font(.system(size: 10))
                    .foregroundStyle(Palette.sub)
            }
            DisclosureGroup(L10n.text("Технические сведения")) {
                Text(details.description).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(
                    maxWidth: .infinity, alignment: .leading
                ).padding(.top, 8)
            }.font(.system(size: 11))
            Text(details.summary).font(.system(size: 10)).foregroundStyle(Palette.sub)
            Text(
                L10n.text(
                    "В Sentry (США) отправятся сообщение, указанная почта, технические сведения и выбранное изображение. Пути и файлы анализа не прикладываются."
                )
            ).font(.system(size: 10)).foregroundStyle(Palette.sub).fixedSize(horizontal: false, vertical: true)
            Link(L10n.text("Приватность Sentry"), destination: URL(string: "https://sentry.io/privacy/")!).font(
                .system(size: 10))
        }.disabled(model.sending || model.loadingAttachment)
    }
    private var details: ReportDiagnostics {
        let screen: ReportDiagnostics.Screen
        if store.showDuplicates {
            screen = .duplicateOverview
        } else if store.snapshot == nil {
            screen = .home
        } else if store.duplicateList {
            screen = .duplicates
        } else {
            screen = store.largestFiles ? .largest : .contents
        }
        return diagnostics.report(screen: screen)
    }
    private var close: some View {
        Button(L10n.text("Закрыть")) { dismissWindow(id: "feedback") }.keyboardShortcut(.cancelAction)
    }
}

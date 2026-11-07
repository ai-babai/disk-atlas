import AtlasCore
import SwiftUI

struct DuplicateOptionsControls: View {
    @Binding var options: DuplicateOptions
    private let kinds: [FileKind] = [.video, .image, .audio, .document, .archive, .code, .other]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FileSizeRange(options: $options)
            HStack {
                Text(L10n.text("Типы")).font(.system(size: 10)).foregroundStyle(Palette.sub)
                Spacer()
                Button(L10n.text("Все")) { options.kinds = [] }.buttonStyle(.plain).font(.system(size: 10)).disabled(
                    options.kinds.isEmpty)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
                ForEach(kinds, id: \.self) { kind in kindButton(kind) }
            }
        }
    }
    private func kindButton(_ kind: FileKind) -> some View {
        let selected = options.kinds.contains(kind)
        return Button {
            if selected { options.kinds.remove(kind) } else { options.kinds.insert(kind) }
        } label: {
            Label(kind.title, systemImage: kind.symbol).font(.system(size: 10)).lineLimit(1).frame(
                maxWidth: .infinity, alignment: .leading
            ).padding(.horizontal, 9).frame(height: 28).foregroundStyle(selected ? Palette.accent : Palette.sub)
                .background(selected ? Palette.mark : Palette.soft, in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct NewDuplicateCheckSheet: View {
    let title: String
    let confirm: (DuplicateOptions) -> Void
    @State private var options: DuplicateOptions
    @Environment(\.dismiss) private var dismiss
    init(title: String, options: DuplicateOptions, confirm: @escaping (DuplicateOptions) -> Void) {
        self.title = title
        self.confirm = confirm
        _options = State(initialValue: options)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("Новая проверка")).font(.system(size: 21, weight: .semibold))
            Text(title).font(.system(size: 11)).foregroundStyle(Palette.sub).lineLimit(1)
            DuplicateOptionsControls(options: $options)
            Text(L10n.text("Сначала оценим время. Чтение файлов — только после запуска.")).font(.system(size: 10))
                .foregroundStyle(Palette.sub)
            HStack {
                Button(L10n.text("Отмена")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.text("Оценить время")) { confirm(options) }.keyboardShortcut(.defaultAction).buttonStyle(
                    .borderedProminent)
            }
        }.padding(24).frame(width: 410).background(Palette.paper).foregroundStyle(Palette.ink)
    }
}

import AtlasCore
import SwiftUI

struct FileTypeComposition: View {
    @ObservedObject var store: AtlasStore
    @State private var expanded: FileKind?
    @State private var values: [ExtensionTotal] = []
    @State private var loading = false
    private var request: String {
        let identity = store.index.map { String(describing: ObjectIdentifier($0)) } ?? ""
        return "\(identity)-\(store.folderID)-\(store.logical)-\(expanded?.rawValue ?? "")"
    }
    var body: some View {
        let kinds = store.index?.totals(of: store.folderID, logical: store.logical) ?? []
        let total = max(1, kinds.reduce(Int64(0)) { $0 + $1.bytes })
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: L10n.text("Типы в папке"))
                Spacer()
                if !store.selectedKinds.isEmpty {
                    Button(L10n.text("Все")) { store.selectedKinds = [] }.font(.system(size: 10)).buttonStyle(.plain)
                }
            }
            Text(L10n.text("Фильтр списка") + " · " + (store.folder.map(store.name) ?? "")).font(.system(size: 10))
                .foregroundStyle(Palette.sub).lineLimit(1).truncationMode(.middle).help(store.folder?.path ?? "")
            ForEach(kinds, id: \.kind) { item in
                VStack(spacing: 4) {
                    category(item, total: total)
                    if expanded == item.kind {
                        if loading { ProgressView().controlSize(.mini) }
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(values) { value in extensionRow(value, kind: item.kind) }
                        }
                    }
                }
            }
            if kinds.isEmpty { Text(L10n.text("В папке пока нет файлов")).font(.caption).foregroundStyle(Palette.sub) }
        }.task(id: request) { await loadExtensions() }
    }
    private func category(_ item: KindTotal, total: Int64) -> some View {
        HStack(spacing: 0) {
            Button {
                expanded = expanded == item.kind ? nil : item.kind
            } label: {
                Image(systemName: expanded == item.kind ? "chevron.down" : "chevron.right").font(
                    .system(size: 10, weight: .medium)
                ).frame(width: 20, height: 36).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(Palette.sub).accessibilityLabel(
                L10n.text("Расширения") + ": " + item.kind.title
            ).accessibilityValue(L10n.text(expanded == item.kind ? "Развёрнуто" : "Свёрнуто")).help(
                L10n.text("Показать расширения файлов"))
            Button {
                store.toggleKind(item.kind)
            } label: {
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(
                            systemName: store.selectedKinds.contains(item.kind)
                                ? "checkmark.circle.fill" : "circle.fill"
                        ).font(.system(size: store.selectedKinds.contains(item.kind) ? 10 : 6)).foregroundStyle(
                            store.selectedKinds.contains(item.kind) ? Palette.accent : MapPalette.fill(item.kind)
                        ).frame(width: 12)
                        Text(item.kind.title).font(.system(size: 11)).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 4)
                        Text(byteString(item.bytes)).font(.system(size: 10, design: .monospaced)).foregroundStyle(
                            Palette.sub
                        ).fixedSize()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.soft)
                            Capsule().fill(MapPalette.fill(item.kind)).frame(
                                width: max(2, geo.size.width * Double(item.bytes) / Double(total)))
                        }
                    }.frame(height: 3)
                }.padding(4).frame(minHeight: 36).background(
                    store.selectedKinds.contains(item.kind) ? Palette.mark : .clear,
                    in: RoundedRectangle(cornerRadius: 4)
                ).contentShape(Rectangle())
            }.buttonStyle(.plain).help(L10n.text("Фильтр: \(item.kind.title)")).accessibilityAddTraits(
                store.selectedKinds.contains(item.kind) ? .isSelected : [])
        }
    }
    private func extensionRow(_ value: ExtensionTotal, kind: FileKind) -> some View {
        let selected = store.selectedKinds == [kind] && store.selectedExtension == value.suffix
        return Button {
            store.selectExtension(value.suffix, kind: kind)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(FileFormat.extensionTitle(value.suffix)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(byteString(value.bytes)).font(.system(size: 10, design: .monospaced)).fixedSize()
                }.font(.system(size: 11))
                Text(L10n.text("Файлов: ") + value.count.formatted()).font(.system(size: 10)).foregroundStyle(
                    Palette.sub)
            }.padding(4).frame(maxWidth: .infinity, alignment: .leading).background(
                selected ? Palette.mark : .clear, in: RoundedRectangle(cornerRadius: 4)
            ).contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.leading, 20).help(
            FileFormat.detail("file." + value.suffix) ?? FileFormat.extensionTitle(value.suffix)
        ).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func loadExtensions() async {
        values = []
        guard let kind = expanded, let index = store.index else {
            loading = false
            return
        }
        loading = true
        let folder = store.folderID
        let logical = store.logical
        let worker = Task.detached(priority: .userInitiated) {
            index.extensions(of: folder, kind: kind, logical: logical)
        }
        let result = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard !Task.isCancelled else { return }
        values = result
        loading = false
    }
}

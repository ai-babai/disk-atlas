import SwiftUI
import AtlasCore
import UniformTypeIdentifiers

struct ScanSetup: View {
    @ObservedObject var store: AtlasStore
    @State private var targeted = false
    private let places: [(String, String, String)] = [
        (L10n.text("Загрузки"), "arrow.down.circle", "Downloads"),
        (L10n.text("Рабочий стол"), "desktopcomputer", "Desktop"),
        (L10n.text("Документы"), "doc.text", "Documents"),
        (L10n.text("Изображения"), "photo", "Pictures"),
        (L10n.text("Видео"), "film", "Movies"),
        (L10n.text("Музыка"), "music.note", "Music")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("Добавь одну или несколько папок. Затем запусти анализ."))
                .font(.system(size: 13)).foregroundStyle(Palette.sub)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 10) {
                ForEach(places, id: \.0) { place in
                    quick(place.0, icon: place.1, path: NSHomeDirectory() + "/" + place.2)
                }
                quick(L10n.text("Домашняя папка"), icon: "house", path: NSHomeDirectory())
                quick(L10n.text("Приложения"), icon: "app.dashed", path: "/Applications")
                quick(L10n.text("Весь диск Mac"), icon: "internaldrive", path: "/System/Volumes/Data")
            }
            VStack(spacing: 10) {
                if store.pendingPaths.isEmpty {
                    VStack(spacing: 11) {
                        Image(systemName: "tray.and.arrow.down").font(.system(size: 30, weight: .light)).foregroundStyle(Palette.accent)
                        Text(L10n.text("Перетащи сюда папки")).font(.system(size: 16, weight: .medium))
                        Text(L10n.text("или добавь их кнопкой ниже")).font(.system(size: 11)).foregroundStyle(Palette.sub)
                    }.frame(maxWidth: .infinity).frame(height: 135)
                } else {
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(store.pendingPaths, id: \.self) { path in selectedRow(path) }
                        }.padding(8)
                    }.frame(height: 145)
                }
                HStack {
                    Button(L10n.text("Добавить папки…"), systemImage: "folder.badge.plus") { store.chooseFolder() }
                    Button(L10n.text("Другой диск…"), systemImage: "externaldrive") { store.chooseFolder(volume: true) }
                    Spacer()
                    if !store.pendingPaths.isEmpty {
                        Text(L10n.text("Выбрано: \(store.pendingPaths.count)")).font(.system(size: 10)).foregroundStyle(Palette.sub)
                    }
                }.controlSize(.small).padding(.horizontal, 14).padding(.bottom, 14)
            }
            .background(targeted ? Palette.mark : Palette.soft, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(targeted ? Palette.accent : Palette.line, style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: store.pendingPaths.isEmpty ? [5, 4] : [])))
            .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in store.addSelection(url) }
                    }
                }
                return true
            }
            VStack(alignment: .leading, spacing: 7) {
                Toggle(L10n.text("Найти дубликаты"), isOn: $store.prepareDuplicateSearch)
                    .font(.system(size: 11)).disabled(store.duplicates.busy)
                if store.prepareDuplicateSearch {
                    Text(L10n.text("Долгая проверка содержимого. Сначала — оценка времени."))
                        .font(.system(size: 10)).foregroundStyle(Palette.sub).fixedSize(horizontal: false, vertical: true)
                    DuplicateStartOptions(session: store.duplicates)
                }
            }
            HStack(spacing: 16) {
                Button(L10n.text("Анализировать"), systemImage: "chart.pie") { store.analyzeSelection() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(store.pendingPaths.isEmpty || store.scanning)
                Text(L10n.text("Включая вложенные папки · без повторного подсчёта\nФайлы не изменяются"))
                    .font(.system(size: 10)).foregroundStyle(Palette.sub).lineSpacing(3)
            }
        }
    }

    private func quick(_ title: String, icon: String, path: String) -> some View {
        Button { store.addSelection(URL(fileURLWithPath: path)) } label: {
            Label(title, systemImage: icon).font(.system(size: 11)).foregroundStyle(Palette.accent)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
        }.buttonStyle(.plain).help(path)
    }

    private func selectedRow(_ path: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: path == "/System/Volumes/Data" ? "internaldrive" : "folder").foregroundStyle(Palette.accent).font(.system(size: 20))
            VStack(alignment: .leading, spacing: 3) {
                Text(path == "/System/Volumes/Data" ? L10n.text("Весь диск Mac · данные") : URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(path).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.sub).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button { store.pendingPaths.removeAll { $0 == path } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.sub) }
                .buttonStyle(.plain).help(L10n.text("Убрать из анализа")).accessibilityLabel(L10n.text("Убрать \(path) из анализа"))
        }.padding(9).background(Palette.paper, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct DuplicateStartOptions: View {
    @ObservedObject var session: DuplicateSession
    var body: some View {
        DisclosureGroup(L10n.text("Размер и дата")) { FileCriteria(options: $session.options).frame(maxWidth: 420).padding(.top, 12) }
            .font(.system(size: 11)).disabled(session.busy)
    }
}

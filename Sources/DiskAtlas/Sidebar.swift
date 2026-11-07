import SwiftUI
import AtlasCore

struct Sidebar: View {
    @ObservedObject var store: AtlasStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                AtlasMark()
                VStack(alignment: .leading, spacing: 1) {
                    Text("Disk Atlas").font(.system(size: 17, weight: .semibold))
                    Text(L10n.text("Место для важного")).font(.system(size: 10)).foregroundStyle(Palette.sub)
                }
            }.padding(.top, 20).padding(.bottom, 24)
            ScrollView {
              VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: L10n.text("Обзор")).padding(.bottom, 12)
            nav(L10n.text("Карта пространства"), symbol: "square.grid.2x2", active: !store.largestFiles) { store.largestFiles = false; store.selectedKinds = [] }
            nav(L10n.text("Крупные файлы"), symbol: "line.3.horizontal.decrease", active: store.largestFiles) { store.largestFiles = true; store.selectedKinds = [] }
            if let snapshot = store.snapshot {
                SectionLabel(text: L10n.text("В этом анализе")).padding(.top, 31).padding(.bottom, 12)
                let roots = snapshot.isComposite ? snapshot.rootEntry.children.map { snapshot.entries[$0] } : [snapshot.rootEntry]
                ForEach(roots) { entry in
                    nav(entry.name, symbol: "folder", active: store.folderID == entry.id) { store.navigate(entry.id) }
                }
                HStack {
                    SectionLabel(text: L10n.text("История сканов"))
                    Spacer()
                    if store.savingHistory > 0 { ProgressView().controlSize(.mini) }
                    Menu {
                        Button(L10n.text("Вся история…")) { store.showHistory = true }
                        Divider()
                        Button(L10n.text("Очистить историю…"), role: .destructive) { store.requestHistoryDeletion() }
                            .disabled(store.historyBusy || (store.historyRecords.isEmpty && store.historyStorageBytes == 0))
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel(L10n.text("Действия с историей"))
                }.padding(.top, 24).padding(.bottom, 8)
                ForEach(store.historyRecords.prefix(5)) { record in
                    HistoryRow(store: store, record: record)
                }
                if store.historyRecords.count > 5 {
                    Button(L10n.text("Вся история…")) { store.showHistory = true }
                        .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Palette.accent).padding(.top, 8)
                }
                if store.historyRecords.isEmpty && store.savingHistory == 0 {
                    Text(L10n.text("Здесь появятся сохранённые сканы")).font(.system(size: 10)).foregroundStyle(Palette.sub)
                }
                SectionLabel(text: L10n.text("Добавить в анализ")).padding(.top, 24).padding(.bottom, 10)
                if !store.alreadyInScan(NSHomeDirectory()) {
                nav(L10n.text("Домашняя папка"), symbol: "house", active: false, add: true) { store.prepare(NSHomeDirectory()) }.disabled(store.scanning)
                }
                if !store.alreadyInScan(NSHomeDirectory() + "/Downloads") {
                nav(L10n.text("Загрузки"), symbol: "arrow.down.circle", active: false, add: true) { store.prepare(NSHomeDirectory() + "/Downloads") }.disabled(store.scanning)
                }
                if !store.alreadyInScan("/Applications") {
                nav(L10n.text("Приложения"), symbol: "app.dashed", active: false, add: true) { store.prepare("/Applications") }.disabled(store.scanning)
                }
                nav(L10n.text("Другие папки…"), symbol: "folder.badge.plus", active: false, add: true) { store.beginSelection() }.disabled(store.scanning)


            }
              }.padding(.horizontal, 8)
            }.padding(.horizontal, -8)
            Spacer(minLength: 12)
            Button { store.showAgent = true } label: {
                HStack {
                    Image(systemName: "terminal").font(.system(size: 14))
                    Text(L10n.text("Для агента")).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 10))
                }.foregroundStyle(Palette.accent).padding(11)
                    .background(Palette.mark, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)
            LanguagePicker(store: store).padding(.top, 12)
            HStack {
                Text(L10n.text("Локально на твоём Mac")).font(.system(size: 10)).foregroundStyle(Palette.sub)
                Spacer()
                Menu {
                    Button(L10n.text("Как в системе")) { store.appearance = "system" }
                    Button(L10n.text("Светлая")) { store.appearance = "light" }
                    Button(L10n.text("Тёмная")) { store.appearance = "dark" }
                } label: { Image(systemName: "circle.lefthalf.filled") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .fixedSize().frame(width: 26, height: 24).help(L10n.text("Оформление"))
                    .accessibilityLabel(L10n.text("Оформление приложения"))
            }.padding(.top, 16).padding(.bottom, 18)
        }.padding(.horizontal, 19).background(Palette.soft)
    }

    private func nav(_ title: String, symbol: String, active: Bool, add: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 17)
                Text(title).font(.system(size: 12, weight: active ? .semibold : .regular))
                Spacer(minLength: 0)
                if add { Image(systemName: "plus").font(.system(size: 9, weight: .semibold)) }
            }.padding(.horizontal, 10).padding(.vertical, 10)
                .foregroundStyle(active ? Palette.accent : Palette.sub)
                .background(active ? Palette.mark : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).padding(.horizontal, -8)
    }

}

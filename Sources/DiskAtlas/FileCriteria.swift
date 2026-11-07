import AtlasCore
import SwiftUI

struct FileSizeRange: View {
    @Binding var options: DuplicateOptions
    @State private var draftLower: Double?
    @State private var draftUpper: Double?
    @State private var editing = false
    @State private var minimum = ""
    @State private var maximum = ""
    @State private var invalid = false
    private func position(_ bytes: Int64) -> Double { bytes <= 0 ? 0 : min(1, log10(Double(bytes)) / 15) }
    private func bytes(_ position: Double) -> Int64 { position <= 0 ? 0 : Int64(pow(10, position * 15).rounded()) }
    private var lower: Double { draftLower ?? position(options.minimumBytes) }
    private var upper: Double { draftUpper ?? options.maximumBytes.map(position) ?? 1 }
    private var caption: String {
        let low = draftLower.map(bytes) ?? options.minimumBytes
        let high = draftUpper.map { $0 >= 0.999 ? nil : bytes($0) } ?? options.maximumBytes
        if low == 0 && high == nil { return L10n.text("Любой размер") }
        if low == 0 { return L10n.text("До ") + byteString(high ?? 0) }
        if high == nil { return L10n.text("От ") + byteString(low) }
        return byteString(low) + " – " + byteString(high!)
    }
    private func set(_ low: Int64, _ high: Int64?) {
        var value = options
        value.minimumBytes = low
        value.maximumBytes = high
        options = value
        draftLower = nil
        draftUpper = nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text("Размер")).font(.system(size: 10)).foregroundStyle(Palette.sub)
                Spacer(minLength: 3)
                Button {
                    minimum = "\(options.minimumBytes) B"
                    maximum = options.maximumBytes.map { "\($0) B" } ?? ""
                    invalid = false
                    editing = true
                } label: {
                    Text(caption).lineLimit(1).minimumScaleFactor(0.7)
                }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(
                    Palette.accent
                ).help(L10n.text("Ввести точные границы")).popover(isPresented: $editing) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("Размер файлов")).font(.headline)
                        TextField(L10n.text("От, например 100 MB"), text: $minimum).frame(width: 240)
                        TextField(L10n.text("До, пусто — без ограничения"), text: $maximum).frame(width: 240)
                        if invalid {
                            Text(L10n.text("Проверь размер и порядок границ.")).font(.caption).foregroundStyle(.red)
                        }
                        Button(L10n.text("Применить")) {
                            guard let low = Self.parse(minimum), maximum.isEmpty || Self.parse(maximum) != nil,
                                maximum.isEmpty || Self.parse(maximum)! >= low
                            else {
                                invalid = true
                                return
                            }
                            set(low, maximum.isEmpty ? nil : Self.parse(maximum))
                            editing = false
                        }.keyboardShortcut(.defaultAction)
                    }.padding(18)
                }
            }
            HStack(spacing: 4) {
                preset("Все", selected: options.minimumBytes == 0 && options.maximumBytes == nil) { set(0, nil) }
                preset("Крупные", selected: options.minimumBytes == 100_000_000 && options.maximumBytes == nil) {
                    set(100_000_000, nil)
                }
                preset("Мелкие", selected: options.minimumBytes == 0 && options.maximumBytes == 1_000_000) {
                    set(0, 1_000_000)
                }
            }
            RangeTrack(
                lower: lower, upper: upper,
                preview: {
                    draftLower = $0
                    draftUpper = $1
                }, commit: { low, high in set(bytes(low), high >= 0.999 ? nil : bytes(high)) }
            ).frame(height: 38)
        }
    }
    private func preset(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(L10n.text(text)).font(.system(size: 10)).lineLimit(1).frame(maxWidth: .infinity).frame(height: 26)
                .foregroundStyle(selected ? Palette.accent : Palette.sub).background(
                    selected ? Palette.mark : Palette.soft, in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain)
    }
    static func parse(_ input: String) -> Int64? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().replacingOccurrences(
            of: ",", with: ".")
        let number = text.prefix { $0.isNumber || $0 == "." }
        let suffix = text.dropFirst(number.count).trimmingCharacters(in: .whitespaces)
        let units: [String: Double] = ["": 1, "B": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12, "PB": 1e15]
        guard let n = Double(number), let scale = units[suffix], n.isFinite, n >= 0, n * scale < Double(Int64.max)
        else { return nil }
        return Int64(n * scale)
    }
}

struct FileCriteria: View {
    @Binding var options: DuplicateOptions
    private var preset: Int {
        if options.modifiedAfter == nil && options.modifiedBefore == nil { return 0 }
        if let date = options.modifiedBefore, options.modifiedAfter == nil {
            if abs(date.timeIntervalSinceNow + 30 * 86400) < 3600 { return 1 }
            if abs(date.timeIntervalSinceNow + 365 * 86400) < 3600 { return 2 }
        }
        if let date = options.modifiedAfter, options.modifiedBefore == nil,
            abs(date.timeIntervalSinceNow + 30 * 86400) < 3600
        {
            return 3
        }
        return 4
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FileSizeRange(options: $options)
            Picker(
                L10n.text("Изменён"),
                selection: Binding(
                    get: { preset },
                    set: { value in
                        options.modifiedAfter = nil
                        options.modifiedBefore = nil
                        if value == 1 { options.modifiedBefore = Date().addingTimeInterval(-30 * 86400) }
                        if value == 2 { options.modifiedBefore = Date().addingTimeInterval(-365 * 86400) }
                        if value == 3 { options.modifiedAfter = Date().addingTimeInterval(-30 * 86400) }
                        if value == 4 {
                            options.modifiedAfter = Calendar.current.startOfDay(
                                for: Date().addingTimeInterval(-365 * 86400))
                            options.modifiedBefore = Date()
                        }
                    })
            ) {
                Text(L10n.text("Любая дата")).tag(0)
                Text(L10n.text("Старше 30 дней")).tag(1)
                Text(L10n.text("Старше года")).tag(2)
                Text(L10n.text("За последние 30 дней")).tag(3)
                Text(L10n.text("Свой период")).tag(4)
            }.font(.system(size: 10)).controlSize(.small).frame(maxWidth: 230, alignment: .leading)
            if preset == 4 {
                DatePicker(
                    L10n.text("С"),
                    selection: Binding(get: { options.modifiedAfter ?? Date() }, set: { options.modifiedAfter = $0 }),
                    displayedComponents: .date)
                DatePicker(
                    L10n.text("По"),
                    selection: Binding(get: { options.modifiedBefore ?? Date() }, set: { options.modifiedBefore = $0 }),
                    displayedComponents: .date)
            }
        }
    }
}

struct ViewFilterButton: View {
    @ObservedObject var store: AtlasStore
    @State private var showing = false
    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Label(L10n.text("Фильтры"), systemImage: "line.3.horizontal.decrease").font(
                .system(size: 11, weight: .medium)
            ).foregroundStyle(store.viewFiltersEnabled ? Palette.accent : Palette.ink).padding(.horizontal, 10).frame(
                height: 28
            ).background(store.viewFiltersEnabled ? Palette.mark : Palette.soft, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).help(L10n.text("Фильтры карты и списка")).accessibilityLabel(
            L10n.text("Фильтры карты и списка")
        ).popover(isPresented: $showing) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L10n.text("Размер и дата")).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if store.viewFiltersEnabled {
                        Button(L10n.text("Сбросить")) {
                            store.viewFiltersEnabled = false
                            store.viewOptions = DuplicateOptions()
                        }.buttonStyle(.plain).font(.system(size: 11))
                    }
                }
                FileCriteria(
                    options: Binding(
                        get: { store.viewOptions },
                        set: { value in
                            store.viewOptions = value
                            store.viewFiltersEnabled = value != DuplicateOptions()
                        }))
                if store.viewFiltering { ProgressView().controlSize(.mini) }
            }.padding(18).frame(width: 320).background(Palette.paper)
        }
    }
}

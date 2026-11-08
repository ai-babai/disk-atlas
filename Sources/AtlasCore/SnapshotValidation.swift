import Foundation

extension Snapshot {
    func validateEntries() throws {
        // The parent-before-child invariant makes cycles impossible and keeps UI navigation safe.
        var linked = Set<Int>()
        for (index, entry) in self.entries.enumerated() {
            try validateEntry(entry, at: index)
            for child in entry.children {
                guard child > index, child < self.entries.count, self.entries[child].parent == index,
                    linked.insert(child).inserted
                else { throw AtlasError.message("Нарушены связи снимка.") }
            }
        }
        guard linked.count == self.entries.count - 1, !self.scanRoots.isEmpty,
            self.scanRoots.allSatisfy({ $0.hasPrefix("/") })
        else { throw AtlasError.message("В снимке есть несвязанные объекты.") }
        try validateTotals()
    }
    private func validateEntry(_ entry: Entry, at index: Int) throws {
        guard entry.id == index, entry.bytes >= 0, entry.logicalBytes >= 0, entry.fileCount >= 0,
            entry.path.hasPrefix("/"), entry.isDirectory || entry.children.isEmpty
        else { throw AtlasError.message("Нарушена структура снимка.") }
        try validateParent(entry, at: index)
    }
    private func validateParent(_ entry: Entry, at index: Int) throws {
        guard index == 0 || (entry.parent != nil && entry.parent! >= 0 && entry.parent! < index) else {
            throw AtlasError.message("Нарушена структура снимка.")
        }
    }
    private func validateTotals() throws {
        for entry in self.entries where entry.isDirectory {
            var bytes: Int64 = 0
            var logical: Int64 = 0
            var files = 0
            for child in entry.children {
                let next = self.entries[child]
                let b = bytes.addingReportingOverflow(next.bytes)
                let l = logical.addingReportingOverflow(next.logicalBytes)
                let f = files.addingReportingOverflow(next.fileCount)
                guard !b.overflow, !l.overflow, !f.overflow else {
                    throw AtlasError.message("Повреждены размеры снимка.")
                }
                bytes = b.partialValue
                logical = l.partialValue
                files = f.partialValue
            }
            guard bytes == entry.bytes, logical == entry.logicalBytes, files == entry.fileCount else {
                throw AtlasError.message("Итоги снимка не совпадают с содержимым.")
            }
        }
    }
    mutating func refreshFileKinds() {
        for i in entries.indices {
            let entry = entries[i]
            if entry.isDirectory || entry.kind == .link { continue }
            entries[i].kind = FileKind.classify(URL(fileURLWithPath: entry.path))
        }
    }
}

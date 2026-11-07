import Foundation

extension PresentationIndex {
    /// Keep the folder's bounded results intact and reveal one selected descendant beside its ancestor.
    public func revealingMapSelection(_ id: Int?, folder: Int, in rows: [Entry]) -> [Entry] {
        guard let id, snapshot.entries.indices.contains(id), !rows.contains(where: { $0.id == id }) else { return rows }
        let ancestors = ancestorIDs(of: id)
        guard ancestors.contains(folder) else { return rows }
        let positions = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })
        let anchor = ancestors.lazy.compactMap { positions[$0] }.first
        var result = rows
        result.insert(snapshot.entries[id], at: anchor.map { $0 + 1 } ?? 0)
        return result
    }

    private func ancestorIDs(of id: Int) -> [Int] {
        var result: [Int] = []
        var next = snapshot.entries[id].parent
        while let parent = next {
            result.append(parent)
            next = snapshot.entries[parent].parent
        }
        return result
    }
}

import Foundation

extension PresentationIndex {
    /// The selected object and its ancestors below the current map root, without changing scope.
    public func mapSelectionAncestors(_ selection: Int?, within folder: Int) -> Set<Int> {
        guard let selection, snapshot.entries.indices.contains(selection) else { return [] }
        return mapBranch(from: selection, until: folder)
    }

    private func mapBranch(from selection: Int, until folder: Int) -> Set<Int> {
        var branch: Set<Int> = []
        var cursor: Int? = selection
        while let id = cursor, id != folder {
            branch.insert(id)
            cursor = snapshot.entries[id].parent
        }
        return cursor == folder ? branch : []
    }
}

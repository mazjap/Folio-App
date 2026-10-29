import Foundation

extension Array where Element: Identifiable {
    // MARK: - Functions
    
    /// Moves the element with `id` into `targetID`'s place: after the target when moving down the list, before it when moving up, so dropping an item on its neighbor swaps the two, and dropping on the last item moves it to the end.
    /// - Returns: Whether anything moved.
    @discardableResult
    mutating func move(id: Element.ID, onto targetID: Element.ID) -> Bool {
        guard id != targetID,
              let from = firstIndex(where: { $0.id == id }),
              let to = firstIndex(where: { $0.id == targetID })
        else { return false }
        
        insert(remove(at: from), at: to)
        return true
    }
    
    /// Moves the element with `id` up (negative `offset`) or down the list, stopping at either end.
    /// - Returns: Whether anything moved.
    @discardableResult
    mutating func move(id: Element.ID, by offset: Int) -> Bool {
        guard let from = firstIndex(where: { $0.id == id }) else { return false }
        
        let to = Swift.min(Swift.max(from + offset, 0), count - 1)
        guard to != from else { return false }
        
        insert(remove(at: from), at: to)
        return true
    }
}

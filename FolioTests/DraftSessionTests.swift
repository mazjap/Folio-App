import Foundation
import Testing
@testable import Folio

@MainActor
@Suite
struct DraftSessionTests {
    private final class Owner: DraftKeyed {
        var key = ""
    }
    
    let store = DraftStore.temporary()
    let base = "dev.new-post"
    
    private func claim(_ owner: Owner) -> String {
        owner.key = NewDraftSlots.claim(base: base, in: store, for: owner)
        return owner.key
    }
    
    @Test func eachOpenEditorGetsItsOwnSlot() {
        let first = Owner()
        let second = Owner()
        
        #expect(claim(first) == base)
        #expect(claim(second) == "\(base)-2")
    }
    
    @Test func slotsAreFreedWhenTheEditorCloses() {
        var first: Owner? = Owner()
        #expect(claim(first!) == base)
        first = nil
        
        #expect(claim(Owner()) == base)
    }
    
    /// A new item's key changes when it's first saved, which frees its slot.
    @Test func slotsAreFreedWhenTheItemIsSaved() {
        let first = Owner()
        _ = claim(first)
        first.key = "dev.post-saved"
        
        #expect(claim(Owner()) == base)
    }
    
    @Test func savedDraftsAreRestoredBeforeEmptySlots() throws {
        try store.save(["title": "Left in slot 3"], key: "\(base)-3")
        let first = Owner()
        let second = Owner()
        
        #expect(claim(first) == "\(base)-3")
        #expect(claim(second) == base)
    }
}

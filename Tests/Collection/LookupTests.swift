import Foundation
import Testing
@testable import MidokuCollectionCore

/// Cached lookup tables must never outlive the arrays they index, including across copies.
@Suite("Library lookup cache")
struct LookupTests {
    @Test func lookupsFollowEditsAndRemovals() throws {
        var state = MCLibraryState()
        let a = try state.createManual(title: "A")
        let b = try state.createManual(title: "B")
        #expect(state.title(try #require(state.entry(a))) == "A")
        try state.editEntry(a) { $0.titleOverride = "Renamed" }
        #expect(state.entry(a)?.titleOverride == "Renamed")
        state.removeEntries([a])
        #expect(state.entry(a) == nil)
        #expect(state.entry(b) != nil)
    }

    @Test func copiesKeepIndependentLookups() throws {
        var original = MCLibraryState()
        let a = try original.createManual(title: "A")
        _ = original.entry(a) // warm the shared cache
        var copy = original
        let b = try copy.createManual(title: "B")
        copy.removeEntries([a])
        #expect(original.entry(a) != nil)
        #expect(original.entry(b) == nil)
        #expect(copy.entry(a) == nil)
        #expect(copy.entry(b) != nil)
    }

    @Test func hierarchyFollowsMoves() throws {
        var state = MCLibraryState()
        let parent = try state.createManual(title: "Parent")
        let child = try state.createManual(title: "Child")
        #expect(state.descendantIDs(of: parent).isEmpty)
        try state.moveEntry(child, into: parent)
        #expect(state.descendantIDs(of: parent) == [child])
        #expect(state.ancestorIDs(of: child) == [parent])
        #expect(state.parentPath(of: try #require(state.entry(child))) == "Parent")
        try state.moveEntry(child, into: nil)
        #expect(state.ancestorIDs(of: child).isEmpty)
    }

    @Test func cacheIsNotEncoded() throws {
        var state = MCLibraryState()
        let a = try state.createManual(title: "A")
        _ = state.entry(a)
        let data = try JSONEncoder().encode(state)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["lookup"] == nil)
        let decoded = try JSONDecoder().decode(MCLibraryState.self, from: data)
        #expect(decoded.entry(a) != nil)
    }
}

@Suite("Batch chapter edits")
struct BatchEditTests {
    private func entry() throws -> (MCLibraryState, UUID, [UUID]) {
        var state = MCLibraryState()
        let id = try state.add(details: .init(id: "batch", title: "Batch", description: "", coverURL: nil), connectionID: UUID(),
            records: [.init(id: "a", title: "Prologue", number: "0", ordinal: 0, language: nil),
                      .init(id: "b", title: "Start", number: "1", ordinal: 1, language: nil),
                      .init(id: "c", title: "Middle", number: "2", ordinal: 2, language: nil)], language: nil)
        let slots = try #require(state.entry(id)).slots.map(\.id)
        return (state, id, slots)
    }

    @Test func renumbersAndRenamesInGivenOrder() throws {
        let (initial, id, slots) = try entry()
        var state = initial
        try state.applyBatchEdit(entryID: id, slotIDs: slots, edit: .init(titlePattern: "Part {n} – {title}", startNumber: 10, step: 5))
        let edited = try #require(state.entry(id)).slots
        let byID = Dictionary(uniqueKeysWithValues: edited.map { ($0.id, $0.preferred!) })
        #expect(byID[slots[0]]?.edits.number == "10")
        #expect(byID[slots[2]]?.edits.number == "20")
        #expect(byID[slots[1]]?.edits.title == "Part 15 – Start")
    }

    @Test func emptyPatternRestoresSourceTitlesAndKeepsNumbers() throws {
        let (initial, id, slots) = try entry()
        var state = initial
        try state.applyBatchEdit(entryID: id, slotIDs: slots, edit: .init(titlePattern: "Ch {i}"))
        try state.applyBatchEdit(entryID: id, slotIDs: [slots[0]], edit: .init(titlePattern: ""))
        let first = try #require(state.entry(id)?.slots.first { $0.id == slots[0] }?.preferred)
        #expect(first.edits.title == nil)
        #expect(first.edits.number == nil)
    }
}

@Suite("Duplicate finder")
struct DuplicateTests {
    @Test func keysIgnoreCasePunctuationAndNotes() {
        #expect(MCLibraryState.duplicateKey("The Héros' Journey (Official)") == MCLibraryState.duplicateKey("heros journey"))
        #expect(MCLibraryState.duplicateKey("Tom & Jerry") == "tom and jerry")
        #expect(MCLibraryState.duplicateKey("Solo Leveling") != MCLibraryState.duplicateKey("Solo Leveling Ragnarok"))
    }

    @Test func groupsMatchingTitlesButNotNestedOnes() throws {
        var state = MCLibraryState()
        let a = try state.createManual(title: "One Piece")
        let b = try state.createManual(title: "one piece [Colored]")
        let other = try state.createManual(title: "Bleach")
        let nested = try state.createManual(title: "Bleach")
        try state.moveEntry(nested, into: other)
        let groups = state.duplicateGroups()
        #expect(groups == [[a, b]])
    }
}

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

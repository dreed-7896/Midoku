import Foundation
import Testing
@testable import MidokuCollectionCore

@Suite("Nested titles")
struct HierarchyTests {
    private func fixture() throws -> (MCLibraryState, UUID, UUID, UUID, UUID) {
        var state = MCLibraryState()
        let connection = UUID()
        func add(_ key: String, _ numbers: [Int]) throws -> UUID {
            try state.add(details: .init(id: key, title: key, description: "", coverURL: nil), connectionID: connection,
                records: numbers.map { .init(id: String($0), title: "Chapter \($0)", number: String($0), ordinal: $0, language: nil) }, language: nil)
        }
        let x = try add("X", [1, 4]), y = try add("Y", [2, 3]), z = try add("Z", [5])
        try state.moveEntry(y, into: x)
        try state.moveEntry(z, into: y)
        let xs = try #require(state.entry(x)).slots, ys = try #require(state.entry(y)).slots
        try state.reorderContents(entryID: x, order: [.chapter(xs[0].id), .title(y), .chapter(xs[1].id)])
        try state.reorderContents(entryID: y, order: [.chapter(ys[0].id), .title(z), .chapter(ys[1].id)])
        return (state, x, y, z, connection)
    }

    @Test func recursiveOrderProgressAndResumeIncludeEveryNestedChapter() throws {
        var (state, x, y, z, connection) = try fixture()
        let sequence = state.flattenedChapters(entryID: x)
        #expect(sequence.compactMap(\.slot.preferred).compactMap { state.number($0) } == ["1", "2", "5", "3", "4"])
        #expect(sequence.map(\.entryID) == [x, y, z, y, x])
        #expect(state.rootEntries.map(\.id) == [x])
        #expect(state.parentPath(of: try #require(state.entry(z))) == "X > Y")
        let next = state.nextSlotIDs(entryID: x, after: sequence[1].slot.id)
        _ = try state.setRead(entryID: x, slotIDs: next, read: true)
        let counts = state.chapterCounts()
        #expect(counts[x]?.total == 5 && counts[x]?.unread == 2)
        #expect(counts[y]?.total == 3 && counts[y]?.unread == 1)
        #expect(counts[z]?.total == 1 && counts[z]?.unread == 0)
        let identity = try #require(sequence[2].slot.preferred.flatMap { state.chapter($0.chapterID)?.identity })
        #expect(state.resumeSlot(try #require(state.entry(x)), positions: [.init(id: identity, updatedAt: Date())]) == sequence[2].slot.id)
        try state.validate(connections: [connection], categories: [])
    }

    @Test func refreshAppendsWithoutFlatteningTitlesOrChangingFollowSettings() throws {
        var (state, x, y, z, connection) = try fixture()
        let original = state.flattenedChapters(entryID: x).map(\.slot.id)
        try state.editEntry(x) { $0.links[0].followsNewChapters = false }
        try state.refresh(details: .init(id: "Y", title: "Y", description: "", coverURL: nil), connectionID: connection,
            records: [2, 3, 6].map { .init(id: String($0), title: "Chapter \($0)", number: String($0), ordinal: $0, language: nil) }, language: nil)
        let sequence = state.flattenedChapters(entryID: x)
        #expect(sequence.compactMap(\.slot.preferred).compactMap { state.number($0) } == ["1", "2", "5", "3", "6", "4"])
        #expect(sequence.filter { original.contains($0.slot.id) }.map(\.slot.id) == original)
        #expect(state.entry(y)?.links.first?.followsNewChapters == true)
        #expect(state.entry(z)?.links.first?.followsNewChapters == true)
        #expect(state.entry(y)?.parentEntryID == x)
        #expect(state.updates.first?.entryID == y)
    }

    @Test func movesRejectCyclesAndCanReturnToLibrary() throws {
        var (state, x, y, z, connection) = try fixture()
        #expect(throws: MCLibraryFailure.self) { try state.moveEntry(x, into: z) }
        #expect(throws: MCLibraryFailure.self) { try state.moveEntry(y, into: y) }
        #expect(state.entry(x)?.parentEntryID == nil)
        try state.moveEntry(y, into: nil)
        #expect(Set(state.rootEntries.map(\.id)) == [x, y])
        #expect(state.entry(z)?.parentEntryID == y)
        #expect(state.flattenedChapters(entryID: x).count == 2)
        #expect(state.flattenedChapters(entryID: y).count == 3)
        state.normalizeContentOrders()
        try state.validate(connections: [connection], categories: [])
    }

    @Test func deleteCanPreserveOrRemoveTheWholeSubtree() throws {
        let (original, x, y, z, connection) = try fixture()
        var keep = original
        keep.removeEntries([x])
        #expect(keep.rootEntries.map(\.id) == [y])
        #expect(keep.entry(z)?.parentEntryID == y)
        #expect(keep.flattenedChapters(entryID: y).count == 3)
        try keep.validate(connections: [connection], categories: [])
        var remove = original
        remove.readingEntryIDs = [x, y, z]
        remove.removeEntries([x], includingDescendants: true)
        #expect(remove.entries.isEmpty && remove.readingIDs.isEmpty)
        #expect(remove.chapters.count == original.chapters.count)
        try remove.validate(connections: [connection], categories: [])
    }

    @Test func backupsPreserveNestingAndOldLibrariesStillDecode() throws {
        let (state, x, y, z, connection) = try fixture()
        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(MCLibraryState.self, from: data)
        #expect(restored.flattenedChapters(entryID: x).map(\.slot.id) == state.flattenedChapters(entryID: x).map(\.slot.id))
        #expect(restored.entry(z)?.parentEntryID == y)
        try restored.validate(connections: [connection], categories: [])
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var entries = try #require(json["entries"] as? [[String: Any]])
        for i in entries.indices { entries[i].removeValue(forKey: "parentEntryID"); entries[i].removeValue(forKey: "contentOrder") }
        json["entries"] = entries
        let legacy = try JSONDecoder().decode(MCLibraryState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.rootEntries.count == 3)
        #expect(legacy.flattenedChapters(entryID: x).count == 2)
        try legacy.validate(connections: [connection], categories: [])
    }

    @Test func invalidBackupParentsAndCyclesAreRejected() throws {
        var (state, x, _, z, connection) = try fixture()
        let index = try #require(state.entries.firstIndex { $0.id == x })
        state.entries[index].parentEntryID = z
        #expect(throws: MCLibraryFailure.self) { try state.validate(connections: [connection], categories: []) }
        state.entries[index].parentEntryID = UUID()
        #expect(throws: MCLibraryFailure.self) { try state.validate(connections: [connection], categories: []) }
    }

    @Test func deletedChaptersLeaveNoReaderRoutesAndNewChaptersRemainAddressable() throws {
        var (state, x, y, _, connection) = try fixture()
        let removed = try #require(state.entry(y)?.slots.first)
        try state.removeSlots(entryID: y, slotIDs: [removed.id])
        state.normalizeContentOrders()
        #expect(!state.flattenedChapters(entryID: x).contains { $0.slot.id == removed.id })
        #expect(state.chapterCounts()[x]?.total == 4)
        try state.validate(connections: [connection], categories: [])
    }
}

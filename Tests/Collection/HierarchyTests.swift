import Foundation
import Testing
@testable import MidokuCollectionCore

@Suite("Nested titles")
struct HierarchyTests {
    @Test func groupingCopiesEditableDetailsWithoutCopyingChaptersOrSourceLinks() throws {
        var (state, x, y, z, connection) = try fixture()
        let other = try state.createManual(title: "Other")
        let category = UUID()
        let cover = MCLibraryCover(url: URL(string: "https://example.com/cover.jpg")!, sourceKey: "source")
        state.covers.append(cover)
        try state.editEntry(x) {
            $0.titleOverride = "Personal X"; $0.descriptionOverride = "Summary"
            $0.authorOverride = "Author"; $0.artistOverride = "Artist"
            $0.status = .onHold; $0.categoryIDs = [category]; $0.coverID = cover.id
            $0.links[0].followsNewChapters = false
        }
        let before = state.flattenedChapters(entryID: x).map(\.slot.id)
        let original = try #require(state.entry(x))
        var details = state.titleDetails(of: original)
        details.title = "My collection" // Copying is a starting point, not a live link.
        let group = try state.groupEntries([other, x], details: details)
        let parent = try #require(state.entry(group))
        #expect(state.rootEntries.map(\.id) == [group])
        #expect(state.contents(of: parent) == [.title(other), .title(x)])
        #expect(parent.titleOverride == "My collection" && parent.descriptionOverride == "Summary")
        #expect(parent.authorOverride == "Author" && parent.artistOverride == "Artist")
        #expect(parent.status == .onHold && parent.categoryIDs == [category] && parent.coverID == cover.id)
        #expect(parent.links.isEmpty && parent.slots.isEmpty && parent.primaryListingID == nil)
        #expect(state.covers.count == 1)
        #expect(state.entry(x)?.titleOverride == original.titleOverride)
        #expect(state.entry(x)?.links.first?.followsNewChapters == false)
        #expect(state.entry(y)?.parentEntryID == x && state.entry(z)?.parentEntryID == y)
        #expect(state.flattenedChapters(entryID: group).map(\.slot.id) == before)
        try state.validate(connections: [connection], categories: [category])
    }

    @Test func inheritedSourceDetailsBecomeIndependentEditableDetails() throws {
        var state = MCLibraryState()
        let connection = UUID(), url = URL(string: "https://example.com/source.jpg")!
        var source = MCMangaDetails(id: "source", title: "Source title", description: "Source summary", coverURL: url)
        source.authors = ["Author 1", "Author 2"]; source.artists = ["Artist"]
        let a = try state.add(details: source, connectionID: connection, records: [], language: nil)
        let b = try state.createManual(title: "B")
        let details = state.titleDetails(of: try #require(state.entry(a)), sourceKey: "source.key")
        #expect(details.title == source.title && details.description == source.description)
        #expect(details.author == "Author 1, Author 2" && details.artist == "Artist")
        #expect(details.cover?.url == url && details.cover?.sourceKey == "source.key")
        let group = try state.groupEntries([a, b], details: details)
        try state.editEntry(a) { $0.titleOverride = "Changed child" }
        #expect(state.title(try #require(state.entry(group))) == "Source title")
        #expect(state.entry(group)?.coverID == details.cover?.id)
        try state.validate(connections: [connection], categories: [])
        var hidden = details; hidden.hidesCover = true
        let hiddenGroup = try state.groupEntries([a, b], details: hidden)
        #expect(state.entry(hiddenGroup)?.hidesCover == true && state.entry(hiddenGroup)?.coverID == nil)
    }

    @Test func groupingOverlappingSelectionsKeepsSubtreesAndRejectsInvalidInputAtomically() throws {
        var (state, x, y, z, connection) = try fixture()
        let before = try JSONEncoder().encode(state)
        #expect(throws: MCLibraryFailure.self) { try state.groupEntries([x, UUID()], details: .init(title: "Group")) }
        #expect(throws: MCLibraryFailure.self) { try state.groupEntries([x, x], details: .init(title: "Group")) }
        #expect(throws: MCLibraryFailure.self) { try state.groupEntries([x, y], details: .init(title: "  ")) }
        // JSON key order is unspecified; compare decoded objects to verify no partial creation.
        #expect(NSDictionary(dictionary: try #require(JSONSerialization.jsonObject(with: before) as? [String: Any])) ==
            NSDictionary(dictionary: try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])))
        let group = try state.groupEntries([z, x, y, x], details: .init(title: "Group"))
        #expect(state.contents(of: try #require(state.entry(group))) == [.title(x)])
        #expect(state.entry(y)?.parentEntryID == x && state.entry(z)?.parentEntryID == y)
        #expect(state.flattenedChapters(entryID: group).count == 5)
        try state.validate(connections: [connection], categories: [])
    }

    @Test func randomReadingPoolIncludesEveryDepthExactlyOnceWithoutUnrelatedTitles() throws {
        var (state, x, y, z, _) = try fixture()
        let other = try state.createManual(title: "Outside Reading")
        #expect(state.entriesIncludingDescendants(of: []).isEmpty)
        #expect(state.entriesIncludingDescendants(of: [UUID()]).isEmpty)
        #expect(state.entriesIncludingDescendants(of: [x]).map(\.id) == [x, y, z])
        #expect(state.entriesIncludingDescendants(of: [x, y, z]).map(\.id) == [x, y, z])
        #expect(state.entriesIncludingDescendants(of: [y]).map(\.id) == [y, z])
        #expect(Set(state.entriesIncludingDescendants(of: Set(state.entries.map(\.id))).map(\.id)) == [x, y, z, other])
    }

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

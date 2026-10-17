import Foundation
import Testing
@testable import MidokuCollectionCore

@Suite("Chapter page splits")
struct PageRangeTests {
    @Test func parsesRangesAndRejectsAmbiguity() throws {
        let ranges = try MCPageRange.parse("1-20, 21-45,46-", disjoint: true)
        #expect(ranges.map(\.text) == ["1-20", "21-45", "46-"])
        for invalid in ["0-4", "3-1", "1,,2", "x", "1-2-3", "-20", "1-1000001"] {
            #expect(throws: (any Error).self) { try MCPageRange.parse(invalid) }
        }
        for invalid in ["1-20,20-30", "21-,40-50", "21-40,1-20"] {
            #expect(throws: (any Error).self) { try MCPageRange.parse(invalid, disjoint: true) }
        }
    }
    @Test func sourcePageNumbersStayStableAndOpenEndIncludesUpdates() throws {
        let ranges = try MCPageRange.parse("1-20,21-", disjoint: true)
        let excluded = try MCPageRange.parse("3,8-10,24")
        var plan = MCChapterPageSelection(originID: UUID(), ranges: ranges, excluded: excluded, part: 0, originalEdits: .init())
        #expect(plan.indices(pageCount: 25) == Array(0..<20).filter { ![2,7,8,9].contains($0) })
        #expect(plan.sourcePage(for: 3) == 4)
        #expect(plan.sourcePage(for: 16) == 20)
        #expect(plan.relativePage(for: 20) == 16)
        #expect(plan.relativePage(for: 3) == nil)
        #expect(plan.sourcePage(for: 17) == nil)
        plan.part = 1
        #expect(plan.indices(pageCount: 25) == [20,21,22,24])
        #expect(plan.indices(pageCount: 28) == [20,21,22,24,25,26,27])
        #expect(plan.sourcePage(for: 4) == 25)
        #expect(plan.sourcePage(for: 7) == 28)
        #expect(plan.relativePage(for: 28) == 7)
        plan.excluded = try MCPageRange.parse("21-23,22-25")
        #expect(plan.sourcePage(for: 1) == 26)
        #expect(plan.indices(pageCount: 0).isEmpty)
    }
    @Test func splitsPersistRefreshAndRejoinWithoutChangingPhysicalIdentity() throws {
        var library = MCLibraryState()
        let connection = UUID()
        let details = MCMangaDetails(id: "book", title: "Book", description: "", coverURL: URL(string: "https://example.com/cover.jpg"))
        let records = [MCChapterRecord(id: "one", title: "Combined", number: "1", ordinal: 0, language: nil)]
        let id = try library.add(details: details, connectionID: connection, records: records, language: nil)
        let slot = try #require(library.entry(id)?.slots.first)
        let ranges = try MCPageRange.parse("1-20,21-45,46-", disjoint: true)
        try library.setChapterPages(entryID: id, slotID: slot.id, ranges: ranges, excluded: try MCPageRange.parse("2,5-6"))
        var parts = try #require(library.entry(id)).slots
        #expect(parts.count == 3)
        #expect(Set(parts.compactMap(\.preferred).map(\.chapterID)).count == 1)
        #expect(Set(parts.compactMap(\.preferred).map(\.id)).count == 3)
        try library.setRead(entryID: id, slotIDs: [parts[0].id], read: true)
        parts = try #require(library.entry(id)).slots
        #expect(library.isRead(parts[0]) && !library.isRead(parts[1]))
        #expect(library.completed.isEmpty)
        let encoded = try JSONEncoder().encode(library)
        library = try JSONDecoder().decode(MCLibraryState.self, from: encoded)
        try library.refresh(details: .init(id: "book", title: "Updated", description: "", coverURL: nil), connectionID: connection, records: records, language: nil)
        #expect(library.entry(id)?.slots.map(\.id) == parts.map(\.id))
        #expect(library.listings.first?.details.coverURL == details.coverURL)
        try library.validate(connections: [connection], categories: [])
        let joinedSlotID = try library.setChapterPages(entryID: id, slotID: parts[2].id, ranges: [], excluded: [])
        let restored = try #require(library.entry(id)?.slots.first)
        #expect(library.entry(id)?.slots.count == 1)
        #expect(restored.id == slot.id && restored.id == joinedSlotID && restored.preferred?.pageSelection == nil)
        #expect(library.chapterTitle(try #require(restored.preferred)) == "Combined")
        try library.validate(connections: [connection], categories: [])
    }
    @Test func removingOnePartAndMergingKeepsRemainingParts() throws {
        var library = MCLibraryState()
        let connection = UUID()
        let id = try library.add(details: .init(id: "a", title: "A", description: "", coverURL: nil), connectionID: connection,
            records: [.init(id: "one", title: "All", number: "1", ordinal: 0, language: nil)], language: nil)
        let slot = try #require(library.entry(id)?.slots.first)
        try library.setChapterPages(entryID: id, slotID: slot.id, ranges: try MCPageRange.parse("1-20,21-40,41-", disjoint: true), excluded: [])
        let parts = try #require(library.entry(id)).slots
        try library.removeSlots(entryID: id, slotIDs: [parts[1].id])
        try library.validate(connections: [connection], categories: [])
        let other = try library.createManual(title: "Other")
        let merged = try library.groupEntries([id, other], details: .init(title: "Merged"), mode: .mergeChapters)
        #expect(library.entry(merged)?.slots.count == 2)
        #expect(library.entry(merged)?.slots.compactMap(\.preferred).compactMap(\.pageSelection).map(\.part) == [0,2])
        try library.validate(connections: [connection], categories: [])
    }
    @Test func editingUnsplitChapterDoesNotChangeReadState() throws {
        var library = MCLibraryState()
        let connection = UUID()
        let id = try library.add(details: .init(id: "a", title: "A", description: "", coverURL: nil), connectionID: connection,
            records: [.init(id: "one", title: "All", number: "1", ordinal: 0, language: nil)], language: nil)
        let slot = try #require(library.entry(id)?.slots.first)
        try library.setRead(entryID: id, slotIDs: [slot.id], read: true)
        try library.setChapterPages(entryID: id, slotID: slot.id, ranges: [], excluded: [])
        #expect(library.isRead(try #require(library.entry(id)?.slots.first)))
    }
}

import Foundation
import Testing
@testable import MidokuCollectionCore

@Suite("Midoku mixed-source composition")
struct CollectionTests {
    let a = UUID(), b = UUID()
    func details(_ id: String = "same-key") -> MCMangaDetails { .init(id: id, title: "Original", description: "Source text", coverURL: nil) }
    func records(_ numbers: [Int]) -> [MCChapterRecord] {
        numbers.map { .init(id: "chapter-\($0)", title: "Episode \($0)", number: String($0), ordinal: $0, language: "en") }
    }
    func mixed() throws -> (MCLibraryState, UUID) {
        var state = MCLibraryState()
        let id = try state.add(details: details(), connectionID: a, records: records([20, 22]), language: nil)
        _ = try state.remember(details: details(), connectionID: b, records: records([20, 21, 22]), complete: true)
        let chapter = try #require(state.chapters.first { $0.identity.listing.connectionID == b && $0.record.number == "21" })
        try state.addChapter(entryID: id, variant: MCChapterVariant(chapterID: chapter.id))
        return (state, id)
    }
    @Test func sourceAToBToASurvivesRestartAndRefresh() throws {
        let (original, id) = try mixed()
        var state = try JSONDecoder().decode(MCLibraryState.self, from: JSONEncoder().encode(original))
        try state.refresh(details: details(), connectionID: b, records: records([20, 21, 22, 23]), language: nil)
        let entry = try #require(state.entry(id))
        #expect(entry.slots.compactMap(\.preferred).compactMap { state.chapter($0.chapterID)?.identity.listing.connectionID } == [a, b, a])
        #expect(entry.links.last?.followsNewChapters == false)
        try state.validate(connections: [a, b], categories: [])
    }
    @Test func directAddIsIdempotentAndSourceIDsDoNotCollide() throws {
        var (state, id) = try mixed()
        let added = try #require(state.entry(id)?.slots.first?.preferred)
        try state.addChapter(entryID: id, variant: added)
        #expect(state.entry(id)?.slots.count == 3)
        #expect(state.chapters.filter { $0.record.id == "chapter-20" }.count == 2)
    }
    @Test func editingSurvivesRefreshAndResetKeepsComposition() throws {
        var (state, id) = try mixed()
        try state.editEntry(id) {
            $0.titleOverride = "My edition"; $0.descriptionOverride = ""; $0.artistOverride = "My artist"
            $0.slots[0].variants[0].edits.title = "Custom name"
        }
        try state.refresh(details: details(), connectionID: a, records: records([20, 22, 23]), language: nil)
        let edited = try #require(state.entry(id))
        #expect(state.title(edited) == "My edition")
        #expect(state.description(edited).isEmpty)
        #expect(edited.artistOverride == "My artist")
        #expect(edited.slots.first?.preferred?.edits.title == "Custom name")
        try state.resetDetails(id)
        #expect(state.entry(id)?.artistOverride == nil)
        #expect(state.entry(id)?.links.count == 2)
        #expect(state.entry(id)?.slots.count == 4)
    }
    @Test func removedChaptersStayExcluded() throws {
        var (state, id) = try mixed()
        let slot = try #require(state.entry(id)?.slots.first)
        try state.removeSlots(entryID: id, slotIDs: [slot.id])
        try state.refresh(details: details(), connectionID: a, records: records([20, 22]), language: nil)
        #expect(state.entry(id)?.slots.count == 2)
        #expect(state.entry(id)?.exclusions.count == 1)
        try state.validate(connections: [a, b], categories: [])
    }
    @Test func removedChaptersCanBeRestored() throws {
        var (state, id) = try mixed()
        let slot = try #require(state.entry(id)?.slots.first)
        let chapterID = try #require(slot.preferred).chapterID
        try state.removeSlots(entryID: id, slotIDs: [slot.id])
        #expect(state.entry(id)?.exclusions.contains(chapterID) == true)
        try state.restoreChapter(entryID: id, chapterID: chapterID)
        let restored = try #require(state.entry(id))
        #expect(!restored.exclusions.contains(chapterID))
        #expect(restored.slots.flatMap(\.variants).contains(where: { $0.chapterID == chapterID }))
    }

    @Test func suggestedChapterNamesContinueEditedSequence() throws {
        var state = MCLibraryState()
        let id = try state.add(details: details(), connectionID: a, records: records([100]), language: nil)
        try state.editEntry(id) { entry in
            entry.slots[0].variants[0].edits.title = "Chapter 4"
        }
        let next = try state.suggestedChapterName(entryID: id)
        #expect(next == "Chapter 5")
        try state.editEntry(id) { entry in
            entry.slots[0].variants[0].edits.title = "Episode 4"
        }
        let inherited = try state.suggestedChapterName(entryID: id)
        #expect(inherited == "Episode 5")
        let empty = try state.createManual(title: "Empty")
        let first = try state.suggestedChapterName(entryID: empty)
        #expect(first == "Chapter 1")
    }
    @Test func alternativesHaveIndependentPhysicalCompletion() throws {
        var (state, id) = try mixed()
        let incoming = try #require(state.chapters.first { $0.identity.listing.connectionID == b && $0.record.number == "20" })
        try state.editEntry(id) { entry in
            let variant = MCChapterVariant(chapterID: incoming.id)
            entry.slots[0].variants.append(variant)
        }
        let slot = try #require(state.entry(id)?.slots.first)
        let original = try #require(slot.preferred).chapterID
        state.completed.insert(try #require(state.chapter(original)).identity)
        #expect(state.isRead(slot))
        try state.editEntry(id) { $0.slots[0].preferredID = $0.slots[0].variants[1].id }
        #expect(!state.isRead(try #require(state.entry(id)?.slots.first)))
    }
    @Test func manualOrderDoesNotReverseWhenDisplayIsDescending() throws {
        var (state, id) = try mixed()
        let last = try #require(state.entry(id)?.slots.last)
        try state.moveSlot(entryID: id, slotID: last.id, offset: -1)
        try state.editEntry(id) { $0.descendingDisplay = true }
        let entry = try #require(state.entry(id))
        #expect(entry.slots.compactMap(\.preferred).compactMap { state.number($0) } == ["20", "22", "21"])
    }
    @Test func directAddEditsPersist() throws {
        var state = MCLibraryState()
        let id = try state.add(details: details(), connectionID: a, records: records([1]), language: nil)
        _ = try state.remember(details: details(), connectionID: b, records: records([2, 3]), complete: true)
        let incoming = try #require(state.chapters.first { $0.identity.listing.connectionID == b && $0.record.number == "2" })
        let edits = MCChapterEdits(title: "My chapter", number: "1.5", volume: "2")
        try state.addChapter(entryID: id, variant: MCChapterVariant(chapterID: incoming.id, edits: edits))
        let reloaded = try JSONDecoder().decode(MCLibraryState.self, from: JSONEncoder().encode(state))
        let pasted = try #require(reloaded.entry(id)?.slots.last?.preferred)
        #expect(reloaded.chapterDisplayTitle(pasted) == "My chapter")
        #expect(pasted.edits.number == "1.5")
        #expect(pasted.edits.volume == "2")
        #expect(reloaded.chapter(pasted.chapterID)?.record.number == "2")
    }

    @Test func resetEntryAndChapterAreIndependent() throws {
        var (state, id) = try mixed()
        let first = try #require(state.entry(id)?.slots.first)
        try state.editEntry(id) { entry in
            entry.titleOverride = "Custom entry"
            entry.slots[0].variants[0].edits.title = "Custom chapter"
            entry.manualOrder = true
            entry.slots.reverse()
        }
        let order = try #require(state.entry(id)).slots.map(\.id)
        try state.resetDetails(id)
        let entry = try #require(state.entry(id))
        #expect(entry.slots.map(\.id) == order)
        #expect(entry.manualOrder)
        #expect(entry.slots.first(where: { $0.id == first.id })?.preferred?.edits.title == "Custom chapter")
        try state.editEntry(id) { $0.titleOverride = "Keep entry edit" }
        try state.resetChapterDetails(entryID: id, slotID: first.id)
        #expect(state.entry(id)?.slots.first(where: { $0.id == first.id })?.preferred?.edits.title == nil)
        #expect(state.entry(id)?.titleOverride == "Keep entry edit")
        #expect(state.entry(id)?.links.count == 2)
    }

    @Test func editedDirectChapterNumberCreatesASeparateSlot() throws {
        var (state, id) = try mixed()
        let source = try #require(state.chapters.first { $0.identity.listing.connectionID == b && $0.record.number == "20" })
        try state.addChapter(entryID: id, variant: MCChapterVariant(chapterID: source.id, edits: .init(number: "30")))
        #expect(state.entry(id)?.slots.count == 4)
        #expect(state.entry(id)?.slots.last?.preferred?.edits.number == "30")
    }

    @Test func chapterLayoutOverrideDefaultsToInheritanceAndPersists() throws {
        var state = MCLibraryState()
        let id = try state.add(details: details(), connectionID: a, records: records([1]), language: nil)
        #expect(state.entry(id)?.chapterGridOverride == nil)
        try state.editEntry(id) { $0.chapterGridOverride = false }
        let reloaded = try JSONDecoder().decode(MCLibraryState.self, from: JSONEncoder().encode(state))
        #expect(reloaded.entry(id)?.chapterGridOverride == false)
    }

    @Test func resettingChapterThumbnailsKeepsOtherChapterEdits() throws {
        var state = MCLibraryState()
        let id = try state.add(details: details(), connectionID: a, records: records([1]), language: nil)
        let cover = MCLibraryCover(data: Data([0xFF, 0xD8, 0xFF]))
        state.covers.append(cover)
        try state.editEntry(id) { entry in
            entry.slots[0].variants[0].edits = .init(title: "Keep title", number: "1.5", coverID: cover.id)
        }
        try state.resetChapterThumbnails(entryID: id)
        let edits = try #require(state.entry(id)?.slots.first?.preferred?.edits)
        #expect(edits.title == "Keep title")
        #expect(edits.number == "1.5")
        #expect(edits.coverID == nil)
        #expect(state.covers.isEmpty)
    }

    @Test func remoteCoverURLsOnlyAcceptReusableWebLinks() {
        #expect(MCRemoteCoverURL.parse(" https://images.example.com/page.jpg?token=abc ")?.host == "images.example.com")
        #expect(MCRemoteCoverURL.parse("http://images.example.com/page.png") != nil)
        #expect(MCRemoteCoverURL.parse("file:///tmp/page.jpg") == nil)
        #expect(MCRemoteCoverURL.parse("javascript:alert(1)") == nil)
        #expect(MCRemoteCoverURL.parse("not a url") == nil)
    }

    @Test func remoteCoverPersistsOnlyItsURLAndLegacyCoverStillDecodes() throws {
        let url = try #require(URL(string: "https://images.example.com/cover.jpg"))
        let remote = MCLibraryCover(url: url, sourceKey: "example", pageImage: true)
        let encoded = try JSONEncoder().encode(remote)
        let restored = try JSONDecoder().decode(MCLibraryCover.self, from: encoded)
        #expect(restored.data == nil)
        #expect(restored.url == url)
        #expect(restored.sourceKey == "example")
        #expect(restored.pageImage == true)
        let legacy = MCLibraryCover(data: Data([0xFF, 0xD8, 0xFF]))
        #expect(try JSONDecoder().decode(MCLibraryCover.self, from: JSONEncoder().encode(legacy)).data == legacy.data)
    }

}

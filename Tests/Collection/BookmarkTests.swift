import Foundation
import Testing
@testable import MidokuCollectionCore

@Suite("Chapter and panel bookmarks")
struct BookmarkTests {
    private func bookmark(kind: MCBookmarkKind? = nil, page: Int = 1, slot: UUID? = nil,
                          source: String = "source") -> MCPanelBookmark {
        .init(id: UUID(), titleKey: "title", slotID: slot, sourceKey: source, mangaKey: "manga",
              chapterKey: "chapter", chapterTitle: "Chapter 1", chapterNumber: 1,
              page: page, preview: nil, kind: kind)
    }

    @Test func legacyPanelBookmarksDecodeWithoutKind() throws {
        let original = bookmark(page: 7)
        let data = try JSONEncoder().encode(original)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["kind"] == nil)
        let decoded = try JSONDecoder().decode(MCPanelBookmark.self, from: data)
        #expect(!decoded.isChapter)
        #expect(decoded.page == 7)
        #expect(decoded.id == original.id)
    }

    @Test func chapterAndFirstPanelRemainSeparate() {
        let slot = UUID()
        let chapter = bookmark(kind: .chapter, slot: slot)
        let panel = bookmark(slot: slot)
        #expect(!chapter.replaces(panel))
        #expect(!panel.replaces(chapter))
        #expect(chapter.replaces(bookmark(kind: .chapter, page: 12, slot: slot)))
        #expect(!panel.replaces(bookmark(page: 2, slot: slot)))
    }

    @Test func duplicateDetectionPreservesSlotsAndPhysicalSources() {
        let slot = UUID()
        let chapter = bookmark(kind: .chapter, slot: slot)
        #expect(chapter.replaces(bookmark(kind: .chapter, slot: slot)))
        #expect(!chapter.replaces(bookmark(kind: .chapter, slot: UUID())))
        #expect(!chapter.replaces(bookmark(kind: .chapter, slot: slot, source: "other")))
    }

    @Test func mixedBookmarksRoundTrip() throws {
        let items = [bookmark(kind: .chapter), bookmark(page: 5)]
        let data = try JSONEncoder().encode(items)
        let decoded = try JSONDecoder().decode([MCPanelBookmark].self, from: data)
        #expect(decoded.map(\.isChapter) == [true, false])
        #expect(decoded.map(\.page) == [1, 5])
    }
}

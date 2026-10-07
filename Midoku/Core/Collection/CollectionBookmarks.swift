import Foundation

nonisolated enum MCBookmarkKind: String, Codable, Sendable {
    case panel, chapter
}

/// The original panel bookmark schema is retained so existing bookmarks decode unchanged.
nonisolated struct MCPanelBookmark: Codable, Identifiable, Sendable {
    let id: UUID
    let titleKey: String
    var title: String? = nil
    let slotID: UUID?
    let sourceKey: String
    let mangaKey: String
    let chapterKey: String
    let chapterTitle: String
    let chapterNumber: Float?
    let page: Int
    let preview: Data?
    var kind: MCBookmarkKind? = nil

    var isChapter: Bool { kind == .chapter }

    func replaces(_ other: Self) -> Bool {
        isChapter == other.isChapter && titleKey == other.titleKey && slotID == other.slotID
            && sourceKey == other.sourceKey && mangaKey == other.mangaKey
            && chapterKey == other.chapterKey && (isChapter || page == other.page)
    }
}

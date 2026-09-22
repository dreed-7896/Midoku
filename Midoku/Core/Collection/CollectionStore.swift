import AidokuRunner
import Foundation
import Observation
import UIKit

nonisolated struct MCConnection: Codable, Identifiable, Sendable {
    var id = UUID()
    var sourceKey: String
    var name: String
}

nonisolated struct MCCategory: Codable, Identifiable, Sendable, Equatable {
    var id = UUID()
    var name: String
}

nonisolated struct MCStoredManga: Codable, Sendable {
    var listingID: UUID
    var manga: AidokuRunner.Manga

    // AidokuRunner deliberately excludes sourceKey from its wire Codable model.
    // Persist it explicitly so a restart cannot detach records from their source.
    enum CodingKeys: String, CodingKey { case listingID, sourceKey, manga }
    init(listingID: UUID, manga: AidokuRunner.Manga) { self.listingID = listingID; self.manga = manga }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        listingID = try values.decode(UUID.self, forKey: .listingID)
        let sourceKey = try values.decode(String.self, forKey: .sourceKey)
        let value = try values.decode(AidokuRunner.Manga.self, forKey: .manga)
        manga = AidokuRunner.Manga(sourceKey: sourceKey, key: value.key, title: value.title, cover: value.cover,
            artists: value.artists, authors: value.authors, description: value.description, url: value.url,
            tags: value.tags, status: value.status, contentRating: value.contentRating, viewer: value.viewer,
            updateStrategy: value.updateStrategy, nextUpdateTime: value.nextUpdateTime, chapters: value.chapters)
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(listingID, forKey: .listingID)
        try values.encode(manga.sourceKey, forKey: .sourceKey)
        try values.encode(manga, forKey: .manga)
    }
}

nonisolated struct MCStoredChapter: Codable, Sendable {
    var chapterID: UUID
    var chapter: AidokuRunner.Chapter
}

nonisolated struct MCCollectionSnapshot: Codable, Sendable {
    var version = 1
    var library = MCLibraryState()
    var connections: [MCConnection] = []
    var categories: [MCCategory] = []
    var manga: [MCStoredManga] = []
    var chapters: [MCStoredChapter] = []
    var adopted: Set<MangaIdentifier> = []
    var legacyCategoriesImported: Bool?

    func validate() throws {
        guard version == 1, Set(connections.map(\.sourceKey)).count == connections.count,
              Set(connections.map(\.id)).count == connections.count,
              Set(categories.map(\.id)).count == categories.count,
              Set(manga.map(\.listingID)).count == manga.count,
              Set(chapters.map(\.chapterID)).count == chapters.count else { throw MCLibraryFailure.invalid }
        try library.validate(connections: Set(connections.map(\.id)), categories: Set(categories.map(\.id)))
        for listing in library.listings {
            guard let record = manga.first(where: { $0.listingID == listing.id }),
                  let connection = connections.first(where: { $0.id == listing.identity.connectionID }),
                  record.manga.sourceKey == connection.sourceKey, record.manga.key == listing.identity.externalID
            else { throw MCLibraryFailure.invalid }
        }
        for chapter in library.chapters {
            guard chapters.first(where: { $0.chapterID == chapter.id })?.chapter.key == chapter.identity.externalID
            else { throw MCLibraryFailure.invalid }
        }
    }

    mutating func connection(sourceKey: String, name: String) -> UUID {
        if let index = connections.firstIndex(where: { $0.sourceKey == sourceKey }) {
            connections[index].name = name
            return connections[index].id
        }
        let item = MCConnection(sourceKey: sourceKey, name: name)
        connections.append(item)
        return item.id
    }

    @discardableResult
    mutating func remember(_ value: AidokuRunner.Manga, chapters incoming: [AidokuRunner.Chapter], sourceName: String, complete: Bool) throws -> UUID {
        let connectionID = connection(sourceKey: value.sourceKey, name: sourceName)
        let details = MCMangaDetails(id: value.key, title: value.title.isEmpty ? "Untitled entry" : value.title,
            description: value.description ?? "", coverURL: value.cover.flatMap(URL.init(string:)),
            authors: value.authors, artists: value.artists, tags: value.tags, webURL: value.url)
        // The runner normalizes numeric labels; physical keys remain the stable identity.
        let records = incoming.enumerated().map { index, chapter in
            MCChapterRecord(id: chapter.key, title: chapter.title ?? "", number: chapter.chapterNumber.map { String(format: "%g", $0) },
                ordinal: index, language: chapter.language, groups: chapter.scanlators,
                volume: chapter.volumeNumber.map { String(format: "%g", $0) })
        }
        let listingID = try library.remember(details: details, connectionID: connectionID, records: records, complete: complete)
        var storedManga = value
        storedManga.chapters = nil
        if let index = manga.firstIndex(where: { $0.listingID == listingID }) { manga[index].manga = storedManga }
        else { manga.append(.init(listingID: listingID, manga: storedManga)) }
        let identity = MCSourceListingIdentity(connectionID: connectionID, externalID: value.key)
        let ids = Dictionary(uniqueKeysWithValues: library.chapters.filter { $0.identity.listing == identity }.map { ($0.record.id, $0.id) })
        for chapter in incoming {
            guard let id = ids[chapter.key] else { throw MCLibraryFailure.invalid }
            if let index = chapters.firstIndex(where: { $0.chapterID == id }) { chapters[index].chapter = chapter }
            else { chapters.append(.init(chapterID: id, chapter: chapter)) }
        }
        return listingID
    }
}

@MainActor @Observable
final class MCCollectionStore {
    static let shared = MCCollectionStore()
    private(set) var snapshot = MCCollectionSnapshot()
    var error: String?
    private(set) var isRefreshing = false
    private(set) var writable = true
    private let fileURL: URL
    @ObservationIgnored private var recentReads: [ChapterIdentifier: Date] = [:]

    var library: MCLibraryState { snapshot.library }

    init(fileURL: URL = FileManager.default.applicationSupportDirectory.appendingPathComponent("MidokuCollection.json")) {
        self.fileURL = fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let loaded = try JSONDecoder().decode(MCCollectionSnapshot.self, from: data)
            try loaded.validate()
            snapshot = loaded
        } catch {
            writable = false
            self.error = "Your library could not be opened. Its saved file has been kept. \(error.localizedDescription)"
        }
    }

    func change(_ edit: (inout MCCollectionSnapshot) throws -> Void) throws {
        guard writable else { throw MCLibraryFailure.invalid }
        var candidate = snapshot
        try edit(&candidate)
        try candidate.validate()
        let data = try JSONEncoder().encode(candidate)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
        let categoriesChanged = snapshot.categories != candidate.categories
        snapshot = candidate
        if categoriesChanged { NotificationCenter.default.post(name: .updateCategories, object: nil) }
    }

    @discardableResult
    func perform(_ edit: (inout MCCollectionSnapshot) throws -> Void) -> Bool {
        do { try change(edit); return true }
        catch { self.error = error.localizedDescription; return false }
    }

    func sourceName(_ connectionID: UUID) -> String {
        snapshot.connections.first { $0.id == connectionID }?.name ?? "Unavailable source"
    }

    func source(_ connectionID: UUID) -> AidokuRunner.Source? {
        guard let key = snapshot.connections.first(where: { $0.id == connectionID })?.sourceKey else { return nil }
        return SourceStore.shared.source(for: key)
    }

    func entryID(for manga: AidokuRunner.Manga) -> UUID? {
        guard let connection = snapshot.connections.first(where: { $0.sourceKey == manga.sourceKey }),
              let listing = library.listings.first(where: { $0.identity.connectionID == connection.id && $0.identity.externalID == manga.key }) else { return nil }
        return library.entries.first { $0.primaryListingID == listing.id }?.id
    }

    @discardableResult
    func add(_ manga: AidokuRunner.Manga, chapters: [AidokuRunner.Chapter], categories: Set<UUID> = [], status: MCPersonalStatus = .planned, follow: Bool = true,
             title: String? = nil, description: String? = nil, author: String? = nil, artist: String? = nil,
             cover: MCLibraryCover? = nil) throws -> UUID {
        if let existing = entryID(for: manga) { return existing }
        let name = SourceStore.shared.source(for: manga.sourceKey)?.name ?? manga.sourceKey
        var result = UUID()
        try change { state in
            let listingID = try state.remember(manga, chapters: chapters, sourceName: name, complete: manga.chapters != nil || !chapters.isEmpty)
            guard let listing = state.library.listing(listingID) else { throw MCLibraryFailure.missing }
            // A listing may already be a selected-only link in another entry. Explicitly adding it still creates its own entry.
            var entry = MCPersonalEntry()
            entry.primaryListingID = listingID
            entry.categoryIDs = categories
            entry.status = status
            entry.titleOverride = title
            entry.descriptionOverride = description
            entry.authorOverride = author
            entry.artistOverride = artist
            if let cover { state.library.covers.append(cover); entry.coverID = cover.id }
            entry.links = [MCEntrySourceLink(listingID: listingID, followsNewChapters: follow, needsInitialImport: chapters.isEmpty && manga.chapters == nil)]
            entry.slots = state.library.chapters.filter { $0.identity.listing == listing.identity && $0.available }
                .map { MCChapterSlot(variant: MCChapterVariant(chapterID: $0.id)) }
            state.library.sortSequence(&entry)
            state.library.entries.append(entry)
            state.adopted.insert(manga.identifier)
            result = entry.id
        }
        return result
    }

    func addChapter(_ chapter: AidokuRunner.Chapter, from manga: AidokuRunner.Manga, to entryID: UUID, title: String) throws {
        let sourceName = SourceStore.shared.source(for: manga.sourceKey)?.name ?? manga.sourceKey
        let displayTitle = chapter.formattedTitle()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw MCLibraryFailure.emptyTitle }

        try change { state in
            let listingID = try state.remember(manga, chapters: [chapter], sourceName: sourceName, complete: false)
            guard
                let listing = state.library.listing(listingID),
                let chapterID = state.library.chapters.first(where: {
                    $0.identity.listing == listing.identity && $0.record.id == chapter.key
                })?.id,
                state.library.entry(entryID) != nil
            else { throw MCLibraryFailure.missing }

            let numberedTitle = MCLibraryState.numberedTitle(from: trimmedTitle)
            let numberOverride = numberedTitle.map(\.number).map(MCLibraryState.numberString)
            let standardChapterName = numberedTitle?.prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "chapter"
            let edits = MCChapterEdits(
                title: trimmedTitle != displayTitle && !standardChapterName ? trimmedTitle : nil,
                number: numberOverride
            )
            try state.library.addChapter(
                entryID: entryID,
                variant: MCChapterVariant(chapterID: chapterID, edits: edits)
            )
        }
    }

    func suggestedChapterName(for entryID: UUID) -> String {
        (try? library.suggestedChapterName(entryID: entryID)) ?? "Chapter 1"
    }

    @discardableResult
    func removeEntries(_ ids: Set<UUID>) -> Bool {
        let removedListings = Set(library.entries.filter { ids.contains($0.id) }.compactMap(\.primaryListingID))
        guard perform({ $0.library.removeEntries(ids) }) else { return false }
        let remainingListings = Set(library.entries.compactMap(\.primaryListingID))
        let mangaIDs = snapshot.manga.filter { removedListings.contains($0.listingID) && !remainingListings.contains($0.listingID) }.map { $0.manga.identifier }
        Task {
            let stillRemoved = mangaIDs.filter { id in
                !library.entries.contains { entry in snapshot.manga.first { $0.listingID == entry.primaryListingID }?.manga.identifier == id }
            }
            do {
                try await CoreDataManager.shared.container.performBackgroundTask { context in
                    for id in stillRemoved {
                        if let bookmark = CoreDataManager.shared.getLibraryManga(mangaId: id, context: context) { context.delete(bookmark) }
                    }
                    try context.save()
                }
                for id in stillRemoved { NotificationCenter.default.post(name: .removeFromLibrary, object: id) }
                NotificationCenter.default.post(name: .updateLibrary, object: nil)
            } catch { self.error = error.localizedDescription }
        }
        return true
    }

    func refresh(entryID: UUID? = nil) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let entries = library.entries.filter { entryID == nil || $0.id == entryID }
        let listingIDs = Set(entries.flatMap(\.links).map(\.listingID))
        var failures: [String] = []
        for listingID in listingIDs {
            guard let listing = library.listing(listingID),
                  let stored = snapshot.manga.first(where: { $0.listingID == listingID }) else { continue }
            guard let source = source(listing.identity.connectionID) else {
                failures.append("\(sourceName(listing.identity.connectionID)): source unavailable")
                continue
            }
            do {
                let updated = try await source.getMangaUpdate(manga: stored.manga, needsDetails: true, needsChapters: true)
                guard let chapters = updated.chapters else { throw MCLibraryFailure.incomplete }
                try change { state in
                    _ = try state.remember(updated, chapters: chapters, sourceName: source.name, complete: true)
                    guard let current = state.library.listing(listingID) else { throw MCLibraryFailure.missing }
                    let records = state.library.chapters.filter { $0.identity.listing == current.identity && $0.available }.map(\.record)
                    try state.library.refresh(details: current.details, connectionID: current.identity.connectionID, records: records, language: nil)
                }
            } catch { failures.append("\(source.name): \(error.localizedDescription)") }
        }
        if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }

    func setRead(entryID: UUID, slotIDs: Set<UUID>, read: Bool) {
        guard let entry = library.entry(entryID) else { return }
        let identities = entry.slots.filter { slotIDs.contains($0.id) }.compactMap(\.preferred).compactMap { library.chapter($0.chapterID)?.identity }
        perform { state in
            for identity in identities {
                if read { state.library.completed.insert(identity) } else { state.library.completed.remove(identity) }
            }
            try state.library.editEntry(entryID) { entry in
                for i in entry.slots.indices where slotIDs.contains(entry.slots[i].id) { entry.slots[i].completionOverride = nil }
            }
        }
        for identity in identities {
            guard let record = physical(identity) else { continue }
            Task {
                if read { await HistoryManager.shared.addHistory(mangaId: record.manga.identifier, chapters: [record.chapter]) }
                else { await HistoryManager.shared.removeHistory(chapterIds: [.init(sourceKey: record.manga.sourceKey, mangaKey: record.manga.key, chapterKey: record.chapter.key)]) }
            }
        }
    }

    func physical(_ identity: MCSourceChapterIdentity) -> (manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter)? {
        guard let listing = library.listings.first(where: { $0.identity == identity.listing }),
              let chapter = library.chapters.first(where: { $0.identity == identity }),
              let manga = snapshot.manga.first(where: { $0.listingID == listing.id })?.manga,
              let value = snapshot.chapters.first(where: { $0.chapterID == chapter.id })?.chapter else { return nil }
        return (manga, value)
    }

    func recordRead(_ identity: ChapterIdentifier, completed: Bool? = nil) {
        if completed == nil, let recent = recentReads[identity], Date().timeIntervalSince(recent) < 30 { return }
        recentReads[identity] = Date()
        guard let connection = snapshot.connections.first(where: { $0.sourceKey == identity.sourceKey }) else { return }
        let key = MCSourceChapterIdentity(listing: .init(connectionID: connection.id, externalID: identity.mangaKey), externalID: identity.chapterKey)
        guard library.chapters.contains(where: { $0.identity == key }) else { return }
        if let completed, completed == library.completed.contains(key) { return }
        perform { state in
            if let completed {
                if completed { state.library.completed.insert(key) } else { state.library.completed.remove(key) }
            }
            for i in state.library.entries.indices {
                if state.library.entries[i].slots.contains(where: { slot in slot.preferred.flatMap { state.library.chapter($0.chapterID) }?.identity == key }) {
                    state.library.entries[i].lastReadAt = Date()
                }
            }
        }
    }

    func saveCover(data: Data) throws -> MCLibraryCover {
        guard data.count <= 20 * 1024 * 1024, let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { throw MCLibraryFailure.cover }
        let factor = min(1, 1200 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let result = resized.jpegData(compressionQuality: 0.75), result.count <= 1_048_576 else { throw MCLibraryFailure.cover }
        return MCLibraryCover(data: result)
    }

    struct CoverTarget {
        let entryID: UUID
        let slotID: UUID
        let variantID: UUID
    }

    func coverTarget(identifier: ChapterIdentifier, entryID: UUID? = nil, variantID: UUID? = nil) -> CoverTarget? {
        for entry in library.entries where entryID == nil || entry.id == entryID {
            for slot in entry.slots {
                for variant in slot.variants where variantID == nil || variant.id == variantID {
                    guard let chapter = library.chapter(variant.chapterID),
                          let physical = physical(chapter.identity),
                          physical.manga.sourceKey == identifier.sourceKey,
                          physical.manga.key == identifier.mangaKey,
                          physical.chapter.key == identifier.chapterKey else { continue }
                    return CoverTarget(entryID: entry.id, slotID: slot.id, variantID: variant.id)
                }
            }
        }
        return nil
    }

    func setCover(data: Data, target: CoverTarget, forEntry: Bool) throws {
        let cover = try saveCover(data: data)
        try change { state in
            state.library.covers.append(cover)
            try state.library.editEntry(target.entryID) { entry in
                guard let s = entry.slots.firstIndex(where: { $0.id == target.slotID }),
                      let v = entry.slots[s].variants.firstIndex(where: { $0.id == target.variantID }) else { throw MCLibraryFailure.missing }
                if forEntry { entry.coverID = cover.id; entry.hidesCover = false }
                else { entry.slots[s].variants[v].edits.coverID = cover.id }
            }
        }
    }

    func backupData() throws -> Data { try JSONEncoder().encode(snapshot) }
    func restore(_ data: Data) throws {
        let incoming = try JSONDecoder().decode(MCCollectionSnapshot.self, from: data)
        try incoming.validate()
        // Restore only after full validation; the old file survives any failed write.
        try change { $0 = incoming }
    }
}

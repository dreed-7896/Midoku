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
        let mangaByListing = Dictionary(uniqueKeysWithValues: manga.map { ($0.listingID, $0.manga) })
        let connectionsByID = Dictionary(uniqueKeysWithValues: connections.map { ($0.id, $0) })
        let chaptersByID = Dictionary(uniqueKeysWithValues: chapters.map { ($0.chapterID, $0.chapter) })
        for listing in library.listings {
            guard let record = mangaByListing[listing.id],
                  let connection = connectionsByID[listing.identity.connectionID],
                  record.sourceKey == connection.sourceKey, record.key == listing.identity.externalID
            else { throw MCLibraryFailure.invalid }
        }
        for chapter in library.chapters {
            guard chaptersByID[chapter.id]?.key == chapter.identity.externalID
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
        var chapterIndices = Dictionary(uniqueKeysWithValues: chapters.enumerated().map { ($0.element.chapterID, $0.offset) })
        for chapter in incoming {
            guard let id = ids[chapter.key] else { throw MCLibraryFailure.invalid }
            if let index = chapterIndices[id] { chapters[index].chapter = chapter }
            else {
                chapterIndices[id] = chapters.count
                chapters.append(.init(chapterID: id, chapter: chapter))
            }
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
    @ObservationIgnored private var entryChapterCounts: [UUID: (total: Int, unread: Int)] = [:]
    @ObservationIgnored private var recentReads: [ChapterIdentifier: Date] = [:]
    @ObservationIgnored private var snapshotRevision = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    var library: MCLibraryState { snapshot.library }

    var readingEntries: [MCPersonalEntry] {
        let entries = Dictionary(uniqueKeysWithValues: library.entries.map { ($0.id, $0) })
        return library.readingIDs.compactMap { entries[$0] }
    }

    @discardableResult
    func addToReading(_ ids: Set<UUID>) -> Bool {
        perform { state in
            var ordered = state.library.readingIDs
            let existing = Set(ordered)
            ordered.append(contentsOf: state.library.entries.map(\.id).filter { ids.contains($0) && !existing.contains($0) })
            state.library.readingEntryIDs = ordered
        }
    }

    @discardableResult
    func removeFromReading(_ ids: Set<UUID>) -> Bool {
        perform { $0.library.readingEntryIDs = $0.library.readingIDs.filter { !ids.contains($0) } }
    }

    @discardableResult
    func addRandomToReading(count: Int) -> Bool {
        perform { state in
            let existing = Set(state.library.readingIDs)
            let eligible = state.library.entries.map(\.id).filter { !existing.contains($0) }
            state.library.readingEntryIDs = state.library.readingIDs + Array(eligible.shuffled().prefix(max(0, count)))
        }
    }

    init(fileURL: URL = FileManager.default.applicationSupportDirectory.appendingPathComponent("MidokuCollection.json")) {
        self.fileURL = fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let loaded = try JSONDecoder().decode(MCCollectionSnapshot.self, from: data)
            try loaded.validate()
            entryChapterCounts = loaded.library.chapterCounts()
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
        candidate.library.normalizeContentOrders()
        try candidate.validate()
        let data = try JSONEncoder().encode(candidate)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
        let categoriesChanged = snapshot.categories != candidate.categories
        entryChapterCounts = candidate.library.chapterCounts()
        snapshot = candidate
        snapshotRevision += 1
        if categoriesChanged { NotificationCenter.default.post(name: .updateCategories, object: nil) }
    }

    /// Encode and validate large refreshes off the UI thread. Retry against current edits
    /// if a user changed the collection while encoding; never publish a stale snapshot.
    func changeAsync(_ edit: (inout MCCollectionSnapshot) throws -> Void) async throws {
        while true {
            try Task.checkCancellation()
            guard writable else { throw MCLibraryFailure.invalid }
            let revision = snapshotRevision
            var candidate = snapshot
            try edit(&candidate)
            candidate.library.normalizeContentOrders()
            let frozen = candidate
            let data = try await Task.detached(priority: .utility) {
                try frozen.validate()
                return try JSONEncoder().encode(frozen)
            }.value
            try Task.checkCancellation()
            guard revision == snapshotRevision else { continue }
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            let categoriesChanged = snapshot.categories != candidate.categories
            entryChapterCounts = candidate.library.chapterCounts()
            snapshot = candidate
            snapshotRevision += 1
            if categoriesChanged { NotificationCenter.default.post(name: .updateCategories, object: nil) }
            return
        }
    }

    @discardableResult
    func perform(_ edit: (inout MCCollectionSnapshot) throws -> Void) -> Bool {
        do { try change(edit); return true }
        catch { self.error = error.localizedDescription; return false }
    }

    /// Built once per saved snapshot instead of scanning every chapter on each category swipe.
    func unreadCount(entryID: UUID) -> Int { entryChapterCounts[entryID]?.unread ?? 0 }
    func chapterCount(entryID: UUID) -> Int { entryChapterCounts[entryID]?.total ?? 0 }

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

    /// Replace a source in place so the personal entry, categories and Reading order survive migration.
    func migrate(_ oldManga: AidokuRunner.Manga, to newManga: AidokuRunner.Manga,
                 chapters newChapters: [AidokuRunner.Chapter]) throws {
        guard let oldConnection = snapshot.connections.first(where: { $0.sourceKey == oldManga.sourceKey }),
              let oldListing = library.listings.first(where: {
                  $0.identity.connectionID == oldConnection.id && $0.identity.externalID == oldManga.key
              }), library.entries.contains(where: { $0.links.contains { $0.listingID == oldListing.id } })
        else { return }
        let sourceName = SourceStore.shared.source(for: newManga.sourceKey)?.name ?? newManga.sourceKey
        try change { state in
            let oldChapterRecords = Dictionary(uniqueKeysWithValues: state.library.chapters.map { ($0.id, $0) })
            let oldReadIDs = Set(state.library.chapters.filter { state.library.completed.contains($0.identity) }.map(\.id))
            let newListingID = try state.remember(newManga, chapters: newChapters, sourceName: sourceName, complete: true)
            guard let newListing = state.library.listing(newListingID) else { throw MCLibraryFailure.missing }
            let incoming = state.library.chapters.filter { $0.identity.listing == newListing.identity && $0.available }
            let oldIDs = Set(oldChapterRecords.values.filter { $0.identity.listing == oldListing.identity }.map(\.id))
            let numbers = Dictionary(grouping: incoming.filter { $0.record.number != nil }, by: { $0.record.number! })
            let titles = Dictionary(grouping: incoming, by: { $0.record.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
            var replacements: [UUID: MCLibraryChapter] = [:]
            for old in oldChapterRecords.values where old.identity.listing == oldListing.identity {
                let exact = incoming.first { $0.record.id == old.record.id }
                let byNumber = old.record.number.flatMap { numbers[$0] }.flatMap { $0.count == 1 ? $0.first : nil }
                let titleKey = old.record.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let byTitle = titles[titleKey].flatMap { $0.count == 1 ? $0.first : nil }
                if let match = exact ?? byNumber ?? byTitle { replacements[old.id] = match }
            }

            let affectedIDs = state.library.entries.filter { $0.links.contains { $0.listingID == oldListing.id } }.map(\.id)
            for id in affectedIDs {
                guard let index = state.library.entries.firstIndex(where: { $0.id == id }) else { continue }
                var entry = state.library.entries[index]
                let existingTarget = state.library.entries.firstIndex(where: { $0.id != id && $0.primaryListingID == newListingID })
                if let targetIndex = existingTarget {
                    state.library.entries[targetIndex].categoryIDs.formUnion(entry.categoryIDs)
                    if state.library.entries[targetIndex].status == .planned { state.library.entries[targetIndex].status = entry.status }
                    if state.library.readingIDs.contains(id) {
                        state.library.readingEntryIDs = state.library.readingIDs.map { $0 == id ? state.library.entries[targetIndex].id : $0 }
                        var seen = Set<UUID>()
                        state.library.readingEntryIDs = state.library.readingIDs.filter { seen.insert($0).inserted }
                    }
                    for slot in entry.slots where state.library.isRead(slot) {
                        for variant in slot.variants where oldIDs.contains(variant.chapterID) {
                            if let replacement = replacements[variant.chapterID] { state.library.completed.insert(replacement.identity) }
                        }
                    }
                    state.library.removeEntries([id])
                    continue
                }
                let oldLink = entry.links.first { $0.listingID == oldListing.id }
                entry.links.removeAll { $0.listingID == oldListing.id }
                if !entry.links.contains(where: { $0.listingID == newListingID }) {
                    entry.links.append(MCEntrySourceLink(listingID: newListingID,
                        followsNewChapters: oldLink?.followsNewChapters ?? true,
                        language: newChapters.first?.language, needsInitialImport: false))
                }
                if entry.primaryListingID == oldListing.id { entry.primaryListingID = newListingID }
                entry.exclusions.subtract(oldIDs)
                let incomingIDs = Set(incoming.map(\.id))
                var used = Set(entry.slots.flatMap(\.variants).map(\.chapterID).filter { incomingIDs.contains($0) })
                entry.slots = entry.slots.compactMap { original in
                    var slot = original
                    let wasRead = state.library.isRead(original)
                    slot.variants = original.variants.compactMap { variant in
                        guard oldIDs.contains(variant.chapterID) else { return variant }
                        guard let replacement = replacements[variant.chapterID], used.insert(replacement.id).inserted else { return nil }
                        if wasRead || oldReadIDs.contains(variant.chapterID) { state.library.completed.insert(replacement.identity) }
                        var updated = variant
                        updated.chapterID = replacement.id
                        return updated
                    }
                    guard let first = slot.variants.first else { return nil }
                    if !slot.variants.contains(where: { $0.id == slot.preferredID }) { slot.preferredID = first.id }
                    return slot
                }
                let present = Set(entry.slots.flatMap(\.variants).map(\.chapterID))
                for chapter in incoming where !present.contains(chapter.id) {
                    entry.slots.append(MCChapterSlot(variant: MCChapterVariant(chapterID: chapter.id)))
                }
                entry.sequenceRevision += 1
                entry.updatedAt = Date()
                if !entry.manualOrder { state.library.sortSequence(&entry) }
                state.library.entries[index] = entry
                state.library.updates.removeAll { $0.entryID == id && oldIDs.contains($0.chapterID) }
            }
            state.adopted.remove(oldManga.identifier)
            state.adopted.insert(newManga.identifier)
        }
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
    func removeEntries(_ selectedIDs: Set<UUID>, includingDescendants: Bool = false) -> Bool {
        var ids = selectedIDs
        if includingDescendants {
            for id in selectedIDs { ids.formUnion(library.descendantIDs(of: id)) }
        }
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
        if let refreshTask { await refreshTask.value; return }
        isRefreshing = true
        let task = Task { await refreshListings(entryID: entryID) }
        refreshTask = task
        await task.value
        refreshTask = nil
        isRefreshing = false
    }

    private func refreshListings(entryID: UUID?) async {
        let entries = library.entries.filter { entryID == nil || $0.id == entryID }
        let listingIDs = Set(entries.flatMap(\.links)
            .filter { $0.followsNewChapters || $0.needsInitialImport == true }
            .map(\.listingID))
        var failures: [String] = []
        for listingID in listingIDs {
            guard !Task.isCancelled else { break }
            guard let listing = library.listing(listingID),
                  let stored = snapshot.manga.first(where: { $0.listingID == listingID }) else { continue }
            guard let source = source(listing.identity.connectionID) else {
                failures.append("\(sourceName(listing.identity.connectionID)): source unavailable")
                continue
            }
            do {
                let updated = try await LibraryRefreshRequest.fetch(source: source, manga: stored.manga, needsDetails: true)
                guard let chapters = updated.chapters else { throw MCLibraryFailure.incomplete }
                try await changeAsync { state in
                    _ = try state.remember(updated, chapters: chapters, sourceName: source.name, complete: true)
                    guard let current = state.library.listing(listingID) else { throw MCLibraryFailure.missing }
                    let records = state.library.chapters.filter { $0.identity.listing == current.identity && $0.available }.map(\.record)
                    try state.library.refresh(details: current.details, connectionID: current.identity.connectionID, records: records, language: nil)
                }
            } catch { failures.append("\(source.name): \(error.localizedDescription)") }
        }
        if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }

    func resumeSlot(entryID: UUID) async -> UUID? {
        guard let entry = library.entry(entryID) else { return nil }
        let chapterIDs = Set(library.flattenedChapters(entryID: entry.id).compactMap(\.slot.preferred).map(\.chapterID))
        let identities = library.chapters.filter { chapterIDs.contains($0.id) }.map(\.identity)
        let connections = Dictionary(uniqueKeysWithValues: snapshot.connections.map { ($0.id, $0.sourceKey) })
        let listingIDs = Set(identities.map(\.listing))
        let mangaIDs = listingIDs.compactMap { id -> MangaIdentifier? in
            guard let sourceKey = connections[id.connectionID] else { return nil }
            return MangaIdentifier(sourceKey: sourceKey, mangaKey: id.externalID)
        }
        let positions = await CoreDataManager.shared.container.performBackgroundTask { context in
            mangaIDs.flatMap { id -> [MCReadingPosition] in
                guard let connectionID = listingIDs.first(where: {
                    connections[$0.connectionID] == id.sourceKey && $0.externalID == id.mangaKey
                })?.connectionID else { return [] }
                return CoreDataManager.shared.getHistoryForManga(mangaId: id, context: context).compactMap { history in
                    guard let date = history.dateRead else { return nil }
                    return MCReadingPosition(id: .init(listing: .init(connectionID: connectionID, externalID: id.mangaKey),
                        externalID: history.chapterId), updatedAt: date)
                }
            }
        }
        guard let current = library.entry(entryID) else { return nil }
        return library.resumeSlot(current, positions: positions)
    }

    func setRead(entryID: UUID, slotIDs: Set<UUID>, read: Bool) {
        setRead(selections: [entryID: slotIDs], read: read)
    }

    func setRead(entryIDs: Set<UUID>, read: Bool) {
        let selections = Dictionary(uniqueKeysWithValues: library.entries.filter { entryIDs.contains($0.id) }
            .map { ($0.id, Set(library.flattenedChapters(entryID: $0.id).map(\.slot.id))) })
        setRead(selections: selections, read: read)
    }

    private func setRead(selections: [UUID: Set<UUID>], read: Bool) {
        var identities = Set<MCSourceChapterIdentity>()
        guard perform({ state in
            for (entryID, slotIDs) in selections {
                identities.formUnion(try state.library.setRead(entryID: entryID, slotIDs: slotIDs, read: read))
            }
        }) else { return }
        let records = identities.compactMap { physical($0) }
        Task {
            for group in Dictionary(grouping: records, by: { $0.manga.identifier }).values {
                guard let first = group.first else { continue }
                if read {
                    await HistoryManager.shared.addHistory(mangaId: first.manga.identifier, chapters: group.map(\.chapter))
                } else {
                    await HistoryManager.shared.removeHistory(chapterIds: group.map {
                        .init(sourceKey: $0.manga.sourceKey, mangaKey: $0.manga.key, chapterKey: $0.chapter.key)
                    })
                }
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
        guard let chapterID = library.chapters.first(where: { $0.identity == key })?.id else { return }
        if let completed, completed == library.completed.contains(key) { return }
        perform { state in
            if let completed {
                if completed { state.library.completed.insert(key) } else { state.library.completed.remove(key) }
            }
            let owners = state.library.entries.filter { $0.slots.contains { $0.preferred?.chapterID == chapterID } }.map(\.id)
            var affected = Set(owners)
            for owner in owners { affected.formUnion(state.library.ancestorIDs(of: owner)) }
            for i in state.library.entries.indices where affected.contains(state.library.entries[i].id) {
                state.library.entries[i].lastReadAt = Date()
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

    func setCover(url: URL, sourceKey: String?, target: CoverTarget, forEntry: Bool, pageImage: Bool = false) throws {
        guard let parsed = MCRemoteCoverURL.parse(url.absoluteString), parsed == url else { throw MCLibraryFailure.coverURL }
        let cover = MCLibraryCover(url: url, sourceKey: sourceKey, pageImage: pageImage)
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

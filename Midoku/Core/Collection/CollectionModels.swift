import Foundation
import CryptoKit

nonisolated enum MCPersonalStatus: String, MCSettingChoice {
    case planned, reading, completed, onHold, dropped
    var title: String { self == .onHold ? "On hold" : rawValue.capitalized }
}

nonisolated enum MCChapterDisplaySort: String, Codable, CaseIterable, Identifiable, Sendable {
    case custom, numberAscending, numberDescending, titleAscending, titleDescending, unreadFirst
    var id: String { rawValue }
    var title: String {
        switch self {
        case .custom: "Personal order"
        case .numberAscending: "Chapter number (first to last)"
        case .numberDescending: "Chapter number (last to first)"
        case .titleAscending: "Title (A to Z)"
        case .titleDescending: "Title (Z to A)"
        case .unreadFirst: "Unread first"
        }
    }
}

nonisolated struct MCLibraryListing: Codable, Identifiable, Sendable {
    var id = UUID()
    let identity: MCSourceListingIdentity
    var details: MCMangaDetails
    var refreshedAt: Date?
    var lastError: String?
}

nonisolated struct MCLibraryChapter: Codable, Identifiable, Sendable {
    var id = UUID()
    let identity: MCSourceChapterIdentity
    var record: MCChapterRecord
    var available = true
}

nonisolated struct MCEntrySourceLink: Codable, Identifiable, Sendable {
    var id = UUID()
    var listingID: UUID
    var followsNewChapters: Bool
    var language: String?
    var followBaseline: Set<UUID>? = nil
    // A partial initial add still imports the existing catalogue when following is off.
    var needsInitialImport: Bool? = nil
}

/// nil inherits; an empty string deliberately clears a field. Source records never change.
nonisolated struct MCChapterEdits: Codable, Sendable {
    var title: String?
    var number: String?
    var volume: String?
    var coverID: UUID?
}

nonisolated struct MCChapterVariant: Codable, Identifiable, Sendable {
    var id = UUID()
    var chapterID: UUID
    var edits = MCChapterEdits()
}

nonisolated struct MCChapterSlot: Codable, Identifiable, Sendable {
    var id = UUID()
    var variants: [MCChapterVariant]
    var preferredID: UUID
    var completionOverride: Bool?
    var preferred: MCChapterVariant? { variants.first { $0.id == preferredID } }
    init(variant: MCChapterVariant) { variants = [variant]; preferredID = variant.id }
}

nonisolated struct MCPersonalEntry: Codable, Identifiable, Sendable {
    var id = UUID()
    var createdAt = Date()
    var updatedAt = Date()
    var lastReadAt: Date?
    var titleOverride: String?
    var descriptionOverride: String?
    var authorOverride: String?
    var artistOverride: String?
    var coverID: UUID?
    var hidesCover = false
    var primaryListingID: UUID?
    var status = MCPersonalStatus.planned
    var categoryIDs: Set<UUID> = []
    var links: [MCEntrySourceLink] = []
    var slots: [MCChapterSlot] = []
    var exclusions: Set<UUID> = []
    var manualOrder = false
    var sequenceRevision = 0
    var readerOverride: MCReaderPreferences?
    var descendingDisplay = false
    var chapterSort: MCChapterDisplaySort?
    /// nil follows the app-wide Appearance setting; otherwise this entry uses its own layout.
    var chapterGridOverride: Bool?
    // Optional so existing libraries and backups decode without migration.
    var parentEntryID: UUID?
    var contentOrder: [MCEntryContent]?
}

/// Remote covers keep only their URL. Older imported covers retain their image data for compatibility.
nonisolated struct MCLibraryCover: Codable, Identifiable, Sendable {
    var id = UUID()
    var data: Data? = nil
    var digest: String? = nil
    var url: URL? = nil
    var sourceKey: String? = nil
    var pageImage: Bool? = nil
    init(data: Data) {
        self.data = data
        digest = Self.hash(data)
    }
    init(url: URL, sourceKey: String?, pageImage: Bool = false) {
        self.url = url
        self.sourceKey = sourceKey
        self.pageImage = pageImage
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

nonisolated enum MCRemoteCoverURL {
    static func parse(_ value: String) -> URL? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 8192, let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else { return nil }
        return url
    }
}

nonisolated struct MCLibraryUpdate: Codable, Identifiable, Sendable {
    var id = UUID()
    var entryID: UUID
    var chapterID: UUID
    var discoveredAt = Date()
}

nonisolated struct MCLibraryState: Codable, Sendable {
    var entries: [MCPersonalEntry] = []
    var listings: [MCLibraryListing] = []
    var chapters: [MCLibraryChapter] = []
    var covers: [MCLibraryCover] = []
    var completed: Set<MCSourceChapterIdentity> = []
    var updates: [MCLibraryUpdate] = []
    // Optional for collections written before Reading mode existed.
    var readingEntryIDs: [UUID]? = nil

    var readingIDs: [UUID] { readingEntryIDs ?? [] }

    func entry(_ id: UUID) -> MCPersonalEntry? { entries.first { $0.id == id } }
    func listing(_ id: UUID?) -> MCLibraryListing? { listings.first { $0.id == id } }
    func chapter(_ id: UUID) -> MCLibraryChapter? { chapters.first { $0.id == id } }
    func title(_ entry: MCPersonalEntry) -> String { entry.titleOverride ?? listing(entry.primaryListingID)?.details.title ?? "Untitled entry" }
    func description(_ entry: MCPersonalEntry) -> String { entry.descriptionOverride ?? listing(entry.primaryListingID)?.details.description ?? "" }
    func number(_ variant: MCChapterVariant) -> String? { variant.edits.number ?? chapter(variant.chapterID)?.record.number }
    func chapterTitle(_ variant: MCChapterVariant) -> String { variant.edits.title ?? chapter(variant.chapterID)?.record.title ?? "Unavailable chapter" }
    func chapterDisplayTitle(_ variant: MCChapterVariant) -> String {
        if let title = variant.edits.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        return number(variant).flatMap { $0.isEmpty ? nil : "Chapter \($0)" } ?? chapterTitle(variant)
    }
    func isRead(_ slot: MCChapterSlot) -> Bool {
        if let override = slot.completionOverride { return override }
        guard let variant = slot.preferred, let source = chapter(variant.chapterID) else { return false }
        return completed.contains(source.identity)
    }
    func readerContext(identity: MCSourceChapterIdentity, preferredEntryID: UUID? = nil) -> (entryID: UUID, slotID: UUID)? {
        let ordered = entries.sorted { ($0.id == preferredEntryID ? 0 : 1) < ($1.id == preferredEntryID ? 0 : 1) }
        for entry in ordered {
            if let slot = entry.slots.first(where: { $0.preferred.flatMap { chapter($0.chapterID) }?.identity == identity }) {
                return (entry.id, slot.id)
            }
        }
        return nil
    }
    func resumeSlot(_ entry: MCPersonalEntry, positions: [MCReadingPosition]) -> UUID? {
        let identities = Dictionary(uniqueKeysWithValues: chapters.map { ($0.id, $0.identity) })
        let slots = Dictionary(flattenedChapters(entryID: entry.id).map(\.slot).compactMap { slot -> (MCSourceChapterIdentity, UUID)? in
            guard let variant = slot.preferred, let identity = identities[variant.chapterID] else { return nil }
            return (identity, slot.id)
        }, uniquingKeysWith: { first, _ in first })
        // Choose the most recently opened chapter; the reader restores its saved page even when completed.
        if let recent = positions.filter({ slots[$0.id] != nil }).max(by: { $0.updatedAt < $1.updatedAt }) {
            return slots[recent.id]
        }
        let sequence = flattenedChapters(entryID: entry.id).map(\.slot)
        return sequence.first(where: { slot in
            !(slot.completionOverride ?? slot.preferred.flatMap { identities[$0.chapterID] }.map(completed.contains) ?? false)
        })?.id ?? sequence.first?.id
    }

    @discardableResult
    mutating func remember(details: MCMangaDetails, connectionID: UUID, records: [MCChapterRecord], complete: Bool, language: String? = nil) throws -> UUID {
        let identity = MCSourceListingIdentity(connectionID: connectionID, externalID: details.id)
        guard Set(records.map(\.id)).count == records.count else { throw MCLibraryFailure.invalid }
        let listingID: UUID
        if let index = listings.firstIndex(where: { $0.identity == identity }) {
            listings[index].details = details
            if complete { listings[index].refreshedAt = Date(); listings[index].lastError = nil }
            listingID = listings[index].id
        } else {
            var listing = MCLibraryListing(identity: identity, details: details)
            if complete { listing.refreshedAt = Date() }
            listingID = listing.id; listings.append(listing)
        }
        let incoming = Set(records.map(\.id))
        if complete {
            for index in chapters.indices where chapters[index].identity.listing == identity && (language == nil || chapters[index].record.language == language) {
                chapters[index].available = incoming.contains(chapters[index].record.id)
            }
        }
        var chapterIndices = Dictionary(uniqueKeysWithValues: chapters.enumerated().map { ($0.element.identity, $0.offset) })
        for record in records {
            let key = MCSourceChapterIdentity(listing: identity, externalID: record.id)
            if let index = chapterIndices[key] {
                chapters[index].record = record; chapters[index].available = true
            } else {
                chapterIndices[key] = chapters.count
                chapters.append(MCLibraryChapter(identity: key, record: record))
            }
        }
        return listingID
    }

    @discardableResult
    mutating func add(details: MCMangaDetails, connectionID: UUID, records: [MCChapterRecord], language: String?, categories: Set<UUID> = [], complete: Bool = true,
                      status: MCPersonalStatus = .planned, followsNewChapters: Bool = true) throws -> UUID {
        let listingID = try remember(details: details, connectionID: connectionID, records: records, complete: complete, language: language)
        if let existing = entries.first(where: { $0.links.contains { $0.listingID == listingID } }) { return existing.id }
        var entry = MCPersonalEntry()
        entry.primaryListingID = listingID; entry.categoryIDs = categories
        entry.links = [MCEntrySourceLink(listingID: listingID, followsNewChapters: followsNewChapters,
            language: language, needsInitialImport: !complete)]
        entry.status = status
        let keys = Set(records.map(\.id))
        entry.slots = chapters.filter { $0.identity.listing == listing(listingID)?.identity && keys.contains($0.record.id) }
            .map { MCChapterSlot(variant: MCChapterVariant(chapterID: $0.id)) }
        sortSequence(&entry)
        entries.append(entry)
        return entry.id
    }

    /// Next means the persisted reading sequence, independent of the current display sort.
    func nextSlotIDs(entryID: UUID, after slotID: UUID) -> Set<UUID> {
        let slots = flattenedChapters(entryID: entryID).map(\.slot)
        guard let index = slots.firstIndex(where: { $0.id == slotID }) else { return [] }
        return Set(slots.dropFirst(index + 1).map(\.id))
    }

    @discardableResult
    mutating func setRead(entryID: UUID, slotIDs: Set<UUID>, read: Bool) throws -> Set<MCSourceChapterIdentity> {
        guard entry(entryID) != nil else { throw MCLibraryFailure.missing }
        let selected = flattenedChapters(entryID: entryID).filter { slotIDs.contains($0.slot.id) }
        let identities = Set(selected.compactMap(\.slot.preferred).compactMap { chapter($0.chapterID)?.identity })
        if read { completed.formUnion(identities) } else { completed.subtract(identities) }
        for (owner, values) in Dictionary(grouping: selected, by: \.entryID) {
            let ids = Set(values.map(\.slot.id))
            try editEntry(owner) { entry in
                for index in entry.slots.indices where ids.contains(entry.slots[index].id) {
                    entry.slots[index].completionOverride = nil
                }
            }
        }
        return identities
    }

    mutating func resetCover(entryID: UUID) throws {
        try editEntry(entryID) { entry in entry.coverID = nil; entry.hidesCover = false }
    }

    /// Reset presentation overrides without rebuilding or discarding the mixed-source composition.
    mutating func resetDetails(_ id: UUID) throws {
        try editEntry(id) { entry in
            if entry.primaryListingID != nil {
                entry.titleOverride = nil; entry.descriptionOverride = nil; entry.authorOverride = nil; entry.artistOverride = nil
            } else {
                entry.descriptionOverride = nil; entry.authorOverride = nil; entry.artistOverride = nil
            }
            entry.coverID = nil; entry.hidesCover = false
        }
    }

    mutating func resetChapterDetails(entryID: UUID, slotID: UUID) throws {
        try editEntry(entryID) { entry in
            guard let s = entry.slots.firstIndex(where: { $0.id == slotID }),
                  let v = entry.slots[s].variants.firstIndex(where: { $0.id == entry.slots[s].preferredID })
            else { throw MCLibraryFailure.missing }
            entry.slots[s].variants[v].edits = MCChapterEdits()
        }
    }

    /// Clears chapter artwork overrides for one entry without changing any other chapter edits.
    mutating func resetChapterThumbnails(entryID: UUID, slotIDs: Set<UUID>? = nil) throws {
        try editEntry(entryID) { entry in
            for slot in entry.slots.indices where slotIDs == nil || slotIDs!.contains(entry.slots[slot].id) {
                for variant in entry.slots[slot].variants.indices {
                    entry.slots[slot].variants[variant].edits.coverID = nil
                }
            }
        }
        let usedCoverIDs = Set(entries.compactMap(\.coverID) + entries.flatMap(\.slots).flatMap(\.variants).compactMap(\.edits.coverID))
        covers.removeAll { !usedCoverIDs.contains($0.id) }
    }

    @discardableResult
    mutating func createManual(title: String, description: String = "", categories: Set<UUID> = []) throws -> UUID {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 1000 else { throw MCLibraryFailure.emptyTitle }
        var entry = MCPersonalEntry(); entry.titleOverride = title; entry.descriptionOverride = description; entry.categoryIDs = categories
        entries.append(entry); return entry.id
    }

    mutating func editEntry(_ id: UUID, _ edit: (inout MCPersonalEntry) throws -> Void) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw MCLibraryFailure.missing }
        var candidate = entries[index]; try edit(&candidate)
        candidate.updatedAt = Date(); candidate.sequenceRevision += 1
        if !candidate.manualOrder { sortSequence(&candidate) }
        entries[index] = candidate
    }

    mutating func refresh(details: MCMangaDetails, connectionID: UUID, records: [MCChapterRecord], language: String?) throws {
        let listingID = try remember(details: details, connectionID: connectionID, records: records, complete: true, language: language)
        let identity = MCSourceListingIdentity(connectionID: connectionID, externalID: details.id)
        let incoming = chapters.filter { $0.identity.listing == identity && $0.available && (language == nil || $0.record.language == language) }
        for index in entries.indices {
            guard let link = entries[index].links.first(where: { $0.listingID == listingID }),
                  (link.followsNewChapters || link.needsInitialImport == true),
                  (language == nil || link.language == language) else { continue }
            var entry = entries[index]
            let matchingIncoming = incoming.filter { link.language == nil || $0.record.language == link.language }
            let present = Set(entry.slots.flatMap(\.variants).map(\.chapterID))
            let additions = matchingIncoming.filter { !present.contains($0.id) && !entry.exclusions.contains($0.id) && !(link.followBaseline ?? []).contains($0.id) }
            // Equal numbers stay separate; grouping always requires explicit equivalence confirmation.
            for item in additions {
                entry.slots.append(MCChapterSlot(variant: MCChapterVariant(chapterID: item.id)))
                if link.needsInitialImport != true, !updates.contains(where: { $0.entryID == entry.id && $0.chapterID == item.id }) {
                    updates.append(MCLibraryUpdate(entryID: entry.id, chapterID: item.id))
                }
            }
            if let linkIndex = entry.links.firstIndex(where: { $0.id == link.id }), entry.links[linkIndex].followBaseline != nil {
                entry.links[linkIndex].followBaseline?.formUnion(matchingIncoming.map(\.id))
            }
            if let linkIndex = entry.links.firstIndex(where: { $0.id == link.id }) { entry.links[linkIndex].needsInitialImport = false }
            if !entry.manualOrder { sortSequence(&entry) }
            entry.sequenceRevision += 1
            if !additions.isEmpty { entry.updatedAt = Date() }
            entries[index] = entry
        }
        updates = Array(updates.suffix(1000))
    }

    mutating func addChapter(entryID: UUID, variant: MCChapterVariant) throws {
        guard let source = chapter(variant.chapterID),
              let listing = listings.first(where: { $0.identity == source.identity.listing })
        else { throw MCLibraryFailure.missing }
        try editEntry(entryID) { entry in
            guard !entry.slots.flatMap(\.variants).contains(where: { $0.chapterID == source.id }) else { return }
            entry.exclusions.remove(source.id)
            if !entry.links.contains(where: { $0.listingID == listing.id }) {
                entry.links.append(MCEntrySourceLink(
                    listingID: listing.id,
                    followsNewChapters: false,
                    language: source.record.language
                ))
            }
            entry.slots.append(MCChapterSlot(variant: variant))
        }
    }

    func suggestedNextChapterNumber(entryID: UUID) throws -> Decimal {
        guard let entry = entry(entryID) else { throw MCLibraryFailure.missing }
        let numbers = entry.slots.compactMap(\.preferred).compactMap { variant -> Decimal? in
            if let value = Self.numberedTitle(from: chapterDisplayTitle(variant))?.number { return value }
            return number(variant).flatMap(Self.numeric)
        }
        return (numbers.max() ?? 0) + 1
    }

    func suggestedChapterName(entryID: UUID) throws -> String {
        guard let entry = entry(entryID) else { throw MCLibraryFailure.missing }
        let template = entry.slots.compactMap(\.preferred).compactMap { variant in
            Self.numberedTitle(from: chapterDisplayTitle(variant))
        }.max { $0.number < $1.number }
        let prefix = template?.prefix ?? "Chapter "
        return "\(prefix)\(Self.numberString(try suggestedNextChapterNumber(entryID: entryID)))"
    }

    static func numberedTitle(from title: String) -> (prefix: String, number: Decimal)? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = title.range(of: #"[+-]?[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression),
              let number = numeric(String(title[range])) else { return nil }
        return (String(title[..<range.lowerBound]), number)
    }

    static func numberString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    mutating func removeSlots(entryID: UUID, slotIDs: Set<UUID>) throws {
        try editEntry(entryID) { entry in
            entry.exclusions.formUnion(entry.slots.filter { slotIDs.contains($0.id) }.flatMap(\.variants).map(\.chapterID))
            entry.slots.removeAll { slotIDs.contains($0.id) }
        }
    }
    mutating func restoreChapter(entryID: UUID, chapterID: UUID) throws {
        guard chapter(chapterID) != nil else { throw MCLibraryFailure.missing }
        try editEntry(entryID) { entry in
            entry.exclusions.remove(chapterID)
            if !entry.slots.flatMap(\.variants).contains(where: { $0.chapterID == chapterID }) {
                entry.slots.append(MCChapterSlot(variant: MCChapterVariant(chapterID: chapterID)))
            }
        }
    }
    /// Forget a removed alternative without allowing a later source refresh to add it again.
    mutating func forgetRemovedAlternative(entryID: UUID, chapterID: UUID) throws {
        guard let entry = entry(entryID), entry.exclusions.contains(chapterID),
              let source = chapter(chapterID),
              let main = listing(entry.primaryListingID),
              let alternative = listings.first(where: { $0.identity == source.identity.listing }),
              source.identity.listing != main.identity else { throw MCLibraryFailure.invalid }
        try editEntry(entryID) { entry in
            guard let index = entry.links.firstIndex(where: { $0.listingID == alternative.id })
            else { throw MCLibraryFailure.missing }
            entry.exclusions.remove(chapterID)
            entry.links[index].followBaseline = (entry.links[index].followBaseline ?? []).union([chapterID])
        }
        updates.removeAll { $0.entryID == entryID && $0.chapterID == chapterID }
    }
    mutating func moveSlot(entryID: UUID, slotID: UUID, offset: Int) throws {
        try editEntry(entryID) { entry in
            guard let index = entry.slots.firstIndex(where: { $0.id == slotID }), entry.slots.indices.contains(index + offset) else { return }
            entry.manualOrder = true; entry.slots.swapAt(index, index + offset)
        }
    }
    mutating func removeEntries(_ selectedIDs: Set<UUID>, includingDescendants: Bool = false) {
        var ids = selectedIDs
        if includingDescendants {
            for id in selectedIDs { ids.formUnion(descendantIDs(of: id)) }
        }
        for index in entries.indices where entries[index].parentEntryID.map(ids.contains) == true && !ids.contains(entries[index].id) {
            entries[index].parentEntryID = nil
            entries[index].updatedAt = Date()
        }
        entries.removeAll { ids.contains($0.id) }
        updates.removeAll { ids.contains($0.entryID) }
        readingEntryIDs = readingIDs.filter { !ids.contains($0) }
        normalizeContentOrders()
        // Shared physical records, downloads, History and progress deliberately survive.
    }

    func sortSequence(_ entry: inout MCPersonalEntry) {
        let positions = Dictionary(uniqueKeysWithValues: entry.slots.enumerated().map { ($0.element.id, $0.offset) })
        let chaptersByID = Dictionary(uniqueKeysWithValues: chapters.map { ($0.id, $0) })
        let numbers = Dictionary(uniqueKeysWithValues: entry.slots.compactMap { slot -> (UUID, String)? in
            guard let variant = slot.preferred else { return nil }
            return (slot.id, variant.edits.number ?? chaptersByID[variant.chapterID]?.record.number ?? "")
        })
        let numericNumbers = numbers.compactMapValues(Self.numeric)
        entry.slots.sort { lhs, rhs in
            guard lhs.preferred != nil, rhs.preferred != nil else { return lhs.id.uuidString < rhs.id.uuidString }
            let ln = numbers[lhs.id] ?? "", rn = numbers[rhs.id] ?? ""
            let a = numericNumbers[lhs.id], b = numericNumbers[rhs.id]
            if let a, let b, a != b { return a < b }
            if (a != nil) != (b != nil) { return a != nil }
            if a == nil && b == nil && ln != rn {
                let order = ln.compare(rn, options: [.numeric, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                if order != .orderedSame { return order == .orderedAscending }
            }
            return (positions[lhs.id] ?? 0) < (positions[rhs.id] ?? 0)
        }
    }
    static func numeric(_ value: String) -> Decimal? {
        guard value.range(of: #"^[+-]?[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }
    static func sameNumber(_ lhs: String, _ rhs: String) -> Bool {
        if let a = numeric(lhs), let b = numeric(rhs) { return a == b }
        return lhs == rhs
    }

}

nonisolated enum MCLibraryFailure: Error, LocalizedError {
    case missing, invalid, emptyTitle, stalePreview, unresolved, excluded, incomplete, cover, coverURL, nestingCycle
    var errorDescription: String? {
        switch self {
        case .nestingCycle: "A title cannot be moved into itself or one of its nested titles."
        case .missing: "This item is no longer available. Reopen the entry and try again."
        case .invalid: "The library contains invalid or conflicting references. No changes were saved."
        case .emptyTitle: "Enter a title between 1 and 1,000 characters."
        case .stalePreview: "This entry changed while the preview was open. Close it and review the chapters again."
        case .unresolved: "Choose how to handle every possible duplicate before pasting."
        case .excluded: "Confirm that you want to restore the previously removed chapter."
        case .incomplete: "The source did not return a complete chapter list. Existing chapters are kept; try again."
        case .cover: "Choose a valid image under 20 MB. The previous cover has been kept."
        case .coverURL: "Enter a valid HTTP or HTTPS image URL."
        }
    }
}

import Foundation

/// Renames and renumbers several chapters at once, in the order given.
/// Only presentation edits change; physical chapters, progress and downloads are untouched.
nonisolated struct MCChapterBatchEdit: Sendable, Equatable {
    /// `nil` keeps titles, an empty pattern restores source titles. Tokens: `{n}` number,
    /// `{i}` position starting at 1, `{title}` the source title.
    var titlePattern: String?
    /// `nil` keeps each chapter's number.
    var startNumber: Decimal?
    var step: Decimal = 1
    /// `nil` keeps volumes, an empty value restores source volumes.
    var volume: String?
}

nonisolated struct MCChapterBatchResult: Equatable, Sendable {
    let slotID: UUID
    let title: String?
    let number: String?
    let volume: String?
}

nonisolated extension MCLibraryState {
    func batchResults(entryID: UUID, slotIDs: [UUID], edit: MCChapterBatchEdit) -> [MCChapterBatchResult] {
        guard let entry = entry(entryID) else { return [] }
        let slots = Dictionary(entry.slots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return slotIDs.enumerated().compactMap { offset, slotID in
            guard let variant = slots[slotID]?.preferred else { return nil }
            let record = chapter(variant.chapterID)?.record
            let newNumber: String? = edit.startNumber.map { Self.numberString($0 + edit.step * Decimal(offset)) }
                ?? self.number(variant)
            let title: String? = edit.titlePattern.map { pattern in
                pattern.replacingOccurrences(of: "{n}", with: newNumber ?? "")
                    .replacingOccurrences(of: "{i}", with: String(offset + 1))
                    .replacingOccurrences(of: "{title}", with: record?.title ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return MCChapterBatchResult(slotID: slotID, title: title, number: newNumber, volume: edit.volume)
        }
    }

    mutating func applyBatchEdit(entryID: UUID, slotIDs: [UUID], edit: MCChapterBatchEdit) throws {
        let results = batchResults(entryID: entryID, slotIDs: slotIDs, edit: edit)
        guard !results.isEmpty else { throw MCLibraryFailure.missing }
        let byID = Dictionary(results.map { ($0.slotID, $0) }, uniquingKeysWith: { first, _ in first })
        try editEntry(entryID) { entry in
            for s in entry.slots.indices {
                guard let result = byID[entry.slots[s].id],
                      let v = entry.slots[s].variants.firstIndex(where: { $0.id == entry.slots[s].preferredID }) else { continue }
                if edit.titlePattern != nil {
                    entry.slots[s].variants[v].edits.title = result.title?.isEmpty == false ? result.title : nil
                }
                if edit.startNumber != nil { entry.slots[s].variants[v].edits.number = result.number }
                if let volume = edit.volume { entry.slots[s].variants[v].edits.volume = volume.isEmpty ? nil : volume }
            }
        }
    }
}

nonisolated extension MCLibraryState {
    /// A comparison key that ignores case, accents, punctuation, bracketed notes and a leading "the".
    static func duplicateKey(_ title: String) -> String {
        var value = title.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        value = value.replacingOccurrences(of: #"[\(\[\{【（][^\)\]\}】）]*[\)\]\}】）]"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: "&", with: " and ")
        let words = value.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return (words.first == "the" && words.count > 1 ? Array(words.dropFirst()) : words).joined(separator: " ")
    }

    /// Titles that look like the same series, matched on their own title or any linked source title.
    /// A title is never matched with a title nested inside it. Groups follow library order.
    func duplicateGroups() -> [[UUID]] {
        var owners: [String: [Int]] = [:]
        for (offset, entry) in entries.enumerated() {
            let titles = [title(entry)] + entry.links.compactMap { listing($0.listingID)?.details.title }
            for key in Set(titles.map(Self.duplicateKey)) where key.count >= 2 { owners[key, default: []].append(offset) }
        }
        // Union titles that share any key.
        var parent = Array(entries.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index { parent[index] = parent[parent[index]]; index = parent[index] }
            return index
        }
        for members in owners.values where members.count > 1 {
            for member in members.dropFirst() { parent[root(member)] = root(members[0]) }
        }
        var groups: [Int: [Int]] = [:]
        for index in entries.indices { groups[root(index), default: []].append(index) }
        return groups.values.compactMap { members -> (Int, [UUID])? in
            let ids = members.map { entries[$0].id }
            let idSet = Set(ids)
            let unrelated = ids.filter { id in idSet.isDisjoint(with: ancestorIDs(of: id)) }
            return unrelated.count > 1 ? (members.min() ?? 0, unrelated) : nil
        }.sorted { $0.0 < $1.0 }.map(\.1)
    }
}

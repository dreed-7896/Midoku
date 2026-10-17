import Foundation

/// One-based source page numbers, before any exclusions. A nil end follows future pages.
nonisolated struct MCPageRange: Codable, Equatable, Sendable {
    var start: Int
    var end: Int?
    var text: String { end == start ? "\(start)" : "\(start)-\(end.map(String.init) ?? "")" }
    func contains(_ page: Int) -> Bool { page >= start && (end.map { page <= $0 } ?? true) }

    static func parse(_ text: String, disjoint: Bool = false) throws -> [Self] {
        guard text.count <= 10_000 else { throw MCPageRangeError.invalid }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        let ranges = try text.split(separator: ",", omittingEmptySubsequences: false).map { token -> Self in
            let parts = token.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-", omittingEmptySubsequences: false)
            func number(_ value: Substring) throws -> Int {
                let value = value.trimmingCharacters(in: .whitespaces)
                guard !value.isEmpty, value.allSatisfy(\.isNumber), let number = Int(value), (1...1_000_000).contains(number) else { throw MCPageRangeError.invalid }
                return number
            }
            guard (1...2).contains(parts.count) else { throw MCPageRangeError.invalid }
            let start = try number(parts[0])
            let end: Int? = parts.count == 1 ? start : (parts[1].trimmingCharacters(in: .whitespaces).isEmpty ? nil : try number(parts[1]))
            guard end.map({ $0 >= start }) ?? true else { throw MCPageRangeError.invalid }
            return Self(start: start, end: end)
        }
        guard ranges.count <= 500 else { throw MCPageRangeError.invalid }
        if disjoint {
            for pair in zip(ranges, ranges.dropFirst()) {
                guard let end = pair.0.end, end < pair.1.start else { throw MCPageRangeError.overlap }
            }
        }
        return ranges
    }
}

nonisolated enum MCPageRangeError: LocalizedError {
    case invalid, overlap, variants
    var errorDescription: String? {
        switch self {
        case .invalid: "Use page numbers or ranges such as 1-20,21-45,46-. Pages start at 1."
        case .overlap: "Split ranges must be in page order without overlaps. Only the last range can be open-ended."
        case .variants: "Separate alternate chapter variants before splitting this chapter."
        }
    }
}

nonisolated struct MCChapterPageSelection: Codable, Sendable {
    var originID: UUID
    var ranges: [MCPageRange]
    var excluded: [MCPageRange]
    var part: Int
    var originalEdits: MCChapterEdits

    var signature: String { ranges.map(\.text).joined(separator: ",") + "|" + excluded.map(\.text).joined(separator: ",") + "|\(part)" }

    func sourcePage(for relativePage: Int) -> Int? {
        guard relativePage > 0, ranges.isEmpty || ranges.indices.contains(part) else { return nil }
        let range = ranges.isEmpty ? MCPageRange(start: 1, end: nil) : ranges[part]
        var remaining = relativePage
        var cursor = range.start
        // Merge overlapping exclusions by advancing the cursor only once.
        for exclusion in excluded.sorted(by: { $0.start < $1.start }) {
            let end = min(exclusion.end ?? Int.max, range.end ?? Int.max)
            guard end >= cursor else { continue }
            let start = max(cursor, exclusion.start)
            if remaining <= start - cursor { break }
            remaining -= start - cursor
            guard end < Int.max else { return nil }
            cursor = end + 1
        }
        let page = cursor + remaining - 1
        return range.contains(page) ? page : nil
    }

    func indices(pageCount: Int) -> [Int] {
        guard pageCount > 0 else { return [] }
        guard ranges.isEmpty || ranges.indices.contains(part) else { return [] }
        let range = ranges.isEmpty ? MCPageRange(start: 1, end: nil) : ranges[part]
        return (0..<pageCount).filter { index in range.contains(index + 1) && !excluded.contains(where: { $0.contains(index + 1) }) }
    }
}

nonisolated extension MCLibraryState {
    /// Reuses existing part identities and their edits. Clearing ranges rejoins the source chapter.
    mutating func setChapterPages(entryID: UUID, slotID: UUID, ranges: [MCPageRange], excluded: [MCPageRange]) throws {
        guard let entry = entry(entryID), let slot = entry.slots.first(where: { $0.id == slotID }), let variant = slot.preferred else { throw MCLibraryFailure.missing }
        let old = variant.pageSelection
        if old == nil && ranges.isEmpty && excluded.isEmpty { return }
        if old?.ranges == ranges && old?.excluded == excluded { return }
        guard slot.variants.count == 1 else { throw MCPageRangeError.variants }
        let group = old?.originID ?? variant.id
        let siblings = entry.slots.filter { $0.preferred?.pageSelection?.originID == group || $0.id == slotID }
            .sorted { ($0.preferred?.pageSelection?.part ?? 0) < ($1.preferred?.pageSelection?.part ?? 0) }
        guard let first = siblings.first, let base = first.preferred else { throw MCLibraryFailure.missing }
        let original = old?.originalEdits ?? base.edits
        let baseTitle = original.title ?? chapter(variant.chapterID)?.record.title ?? "Chapter"
        let siblingIDs = Set(siblings.map(\.id))
        let replacements: [MCChapterSlot] = (0..<max(1, ranges.count)).map { part in
            var result = siblings.first(where: { ($0.preferred?.pageSelection?.part ?? 0) == part }) ?? MCChapterSlot(variant: MCChapterVariant(chapterID: variant.chapterID))
            result.completionOverride = false
            if ranges.isEmpty {
                result.variants[0].edits = original
            } else if result.preferred?.pageSelection == nil {
                result.variants[0].edits = original
                result.variants[0].edits.title = "\(baseTitle) · Part \(part + 1)"
            }
            result.variants[0].pageSelection = ranges.isEmpty && excluded.isEmpty ? nil : .init(
                originID: group, ranges: ranges, excluded: excluded, part: part, originalEdits: original)
            return result
        }
        try editEntry(entryID) { value in
            let index = value.slots.firstIndex { siblingIDs.contains($0.id) } ?? value.slots.count
            value.slots.removeAll { siblingIDs.contains($0.id) }
            value.slots.insert(contentsOf: replacements, at: min(index, value.slots.count))
            if let order = value.contentOrder {
                var result: [MCEntryContent] = []
                var inserted = false
                for item in order {
                    if case .chapter(let id) = item, siblingIDs.contains(id) {
                        if !inserted { result += replacements.map { .chapter($0.id) }; inserted = true }
                    } else { result.append(item) }
                }
                value.contentOrder = result
            }
        }
    }
}

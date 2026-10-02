import Foundation

/// Chapter slots remain owned by their title. This order only arranges the title's
/// direct children; flattening happens when a reader session is created.
nonisolated enum MCEntryContent: Codable, Hashable, Identifiable, Sendable {
    case chapter(UUID)
    case title(UUID)

    var id: Self { self }
}

nonisolated struct MCEntryChapter: Sendable {
    let entryID: UUID
    let slot: MCChapterSlot
}

nonisolated extension MCLibraryState {
    var rootEntries: [MCPersonalEntry] { entries.filter { $0.parentEntryID == nil } }

    func contents(of entry: MCPersonalEntry) -> [MCEntryContent] {
        orderedContents(of: entry, children: entries.filter { $0.parentEntryID == entry.id })
    }

    private func orderedContents(of entry: MCPersonalEntry, children: [MCPersonalEntry]) -> [MCEntryContent] {
        let available = entry.slots.map { MCEntryContent.chapter($0.id) } + children.map { .title($0.id) }
        let valid = Set(available)
        var seen = Set<MCEntryContent>()
        return ((entry.contentOrder ?? []) + available).filter { valid.contains($0) && seen.insert($0).inserted }
    }

    /// Iterative traversal supports deep nesting without using the call stack.
    func flattenedChapters(entryID: UUID) -> [MCEntryChapter] {
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let children = Dictionary(grouping: entries.filter { $0.parentEntryID != nil }, by: { $0.parentEntryID! })
        var pending: [(UUID, MCEntryContent)] = [(entryID, .title(entryID))]
        var visited = Set<UUID>()
        var result: [MCEntryChapter] = []
        let slots = Dictionary(uniqueKeysWithValues: entries.flatMap(\.slots).map { ($0.id, $0) })
        while let (owner, item) = pending.popLast() {
            switch item {
            case .chapter(let id):
                if let slot = slots[id] { result.append(.init(entryID: owner, slot: slot)) }
            case .title(let id):
                guard visited.insert(id).inserted, let entry = byID[id] else { continue }
                pending.append(contentsOf: orderedContents(of: entry, children: children[id] ?? []).reversed().map { (id, $0) })
            }
        }
        return result
    }

    /// Closest parent first. Invalid imported cycles are rejected by validate().
    func ancestorIDs(of id: UUID) -> [UUID] {
        let parents = Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
            entry.parentEntryID.map { (entry.id, $0) }
        })
        var result: [UUID] = [], visited: Set<UUID> = [id]
        var current = parents[id]
        while let parent = current, visited.insert(parent).inserted {
            result.append(parent)
            current = parents[parent]
        }
        return result
    }

    func parentPath(of entry: MCPersonalEntry) -> String? {
        let titles = ancestorIDs(of: entry.id).reversed().compactMap { self.entry($0).map(title) }
        return titles.isEmpty ? nil : titles.joined(separator: " > ")
    }

    func descendantIDs(of id: UUID) -> Set<UUID> {
        let children = Dictionary(grouping: entries.filter { $0.parentEntryID != nil }, by: { $0.parentEntryID! })
        var pending = [id], visited: Set<UUID> = [id]
        while let next = pending.popLast() {
            for child in children[next] ?? [] where visited.insert(child.id).inserted { pending.append(child.id) }
        }
        visited.remove(id)
        return visited
    }

    func canMove(_ id: UUID, into parentID: UUID) -> Bool {
        entry(id) != nil && entry(parentID) != nil && id != parentID && !ancestorIDs(of: parentID).contains(id)
    }

    mutating func moveEntry(_ id: UUID, into parentID: UUID?) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw MCLibraryFailure.missing }
        if let parentID, !canMove(id, into: parentID) { throw MCLibraryFailure.nestingCycle }
        guard entries[index].parentEntryID != parentID else { return }
        let oldParent = entries[index].parentEntryID
        // Freeze the parent's current order before inserting the new child.
        if let parentID, let parent = entry(parentID) {
            let order = contents(of: parent) + [.title(id)]
            try editEntry(parentID) { $0.manualOrder = true; $0.contentOrder = order }
        }
        entries[index].parentEntryID = parentID
        entries[index].updatedAt = Date()
        entries[index].sequenceRevision += 1
        if let oldParent {
            try editEntry(oldParent) { $0.contentOrder?.removeAll { $0 == .title(id) } }
        }
    }

    mutating func reorderContents(entryID: UUID, order: [MCEntryContent]) throws {
        guard let entry = entry(entryID) else { throw MCLibraryFailure.missing }
        guard order.count == Set(order).count, Set(order) == Set(contents(of: entry)) else { throw MCLibraryFailure.stalePreview }
        try editEntry(entryID) { $0.manualOrder = true; $0.contentOrder = order }
    }

    /// Order references are hints: deleted slots disappear and newly fetched chapters append.
    /// Parent links are authoritative, including when merging an older backup.
    mutating func normalizeContentOrders() {
        let children = Dictionary(grouping: entries.filter { $0.parentEntryID != nil }, by: { $0.parentEntryID! })
        for i in entries.indices where entries[i].contentOrder != nil {
            entries[i].contentOrder = orderedContents(of: entries[i], children: children[entries[i].id] ?? [])
        }
    }

    /// Aggregate once per saved snapshot; category swipes do not rescan descendants.
    func chapterCounts() -> [UUID: (total: Int, unread: Int)] {
        let completedIDs = Set(chapters.filter { completed.contains($0.identity) }.map(\.id))
        let parents = Dictionary(uniqueKeysWithValues: entries.compactMap { entry in entry.parentEntryID.map { (entry.id, $0) } })
        var remaining = Dictionary(grouping: entries.filter { $0.parentEntryID != nil }, by: { $0.parentEntryID! }).mapValues(\.count)
        var counts = Dictionary(uniqueKeysWithValues: entries.map { entry in
            (entry.id, (total: entry.slots.count, unread: entry.slots.filter {
                !($0.completionOverride ?? $0.preferred.map { completedIDs.contains($0.chapterID) } ?? false)
            }.count))
        })
        var ready = entries.filter { remaining[$0.id, default: 0] == 0 }.map(\.id)
        while let id = ready.popLast(), let value = counts[id] {
            guard let parent = parents[id], let current = counts[parent] else { continue }
            counts[parent] = (current.total + value.total, current.unread + value.unread)
            remaining[parent, default: 0] -= 1
            if remaining[parent] == 0 { ready.append(parent) }
        }
        return counts
    }
}

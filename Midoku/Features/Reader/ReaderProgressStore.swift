import Foundation

/// An immediate local position keeps reopen/resume independent of background
/// Core Data saves and remote completion updates. All keys are physical chapters.
@MainActor
enum ReaderProgressStore {
    struct Position: Codable, Sendable {
        let identifier: ChapterIdentifier
        let page: Int
        let scrollPosition: Double?
        let updatedAt: Date
        let slotID: UUID?
        var selectionSignature: String? = nil
    }

    private static let writer = DispatchQueue(label: "Midoku.reader-progress", qos: .utility)
    private static var isDirty = false
    private static let key = "Reader.lastPositions.v1"
    private static var positions: [ChapterIdentifier: Position] = {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([Position].self, from: data) else { return [:] }
        return Dictionary(saved.map { ($0.identifier, $0) }, uniquingKeysWith: { _, last in last })
    }()

    private static let slotKey = "Reader.slotPositions.v1"
    private static var slotPositions: [UUID: Position] = {
        guard let data = UserDefaults.standard.data(forKey: slotKey), let values = try? JSONDecoder().decode([Position].self, from: data) else { return [:] }
        return Dictionary(values.compactMap { value in value.slotID.map { ($0, value) } }, uniquingKeysWith: { _, last in last })
    }()
    static func position(for identifier: ChapterIdentifier, slotID: UUID? = nil) -> Position? {
        if let slotID { return slotPositions[slotID] }
        return positions[identifier]
    }

    static func latest(in identifiers: Set<ChapterIdentifier>) -> Position? {
        positions.values.filter { identifiers.contains($0.identifier) }.max { $0.updatedAt < $1.updatedAt }
    }

    static func record(identifier: ChapterIdentifier, page: Int, scrollPosition: Double?, slotID: UUID?, sourcePage: Int? = nil, selectionSignature: String? = nil) {
        guard page > 0, !AppSettings.general.incognitoMode.get() else { return }
        let local = Position(identifier: identifier, page: page, scrollPosition: scrollPosition,
                             updatedAt: Date(), slotID: slotID, selectionSignature: selectionSignature)
        positions[identifier] = Position(identifier: identifier, page: sourcePage ?? page,
            scrollPosition: scrollPosition, updatedAt: local.updatedAt, slotID: slotID)
        if let slotID { slotPositions[slotID] = local }
        isDirty = true
        // Reading only updates memory. The reader explicitly flushes on exit or
        // backgrounding; even a pause between swipes must not start disk work.
    }

    static func flush() {
        guard isDirty else { return }
        isDirty = false
        let snapshot = Array(positions.values)
        let slots = Array(slotPositions.values)
        let slotsKey = slotKey
        let storageKey = key
        writer.async {
            if let data = try? JSONEncoder().encode(slots) { UserDefaults.standard.set(data, forKey: slotsKey) }
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: storageKey)
            }
        }
    }

    static func remove(chapterIDs: [ChapterIdentifier]) {
        for id in chapterIDs { positions[id] = nil }
        slotPositions = slotPositions.filter { !chapterIDs.contains($0.value.identifier) }
        isDirty = true
        flush()
    }

    static func remove(mangaID: MangaIdentifier) {
        slotPositions = slotPositions.filter { $0.value.identifier.mangaIdentifier != mangaID }
        positions = positions.filter { $0.key.mangaIdentifier != mangaID }
        isDirty = true
        flush()
    }

    static func clear(keeping mangaIDs: Set<MangaIdentifier> = []) {
        slotPositions = slotPositions.filter { mangaIDs.contains($0.value.identifier.mangaIdentifier) }
        positions = positions.filter { mangaIDs.contains($0.key.mangaIdentifier) }
        isDirty = true
        flush()
    }
}

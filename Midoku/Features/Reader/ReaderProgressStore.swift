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
    }

    private static let writer = DispatchQueue(label: "Midoku.reader-progress", qos: .utility)
    private static var isDirty = false
    private static let key = "Reader.lastPositions.v1"
    private static var positions: [ChapterIdentifier: Position] = {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([Position].self, from: data) else { return [:] }
        return Dictionary(saved.map { ($0.identifier, $0) }, uniquingKeysWith: { _, last in last })
    }()

    static func position(for identifier: ChapterIdentifier) -> Position? { positions[identifier] }

    static func latest(in identifiers: Set<ChapterIdentifier>) -> Position? {
        positions.values.filter { identifiers.contains($0.identifier) }.max { $0.updatedAt < $1.updatedAt }
    }

    static func record(identifier: ChapterIdentifier, page: Int, scrollPosition: Double?, slotID: UUID?) {
        guard page > 0, !AppSettings.general.incognitoMode.get() else { return }
        positions[identifier] = Position(identifier: identifier, page: page, scrollPosition: scrollPosition,
                                         updatedAt: Date(), slotID: slotID)
        isDirty = true
        // Reading only updates memory. The reader explicitly flushes on exit or
        // backgrounding; even a pause between swipes must not start disk work.
    }

    static func flush() {
        guard isDirty else { return }
        isDirty = false
        let snapshot = Array(positions.values)
        let storageKey = key
        writer.async {
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: storageKey)
            }
        }
    }

    static func remove(chapterIDs: [ChapterIdentifier]) {
        for id in chapterIDs { positions[id] = nil }
        isDirty = true
        flush()
    }

    static func remove(mangaID: MangaIdentifier) {
        positions = positions.filter { $0.key.mangaIdentifier != mangaID }
        isDirty = true
        flush()
    }

    static func clear(keeping mangaIDs: Set<MangaIdentifier> = []) {
        positions = positions.filter { mangaIDs.contains($0.key.mangaIdentifier) }
        isDirty = true
        flush()
    }
}

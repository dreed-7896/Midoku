import CryptoKit
import Foundation

/// Keeps page translations on device for 30 days, so a page is not recognized or sent for
/// translation again when it is reopened. One small file per page, keyed by the reader's
/// translation key; saving a page again replaces its file, and expired files are removed at launch.
@MainActor
final class TranslationStore {
    static let shared = TranslationStore()
    static let lifetime: TimeInterval = 30 * 24 * 60 * 60

    private struct Entry: Codable {
        struct Region: Codable {
            let id: Int
            let imageIndex: Int
            let text: String
            let x, y, width, height: Double
        }
        let savedAt: Date
        let regions: [Region]
        let translations: [String: String]
    }

    private let directory: URL
    private let queue = DispatchQueue(label: "com.raahat.Midoku.translations", qos: .utility)
    /// Keys already looked up and not stored, so visible pages do not re-read the disk every refresh.
    private var misses = Set<String>()

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MidokuTranslations")) {
        self.directory = directory
        queue.async { Self.removeExpired(in: directory) }
    }

    func record(for key: String) -> ReaderTranslationRecord? {
        guard !misses.contains(key) else { return nil }
        guard let data = try? Data(contentsOf: file(for: key)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              Date().timeIntervalSince(entry.savedAt) < Self.lifetime else {
            misses.insert(key)
            return nil
        }
        let regions = entry.regions.map {
            TranslationRegion(id: $0.id, imageIndex: $0.imageIndex, sourceText: $0.text,
                              bounds: CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height))
        }
        let translations = Dictionary(uniqueKeysWithValues: entry.translations.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
        return ReaderTranslationRecord(regions: regions, translations: translations)
    }

    func save(_ record: ReaderTranslationRecord, for key: String) {
        let entry = Entry(
            savedAt: Date(),
            regions: record.regions.map {
                .init(id: $0.id, imageIndex: $0.imageIndex, text: $0.sourceText,
                      x: $0.bounds.minX, y: $0.bounds.minY, width: $0.bounds.width, height: $0.bounds.height)
            },
            translations: Dictionary(uniqueKeysWithValues: record.translations.map { (String($0.key), $0.value) })
        )
        guard let data = try? JSONEncoder().encode(entry) else { return }
        misses.remove(key)
        let directory = directory
        let file = file(for: key)
        queue.async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }

    private func file(for key: String) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".json")
    }

    nonisolated private static func removeExpired(in directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let cutoff = Date().addingTimeInterval(-lifetime)
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }
}

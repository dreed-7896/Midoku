import CryptoKit
import Foundation

/// Keeps page translations on device so a page is not recognized or sent for translation again
/// when it is reopened. Files are grouped in one folder per title (source and manga):
/// - titles in the library keep their translations until the entry is removed from the library;
/// - titles read without adding them are kept for 30 days.
/// Saving a page again replaces its file.
@MainActor
final class TranslationStore {
    static let shared = TranslationStore()
    /// How long translations of titles that are not in the library are kept.
    nonisolated static let browsingLifetime: TimeInterval = 30 * 24 * 60 * 60

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
    private var libraryFile: URL { directory.appendingPathComponent("library.json") }
    private let queue = DispatchQueue(label: "com.raahat.Midoku.translations", qos: .utility)
    /// Keys already looked up and not stored, so visible pages do not re-read the disk every refresh.
    private var misses = Set<String>()

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MidokuTranslations")) {
        self.directory = directory
    }

    /// The folder for a title, shared by every page key of that source and manga.
    nonisolated static func folder(sourceKey: String, mangaKey: String) -> String {
        SHA256.hash(data: Data("\(sourceKey)|\(mangaKey)".utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    func record(for key: String) -> ReaderTranslationRecord? {
        guard !misses.contains(key) else { return nil }
        let file = file(for: key)
        // Translations saved before titles had their own folder are moved into it on first use.
        let legacy = directory.appendingPathComponent(Self.name(for: key))
        let data = (try? Data(contentsOf: file)) ?? (try? Data(contentsOf: legacy)).map { data in
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: legacy, to: file)
            return data
        }
        guard let data, let entry = try? JSONDecoder().decode(Entry.self, from: data) else {
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
        let file = file(for: key)
        queue.async {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }

    /// Updates which titles are in the library. Translations of titles that were in the library
    /// and no longer are are deleted; titles never added expire after 30 days.
    func retainLibrary(folders: Set<String>) {
        misses.removeAll()
        let directory = directory
        let libraryFile = libraryFile
        queue.async {
            let previous = (try? Data(contentsOf: libraryFile)).flatMap { try? JSONDecoder().decode(Set<String>.self, from: $0) } ?? []
            let fileManager = FileManager.default
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(folders) { try? data.write(to: libraryFile, options: .atomic) }
            let cutoff = Date().addingTimeInterval(-Self.browsingLifetime)
            let items = (try? fileManager.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey])) ?? []
            for item in items where item.lastPathComponent != libraryFile.lastPathComponent && !folders.contains(item.lastPathComponent) {
                let isFolder = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                if previous.contains(item.lastPathComponent) {
                    // The entry was removed from the library.
                    try? fileManager.removeItem(at: item)
                    continue
                }
                // A title read without adding it to the library (or a translation saved before folders existed).
                let files = isFolder
                    ? (try? fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
                    : [item]
                for file in files {
                    let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    if let modified, modified < cutoff { try? fileManager.removeItem(at: file) }
                }
                if isFolder, (try? fileManager.contentsOfDirectory(atPath: item.path))?.isEmpty == true {
                    try? fileManager.removeItem(at: item)
                }
            }
        }
    }

    private func file(for key: String) -> URL {
        // Reader keys are JSON arrays that start with the source key and manga key.
        let parts = (try? JSONDecoder().decode([String].self, from: Data(key.utf8))) ?? []
        let folder = Self.folder(sourceKey: parts.first ?? "", mangaKey: parts.count > 1 ? parts[1] : "")
        return directory.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(Self.name(for: key))
    }

    private static func name(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
    }
}

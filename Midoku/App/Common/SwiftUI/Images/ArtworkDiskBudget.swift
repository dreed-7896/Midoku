import Foundation

/// Only regenerable cache files are evicted. Library covers and downloaded chapters
/// live elsewhere and are never included in this budget.
nonisolated enum ArtworkDiskBudget {
    static func trim(directory: URL, limit: Int) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: Array(keys))) ?? []
        var items = files.compactMap { url -> (url: URL, size: Int, date: Date)? in
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var size = items.reduce(0) { $0 + $1.size }
        guard size > limit else { return }
        items.sort { $0.date < $1.date }
        for item in items where size > limit {
            do { try FileManager.default.removeItem(at: item.url); size -= item.size } catch { continue }
        }
    }
}

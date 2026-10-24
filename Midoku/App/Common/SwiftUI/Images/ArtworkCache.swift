import CryptoKit
import UIKit
import Nuke

/// Keeps the final, decoded artwork independently of source headers and Cloudflare state.
/// Artwork survives source/header changes. Each image is stored exactly once: covers seen while
/// browsing live in Caches, library covers in a persistent store the system does not purge, and
/// Nuke's own disk and memory caches are bypassed for artwork so no second copy is kept.
/// A cover is only replaced when its entry is refreshed with new artwork, and the old file is removed.
@MainActor
final class MCArtworkCache {
    static let shared = MCArtworkCache()

    final class Artwork {
        let image: UIImage
        let animatedData: Data?
        init(image: UIImage, animatedData: Data? = nil) {
            self.image = image
            self.animatedData = animatedData
        }
    }

    private let memory = NSCache<NSString, Artwork>()
    private let directory: URL
    private let libraryDirectory: URL
    private let diskQueue = DispatchQueue(label: "com.raahat.Midoku.artwork-cache", qos: .utility)
    private var revisions: [String: Int] = [:]
    private var epoch = 0
    private var loads: [String: (id: UUID, task: Task<Artwork?, Never>)] = [:]
    private var reloadKeys = Set<String>()

    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MidokuArtworkCache"),
         libraryDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MidokuLibraryArtwork")) {
        self.directory = directory
        self.libraryDirectory = libraryDirectory
        memory.totalCostLimit = 96 * 1024 * 1024
    }

    static func key(url: String, sourceKey: String?, pageImage: Bool = false, width: CGFloat? = nil) -> String {
        let value = "\(sourceKey ?? "")|\(url)|\(pageImage)|\(width.map { String(Double($0)) } ?? "full")"
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func revision(for key: String) -> String { "\(epoch):\(revisions[key, default: 0])" }
    func needsReload(for key: String) -> Bool { reloadKeys.contains(key) }
    func memoryImage(for key: String) -> Artwork? { memory.object(forKey: key as NSString) }

    func image(for key: String, persistent: Bool = false) async -> Artwork? {
        if let image = memoryImage(for: key) { return image }
        let revision = revision(for: key)
        let file = directory.appendingPathComponent(key)
        let libraryFile = libraryDirectory.appendingPathComponent(key)
        let libraryDirectory = libraryDirectory
        let data: Data? = await withCheckedContinuation { continuation in
            diskQueue.async {
                if let data = try? Data(contentsOf: libraryFile) {
                    continuation.resume(returning: data)
                    return
                }
                let data = try? Data(contentsOf: file)
                if data != nil, persistent {
                    // Move artwork cached before library covers had their own store, rather than copying it.
                    Self.prepare(libraryDirectory)
                    try? FileManager.default.moveItem(at: file, to: libraryFile)
                }
                continuation.resume(returning: data)
            }
        }
        guard !Task.isCancelled, revision == self.revision(for: key), let data,
              let image = UIImage(data: data) else { return nil }
        let artwork = Artwork(image: image, animatedData: data.starts(with: [0x47, 0x49, 0x46]) ? data : nil)
        memory.setObject(artwork, forKey: key as NSString, cost: Int(image.size.width * image.size.height * 4))
        return artwork
    }

    @discardableResult
    func store(image: UIImage, animatedData: Data? = nil, for key: String, revision: String, persistent: Bool = false) -> Artwork? {
        guard revision == self.revision(for: key) else { return nil }
        reloadKeys.remove(key)
        let artwork = Artwork(image: image, animatedData: animatedData)
        memory.setObject(artwork, forKey: key as NSString, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        let target = (persistent ? libraryDirectory : directory).appendingPathComponent(key)
        let other = (persistent ? directory : libraryDirectory).appendingPathComponent(key)
        let targetDirectory = persistent ? libraryDirectory : directory
        diskQueue.async {
            if let data = animatedData ?? image.jpegData(compressionQuality: 0.9) ?? image.pngData() {
                Self.prepare(targetDirectory)
                // Atomic writes ensure reset and cache reads can never see a partial image.
                try? data.write(to: target, options: .atomic)
                try? FileManager.default.removeItem(at: other)
            }
        }
        return artwork
    }

    nonisolated private static func prepare(_ directory: URL) {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = directory
        try? directory.setResourceValues(values)
    }

    /// Cell lifetimes never own shared work. Refreshing a list cannot cancel a cover download.
    func load(key: String, persistent: Bool = false, request: @escaping @MainActor () async -> ImageRequest?) async -> Artwork? {
        if let cached = memoryImage(for: key) { return cached }
        if let pending = loads[key] { return await pending.task.value }
        let id = UUID()
        let revision = revision(for: key)
        let task = Task<Artwork?, Never> { [self] in
            if let cached = await image(for: key, persistent: persistent) { return cached }
            guard var request = await request(), !Task.isCancelled else { return nil }
            // This cache owns artwork; Nuke may still read data it stored earlier, but never keeps a copy of its own.
            request.options.insert([.disableDiskCacheWrites, .disableMemoryCacheWrites])
            do {
                let response = try await ImagePipeline.shared.imageTask(with: request).response
                guard !Task.isCancelled else { return nil }
                let artwork = store(image: response.image, animatedData: response.container.type == .gif ? response.container.data : nil,
                                    for: key, revision: revision, persistent: persistent)
                if artwork != nil { ImagePipeline.shared.cache.removeCachedData(for: request) }
                return artwork
            } catch { return nil }
        }
        loads[key] = (id, task)
        let result = await task.value
        if loads[key]?.id == id { loads[key] = nil }
        return result
    }

    func reset(_ key: String) {
        loads[key]?.task.cancel()
        loads[key] = nil
        revisions[key, default: 0] += 1
        reloadKeys.insert(key)
        memory.removeObject(forKey: key as NSString)
        let files = [directory.appendingPathComponent(key), libraryDirectory.appendingPathComponent(key)]
        diskQueue.async { for file in files { try? FileManager.default.removeItem(at: file) } }
    }

    /// Removes stored library covers that no entry shows anymore, such as removed entries
    /// or covers replaced by a refresh or a custom cover.
    func retainLibraryArtwork(_ keys: Set<String>) {
        let libraryDirectory = libraryDirectory
        diskQueue.async {
            let files = (try? FileManager.default.contentsOfDirectory(at: libraryDirectory, includingPropertiesForKeys: nil)) ?? []
            for file in files where !keys.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    var diskSize: Int {
        [directory, libraryDirectory].reduce(0) { total, directory in
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            return total + files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            diskQueue.async { continuation.resume() }
        }
    }

    func removeAll() {
        for load in loads.values { load.task.cancel() }
        loads.removeAll()
        epoch += 1
        memory.removeAllObjects()
        let directories = [directory, libraryDirectory]
        diskQueue.async { for directory in directories { try? FileManager.default.removeItem(at: directory) } }
    }
}

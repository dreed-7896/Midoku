import CryptoKit
import UIKit
import Nuke

/// Keeps the final, decoded artwork independently of source headers and Cloudflare state.
/// Artwork survives source/header changes, with a bounded disk cache.
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
    private let diskQueue = DispatchQueue(label: "com.raahat.Midoku.artwork-cache", qos: .utility)
    private var revisions: [String: Int] = [:]
    private var epoch = 0
    private var loads: [String: (id: UUID, task: Task<Artwork?, Never>)] = [:]
    private var reloadKeys = Set<String>()

    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MidokuArtworkCache")) {
        self.directory = directory
        memory.totalCostLimit = 32 * 1024 * 1024
        diskQueue.async { ArtworkDiskBudget.trim(directory: directory, limit: 100 * 1024 * 1024) }
    }

    static func key(url: String, sourceKey: String?, pageImage: Bool = false, width: CGFloat? = nil) -> String {
        let value = "\(sourceKey ?? "")|\(url)|\(pageImage)|\(width.map { String(Double($0)) } ?? "full")"
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func revision(for key: String) -> String { "\(epoch):\(revisions[key, default: 0])" }
    func needsReload(for key: String) -> Bool { reloadKeys.contains(key) }
    func memoryImage(for key: String) -> Artwork? { memory.object(forKey: key as NSString) }

    func image(for key: String) async -> Artwork? {
        if let image = memoryImage(for: key) { return image }
        let revision = revision(for: key)
        let file = directory.appendingPathComponent(key)
        let data: Data? = await withCheckedContinuation { continuation in
            diskQueue.async { continuation.resume(returning: try? Data(contentsOf: file)) }
        }
        guard !Task.isCancelled, revision == self.revision(for: key), let data,
              let image = UIImage(data: data) else { return nil }
        let artwork = Artwork(image: image, animatedData: data.starts(with: [0x47, 0x49, 0x46]) ? data : nil)
        memory.setObject(artwork, forKey: key as NSString, cost: Int(image.size.width * image.size.height * 4))
        return artwork
    }

    @discardableResult
    func store(image: UIImage, animatedData: Data? = nil, for key: String, revision: String) -> Artwork? {
        guard revision == self.revision(for: key) else { return nil }
        reloadKeys.remove(key)
        let artwork = Artwork(image: image, animatedData: animatedData)
        memory.setObject(artwork, forKey: key as NSString, cost: Int(image.size.width * image.size.height * 4))
        // Atomic writes ensure reset and cache reads can never see a partial image.
        let directory = directory
        diskQueue.async {
            if let data = animatedData ?? image.jpegData(compressionQuality: 0.85) ?? image.pngData() {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? data.write(to: directory.appendingPathComponent(key), options: .atomic)
                ArtworkDiskBudget.trim(directory: directory, limit: 100 * 1024 * 1024)
            }
        }
        return artwork
    }

    /// Cell lifetimes never own shared work. Refreshing a list cannot cancel a cover download.
    func load(key: String, request: @escaping @MainActor () async -> ImageRequest?) async -> Artwork? {
        if let cached = memoryImage(for: key) { return cached }
        if let pending = loads[key] { return await pending.task.value }
        let id = UUID()
        let revision = revision(for: key)
        let task = Task<Artwork?, Never> { [self] in
            if let cached = await image(for: key) { return cached }
            guard let request = await request(), !Task.isCancelled else { return nil }
            do {
                let response = try await ImagePipeline.shared.imageTask(with: request).response
                guard !Task.isCancelled else { return nil }
                return store(image: response.image, animatedData: response.container.type == .gif ? response.container.data : nil,
                             for: key, revision: revision)
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
        let file = directory.appendingPathComponent(key)
        diskQueue.async { try? FileManager.default.removeItem(at: file) }
    }

    var diskSize: Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
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
        let directory = directory
        diskQueue.async { try? FileManager.default.removeItem(at: directory) }
    }
}

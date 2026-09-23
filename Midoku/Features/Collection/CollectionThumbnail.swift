import AidokuRunner
import Nuke
import SwiftUI

enum MCRequestPurpose {
    @TaskLocal static var thumbnail = false
}

struct MCCustomCoverImage: View {
    let cover: MCLibraryCover
    let size: CGSize

    var body: some View {
        if let data = cover.data, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: size.width, height: size.height).clipped()
        } else if let url = cover.url {
            SourceImageView(source: cover.sourceKey.flatMap { SourceStore.shared.source(for: $0) },
                imageUrl: url.absoluteString, width: size.width, height: size.height,
                placeholder: "MidokuCoverPlaceholder", pageImage: cover.pageImage == true).clipped()
        } else {
            Image("MidokuCoverPlaceholder").resizable().scaledToFill()
                .frame(width: size.width, height: size.height).clipped()
        }
    }
}

@MainActor
final class MCThumbnailCache {
    static let shared = MCThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()
    private var active = 0
    private var tasks: [UUID: Task<UIImage?, Never>] = [:]
    private let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MidokuChapterThumbnails")

    init() { cache.totalCostLimit = 16 * 1024 * 1024 }

    /// Returns an existing generated thumbnail without starting any source or image requests.
    func cachedImage(chapterID: UUID) -> UIImage? {
        let key = chapterID.uuidString as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let file = directory.appendingPathComponent(chapterID.uuidString + ".jpg")
        guard let data = try? Data(contentsOf: file), let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key, cost: data.count)
        return image
    }

    func reset(chapterIDs: Set<UUID>) {
        for chapterID in chapterIDs {
            tasks[chapterID]?.cancel()
            tasks[chapterID] = nil
            cache.removeObject(forKey: chapterID.uuidString as NSString)
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(chapterID.uuidString + ".jpg"))
        }
    }

    func image(chapter: MCLibraryChapter, store: MCCollectionStore) async -> UIImage? {
        if let cached = cachedImage(chapterID: chapter.id) { return cached }
        let key = chapter.id.uuidString as NSString
        let file = directory.appendingPathComponent(chapter.id.uuidString + ".jpg")
        if let task = tasks[chapter.id] { return await task.value }
        guard let physical = store.physical(chapter.identity) else { return nil }
        let task = Task<UIImage?, Never> { [self] in
            while active >= 2 {
                do { try await Task.sleep(nanoseconds: 100_000_000); try Task.checkCancellation() } catch { return nil }
            }
            active += 1
            defer { active -= 1 }
            do {
                let identifier = ChapterIdentifier(sourceKey: physical.manga.sourceKey, mangaKey: physical.manga.key, chapterKey: physical.chapter.key)
                let pages: [AidokuRunner.Page]
                if DownloadManager.shared.isChapterDownloaded(chapter: identifier) {
                    pages = await DownloadManager.shared.getDownloadedPages(for: identifier)
                } else if let source = store.source(chapter.identity.listing.connectionID) {
                    pages = try await MCRequestPurpose.$thumbnail.withValue(true) { try await source.getPageList(manga: physical.manga, chapter: physical.chapter) }
                } else { return nil }
                try Task.checkCancellation()
                guard let page = pages.first else { return nil }
                let image: UIImage
                switch page.content {
                case .url(let url, let context):
                    let request = await ReaderPageView.imageRequest(url: url, context: context, sourceKey: physical.manga.sourceKey)
                    image = try await ImagePipeline.shared.image(for: request)
                case .image(let value): image = value.image
                default: return nil
                }
                try Task.checkCancellation()
                let width: CGFloat = 240
                let scaledHeight = max(1, image.size.height * width / max(1, image.size.width))
                let size = CGSize(width: width, height: min(360, scaledHeight))
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(x: 0, y: 0, width: width, height: scaledHeight)) }
                if let data = thumbnail.jpegData(compressionQuality: 0.72) {
                    cache.setObject(thumbnail, forKey: key, cost: data.count)
                    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try? data.write(to: file, options: .atomic)
                    let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
                    if files.count > 250 {
                        let ordered = files.sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
                        for old in ordered.prefix(files.count - 250) { try? FileManager.default.removeItem(at: old) }
                    }
                }
                return thumbnail
            } catch { return nil }
        }
        tasks[chapter.id] = task
        let image = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        tasks[chapter.id] = nil
        return image
    }
}

/// List rows never fetch chapter artwork. They reuse a local/generated or in-memory source
/// thumbnail when one already exists, and otherwise fall back to the entry cover.
struct MCChapterListArtwork: View {
    let entry: MCPersonalEntry
    let variant: MCChapterVariant?
    @State private var store = MCCollectionStore.shared
    @State private var cachedSourceImage: UIImage?

    private var chapter: MCLibraryChapter? { variant.flatMap { store.library.chapter($0.chapterID) } }
    private var customCover: MCLibraryCover? {
        guard let id = variant?.edits.coverID else { return nil }
        return store.library.covers.first { $0.id == id }
    }
    private var generatedImage: UIImage? {
        chapter.flatMap { MCThumbnailCache.shared.cachedImage(chapterID: $0.id) }
    }

    var body: some View {
        Group {
            if let customCover {
                GeometryReader { geometry in MCCustomCoverImage(cover: customCover, size: geometry.size) }
            } else if let image = generatedImage ?? cachedSourceImage {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                MCEntryCover(entry: entry)
            }
        }
        .clipped()
        .task(id: variant?.chapterID) {
            cachedSourceImage = nil
            guard customCover == nil, generatedImage == nil, let chapter,
                  let thumbnail = store.snapshot.chapters.first(where: { $0.chapterID == chapter.id })?.chapter.thumbnail else { return }
            cachedSourceImage = await existingSourceImage(thumbnail, chapter: chapter)
        }
        .accessibilityHidden(true)
    }

    private func existingSourceImage(_ value: String, chapter: MCLibraryChapter) async -> UIImage? {
        guard let url = URL(string: value) else { return nil }
        let request: ImageRequest
        if let fileURL = url.toMidokuFileUrl() {
            request = ImageRequest(url: fileURL)
        } else if !url.isFileURL, let source = store.source(chapter.identity.listing.connectionID) {
            var processors: [ImageProcessing] = []
            if source.features.processesCovers { processors.append(CoverInterceptorProcessor(source: source)) }
            request = ImageRequest(
                urlRequest: await source.getModifiedImageRequest(url: url, context: nil),
                processors: processors,
                userInfo: [.processesKey: source.features.processesCovers]
            )
        } else {
            request = ImageRequest(url: url)
        }
        guard ImagePipeline.shared.cache.containsCachedImage(for: request) else { return nil }
        return ImagePipeline.shared.cache.cachedImage(for: request)?.image
    }
}

struct MCChapterThumbnail: View {
    let variant: MCChapterVariant?
    @State private var store = MCCollectionStore.shared
    @State private var image: UIImage?
    @State private var visible = false
    private var chapter: MCLibraryChapter? { variant.flatMap { store.library.chapter($0.chapterID) } }
    private var customCover: MCLibraryCover? {
        guard let id = variant?.edits.coverID else { return nil }
        return store.library.covers.first { $0.id == id }
    }
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let customCover {
                    MCCustomCoverImage(cover: customCover, size: geometry.size)
                } else if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if let chapter, let thumbnail = store.snapshot.chapters.first(where: { $0.chapterID == chapter.id })?.chapter.thumbnail {
                    SourceImageView(source: store.source(chapter.identity.listing.connectionID), imageUrl: thumbnail,
                        width: geometry.size.width, height: geometry.size.height, placeholderSymbol: "photo")
                } else {
                    Color(uiColor: .secondarySystemBackground)
                        .overlay { Image(systemName: "photo").font(.title3).foregroundStyle(.tertiary) }
                }
            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .top).clipped()
        }
        .onScrollVisibilityChange(threshold: 0.1) { visible = $0 }
        .task(id: "\(variant?.chapterID.uuidString ?? "")-\(visible)") {
            guard visible, customCover == nil, let chapter,
                  store.snapshot.chapters.first(where: { $0.chapterID == chapter.id })?.chapter.thumbnail == nil else { return }
            do { try await Task.sleep(nanoseconds: 300_000_000); try Task.checkCancellation() } catch { return }
            image = await MCThumbnailCache.shared.image(chapter: chapter, store: store)
        }.accessibilityHidden(true)
    }
}

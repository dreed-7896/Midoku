import AidokuRunner
import SwiftUI

/// A reader session freezes the personal order. Display keys are local variant UUIDs;
/// network, download and history operations always resolve the physical source tuple.
@MainActor
final class MCReaderSequence {
    struct Route {
        let entryID: UUID
        let slotID: UUID
        let initiallyRead: Bool
        let identity: MCSourceChapterIdentity
        let manga: AidokuRunner.Manga
        let chapter: AidokuRunner.Chapter
        let displayChapter: AidokuRunner.Chapter
        var identifier: ChapterIdentifier {
            .init(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key)
        }
        @MainActor var source: AidokuRunner.Source? { SourceStore.shared.source(for: manga.sourceKey) }
    }
    let entryID: UUID
    let title: String
    let routes: [Route]
    let initialKey: String
    private let indices: [String: Int]
    var chapters: [AidokuRunner.Chapter] { routes.map(\.displayChapter) }

    init(entryID: UUID, slotID: UUID, initialChapterID: UUID? = nil, store: MCCollectionStore? = nil) throws {
        let store = store ?? .shared
        let rootID = store.library.ancestorIDs(of: entryID).last ?? entryID
        guard let entry = store.library.entry(rootID) else { throw MCLibraryFailure.missing }
        self.entryID = rootID
        title = store.library.title(entry)
        var routes: [Route] = []
        var initial: String?
        let chapters = Dictionary(uniqueKeysWithValues: store.library.chapters.map { ($0.id, $0) })
        let storedChapters = Dictionary(uniqueKeysWithValues: store.snapshot.chapters.map { ($0.chapterID, $0.chapter) })
        let listings = Dictionary(uniqueKeysWithValues: store.library.listings.map { ($0.identity, $0.id) })
        let manga = Dictionary(uniqueKeysWithValues: store.snapshot.manga.map { ($0.listingID, $0.manga) })
        for item in store.library.flattenedChapters(entryID: rootID) {
            let slot = item.slot
            let initialVariant = slot.id == slotID ? slot.variants.first { $0.chapterID == initialChapterID } : nil
            guard let variant = initialVariant ?? slot.preferred, let libraryChapter = chapters[variant.chapterID],
                  let original = storedChapters[libraryChapter.id],
                  let listingID = listings[libraryChapter.identity.listing], let physicalManga = manga[listingID]
            else { throw MCLibraryFailure.missing }
            let display = AidokuRunner.Chapter(key: variant.id.uuidString,
                title: variant.edits.title ?? original.title,
                chapterNumber: variant.edits.number.flatMap(Float.init) ?? original.chapterNumber,
                volumeNumber: variant.edits.volume.flatMap(Float.init) ?? original.volumeNumber,
                dateUploaded: original.dateUploaded, scanlators: original.scanlators,
                url: original.url, language: original.language, thumbnail: original.thumbnail, locked: original.locked)
            routes.append(Route(entryID: item.entryID, slotID: slot.id, initiallyRead: store.library.isRead(slot), identity: libraryChapter.identity, manga: physicalManga, chapter: original, displayChapter: display))
            if slot.id == slotID { initial = display.key }
        }
        guard let initial else { throw MCLibraryFailure.missing }
        self.routes = routes
        indices = Dictionary(uniqueKeysWithValues: routes.enumerated().map { ($0.element.displayChapter.key, $0.offset) })
        initialKey = initial
    }

    func route(_ chapter: AidokuRunner.Chapter) -> Route? { route(key: chapter.key) }
    func route(key: String) -> Route? { indices[key].map { routes[$0] } }
    func adjacent(to chapter: AidokuRunner.Chapter, offset: Int) -> AidokuRunner.Chapter? {
        guard let index = indices[chapter.key], routes.indices.contains(index + offset) else { return nil }
        return routes[index + offset].displayChapter
    }
}

struct MCReaderSheet: Identifiable, Hashable {
    let id = UUID()
    let sequence: MCReaderSequence
    var startPage: Int? = nil
    var showPanels = false

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Small, durable panel references. The preview is kept small so bookmarks do not
/// depend on the source remaining online or the image cache surviving eviction.
struct MCPanelBookmark: Codable, Identifiable {
    let id: UUID
    let titleKey: String
    var title: String? = nil
    let slotID: UUID?
    let sourceKey: String
    let mangaKey: String
    let chapterKey: String
    let chapterTitle: String
    let chapterNumber: Float?
    let page: Int
    let preview: Data?
}

@MainActor
enum MCPanelBookmarks {
    private static let key = "Reader.panelBookmarks.v1"
    static let changed = Notification.Name("MCPanelBookmarks.changed")

    static var all: [MCPanelBookmark] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([MCPanelBookmark].self, from: data)) ?? []
    }

    static func forTitle(_ titleKey: String) -> [MCPanelBookmark] {
        all.filter { $0.titleKey == titleKey }
    }

    static func add(_ bookmark: MCPanelBookmark) {
        var items = all
        items.removeAll { $0.titleKey == bookmark.titleKey && $0.slotID == bookmark.slotID
            && $0.sourceKey == bookmark.sourceKey && $0.mangaKey == bookmark.mangaKey
            && $0.chapterKey == bookmark.chapterKey && $0.page == bookmark.page }
        items.insert(bookmark, at: 0)
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static func remove(_ id: UUID) {
        UserDefaults.standard.set(try? JSONEncoder().encode(all.filter { $0.id != id }), forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static func reader(for bookmark: MCPanelBookmark) throws -> MCReaderSheet {
        let store = MCCollectionStore.shared
        guard let connection = store.snapshot.connections.first(where: { $0.sourceKey == bookmark.sourceKey }),
              let chapter = store.library.chapters.first(where: {
                  $0.identity.listing.connectionID == connection.id
                      && $0.identity.listing.externalID == bookmark.mangaKey && $0.identity.externalID == bookmark.chapterKey
              }) else { throw MCLibraryFailure.missing }
        let entries = store.library.entries.sorted { ($0.id.uuidString == bookmark.titleKey ? 0 : 1) < ($1.id.uuidString == bookmark.titleKey ? 0 : 1) }
        for entry in entries {
            let slots = store.library.flattenedChapters(entryID: entry.id).map(\.slot)
            let slot = slots.first { $0.id == bookmark.slotID && $0.variants.contains { $0.chapterID == chapter.id } }
                ?? slots.first { $0.variants.contains { $0.chapterID == chapter.id } }
            if let slot {
                return MCReaderSheet(sequence: try MCReaderSequence(entryID: entry.id, slotID: slot.id,
                                     initialChapterID: chapter.id), startPage: bookmark.page)
            }
        }
        throw MCLibraryFailure.missing
    }
}

extension ReaderViewController {
    func bookmarkPanelAction(image: UIImage, chapterKey: String, page: Int) -> UIAction {
        UIAction(title: "Bookmark panel", image: UIImage(systemName: "bookmark")) { [weak self] _ in
            guard let self, page > 0 else { return }
            let route = collectionSequence?.route(key: chapterKey)
            let identity = route?.identifier ?? ChapterIdentifier(sourceKey: manga.sourceKey,
                mangaKey: manga.key, chapterKey: chapterKey)
            let display = route?.displayChapter ?? chapter
            let size = CGSize(width: 160, height: max(1, min(240, 160 * image.size.height / max(1, image.size.width))))
            let preview = UIGraphicsImageRenderer(size: size).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }.jpegData(compressionQuality: 0.55)
            MCPanelBookmarks.add(.init(id: UUID(), titleKey: collectionSequence?.entryID.uuidString ?? "\(manga.sourceKey):\(manga.key)",
                title: collectionSequence?.title ?? manga.title,
                slotID: route?.slotID,
                sourceKey: identity.sourceKey, mangaKey: identity.mangaKey, chapterKey: identity.chapterKey,
                chapterTitle: display.title ?? "Chapter", chapterNumber: display.chapterNumber,
                page: page, preview: preview))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    func collectionCoverActions(image: UIImage, chapterKey: String, imageURL: String?) -> [UIAction] {
        let store = MCCollectionStore.shared
        let route = collectionSequence?.route(key: chapterKey)
        let identity = route?.identifier ?? ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapterKey)
        let target = collectionSequence != nil && route == nil ? nil : store.coverTarget(identifier: identity, entryID: route?.entryID,
                                      variantID: collectionSequence == nil ? nil : UUID(uuidString: chapterKey))
        // Freeze the pressed page's target. Infinite scrolling may already be displaying another chapter.
        var actions: [UIAction] = []
        if let imageURL, let url = MCRemoteCoverURL.parse(imageURL) {
            actions.append(UIAction(title: "Copy URL", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = url.absoluteString
                UISelectionFeedbackGenerator().selectionChanged()
            })
        }
        actions += [false, true].map { forEntry in
            let action = UIAction(title: forEntry ? "Set as entry cover" : "Set as chapter cover",
                                  image: UIImage(systemName: forEntry ? "book.closed" : "photo"),
                                  attributes: target == nil || imageURL.flatMap(MCRemoteCoverURL.parse) == nil ? .disabled : []) { [weak self] _ in
                guard let target, let imageURL, let url = MCRemoteCoverURL.parse(imageURL) else { return }
                do {
                    try store.setCover(url: url, sourceKey: identity.sourceKey, target: target, forEntry: forEntry, pageImage: true)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } catch {
                    let alert = UIAlertController(title: "Cover could not be saved", message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(alert, animated: true)
                }
            }
            if target == nil { action.subtitle = "Add this title to Library first" }
            else if imageURL.flatMap(MCRemoteCoverURL.parse) == nil { action.subtitle = "This page has no reusable image URL" }
            return action
        }
        return actions
    }
}

struct MCReaderView: UIViewControllerRepresentable {
    let sequence: MCReaderSequence
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> ReaderViewController {
        guard let route = sequence.route(key: sequence.initialKey) else { preconditionFailure("Validated reader route missing") }
        let reader = ReaderViewController(source: route.source, manga: route.manga, chapter: route.displayChapter,
                                          startPage: startPage, collectionSequence: sequence)
        reader.showPanelsOnOpen = showPanels
        reader.isNavigationPage = true
        reader.goBack = { dismiss() }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--reader-preview") {
            Task { @MainActor [weak reader] in
                try? await Task.sleep(for: .seconds(1))
                reader?.showBars()
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--reader-hidden-preview") {
            Task { @MainActor [weak reader] in
                try? await Task.sleep(for: .seconds(2))
                reader?.hideBars()
            }
        }
        #endif
        return reader
    }
    func updateUIViewController(_ uiViewController: ReaderViewController, context: Context) {}
    var startPage: Int? = nil
    var showPanels = false
}

/// The reader is a destination in the existing stack, so UIKit owns back swipes.
struct MCReaderPresentation: ViewModifier {
    @Binding var sheet: MCReaderSheet?

    func body(content: Content) -> some View {
        content.navigationDestination(item: $sheet) {
            MCReaderPage(route: $0)
        }
    }
}

private struct MCReaderPage: View {
    let route: MCReaderSheet
    @AppStorage("Reader.orientation") private var orientation = "device"
    @State private var barsVisible = true
    private var orientations: UIInterfaceOrientationMask {
        switch orientation {
        case "portrait": .portrait
        case "landscape": .landscape
        default: .all
        }
    }

    var body: some View {
        MCReaderView(sequence: route.sequence, startPage: route.startPage, showPanels: route.showPanels)
            .ignoresSafeArea()
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .statusBarHidden(!barsVisible)
            .interfaceOrientations(orientations)
            .onReceive(NotificationCenter.default.publisher(for: .readerShowingBars)) { _ in barsVisible = true }
            .onReceive(NotificationCenter.default.publisher(for: .readerHidingBars)) { _ in barsVisible = false }
    }
}

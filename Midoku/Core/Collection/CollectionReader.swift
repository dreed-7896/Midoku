import AidokuRunner
import SwiftUI

/// A reader session freezes the personal order. Display keys are local variant UUIDs;
/// network, download and history operations always resolve the physical source tuple.
@MainActor
final class MCReaderSequence {
    struct Route {
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
    var chapters: [AidokuRunner.Chapter] { routes.map(\.displayChapter) }

    init(entryID: UUID, slotID: UUID, store: MCCollectionStore? = nil) throws {
        let store = store ?? .shared
        guard let entry = store.library.entry(entryID) else { throw MCLibraryFailure.missing }
        self.entryID = entryID
        title = store.library.title(entry)
        var routes: [Route] = []
        var initial: String?
        for slot in entry.slots {
            guard let variant = slot.preferred, let libraryChapter = store.library.chapter(variant.chapterID),
                  let record = store.physical(libraryChapter.identity) else { throw MCLibraryFailure.missing }
            let original = record.chapter
            let display = AidokuRunner.Chapter(key: variant.id.uuidString,
                title: variant.edits.title ?? original.title,
                chapterNumber: variant.edits.number.flatMap(Float.init) ?? original.chapterNumber,
                volumeNumber: variant.edits.volume.flatMap(Float.init) ?? original.volumeNumber,
                dateUploaded: original.dateUploaded, scanlators: original.scanlators,
                url: original.url, language: original.language, thumbnail: original.thumbnail, locked: original.locked)
            routes.append(Route(identity: libraryChapter.identity, manga: record.manga, chapter: original, displayChapter: display))
            if slot.id == slotID { initial = display.key }
        }
        guard let initial else { throw MCLibraryFailure.missing }
        self.routes = routes
        initialKey = initial
    }

    func route(_ chapter: AidokuRunner.Chapter) -> Route? { routes.first { $0.displayChapter.key == chapter.key } }
    func route(key: String) -> Route? { routes.first { $0.displayChapter.key == key } }
    func adjacent(to chapter: AidokuRunner.Chapter, offset: Int) -> AidokuRunner.Chapter? {
        guard let index = routes.firstIndex(where: { $0.displayChapter.key == chapter.key }), routes.indices.contains(index + offset) else { return nil }
        return routes[index + offset].displayChapter
    }
}

struct MCReaderSheet: Identifiable {
    let id = UUID()
    let sequence: MCReaderSequence
}

extension ReaderViewController {
    func collectionCoverActions(image: UIImage, chapterKey: String, imageURL: String?) -> [UIAction] {
        let store = MCCollectionStore.shared
        let route = collectionSequence?.route(key: chapterKey)
        let identity = route?.identifier ?? ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapterKey)
        let target = collectionSequence != nil && route == nil ? nil : store.coverTarget(identifier: identity, entryID: collectionSequence?.entryID,
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
    func makeUIViewController(context: Context) -> ReaderNavigationController {
        guard let route = sequence.route(key: sequence.initialKey) else { preconditionFailure("Validated reader route missing") }
        let reader = ReaderViewController(source: route.source, manga: route.manga, chapter: route.displayChapter, collectionSequence: sequence)
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
        return ReaderNavigationController(readerViewController: reader)
    }
    func updateUIViewController(_ uiViewController: ReaderNavigationController, context: Context) {}
}

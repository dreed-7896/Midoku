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
    private let indices: [String: Int]
    var chapters: [AidokuRunner.Chapter] { routes.map(\.displayChapter) }

    init(entryID: UUID, slotID: UUID, store: MCCollectionStore? = nil) throws {
        let store = store ?? .shared
        guard let entry = store.library.entry(entryID) else { throw MCLibraryFailure.missing }
        self.entryID = entryID
        title = store.library.title(entry)
        var routes: [Route] = []
        var initial: String?
        let chapters = Dictionary(uniqueKeysWithValues: store.library.chapters.map { ($0.id, $0) })
        let storedChapters = Dictionary(uniqueKeysWithValues: store.snapshot.chapters.map { ($0.chapterID, $0.chapter) })
        let listings = Dictionary(uniqueKeysWithValues: store.library.listings.map { ($0.identity, $0.id) })
        let manga = Dictionary(uniqueKeysWithValues: store.snapshot.manga.map { ($0.listingID, $0.manga) })
        for slot in entry.slots {
            guard let variant = slot.preferred, let libraryChapter = chapters[variant.chapterID],
                  let original = storedChapters[libraryChapter.id],
                  let listingID = listings[libraryChapter.identity.listing], let physicalManga = manga[listingID]
            else { throw MCLibraryFailure.missing }
            let display = AidokuRunner.Chapter(key: variant.id.uuidString,
                title: variant.edits.title ?? original.title,
                chapterNumber: variant.edits.number.flatMap(Float.init) ?? original.chapterNumber,
                volumeNumber: variant.edits.volume.flatMap(Float.init) ?? original.volumeNumber,
                dateUploaded: original.dateUploaded, scanlators: original.scanlators,
                url: original.url, language: original.language, thumbnail: original.thumbnail, locked: original.locked)
            routes.append(Route(identity: libraryChapter.identity, manga: physicalManga, chapter: original, displayChapter: display))
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
        makeReaderController()
    }
    func makeReaderController() -> ReaderNavigationController {
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

/// Present directly through UIKit so drag progress drives the actual dismissal rather
/// than waiting for a SwiftUI fullScreenCover to close after the swipe has ended.
struct MCReaderPresentation: UIViewControllerRepresentable {
    @Binding var sheet: MCReaderSheet?

    final class Anchor: UIViewController {
        var updatePresentation: (() -> Void)?
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            updatePresentation?()
        }
    }

    final class Coordinator {
        var sheet: Binding<MCReaderSheet?>
        weak var anchor: Anchor?
        var reader: ReaderNavigationController?
        init(sheet: Binding<MCReaderSheet?>) { self.sheet = sheet }
        func update() {
            guard let anchor, anchor.viewIfLoaded?.window != nil else { return }
            guard let item = sheet.wrappedValue else {
                if let reader, !reader.isBeingDismissed { reader.dismiss(animated: true) }
                return
            }
            guard reader == nil, anchor.presentedViewController == nil else { return }
            let nav = MCReaderView(sequence: item.sequence).makeReaderController()
            reader = nav
            nav.onDismissed = { [weak self] in
                guard let self else { return }
                reader = nil
                if sheet.wrappedValue?.id == item.id { sheet.wrappedValue = nil }
            }
            anchor.present(nav, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(sheet: $sheet) }
    func makeUIViewController(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.view.backgroundColor = .clear
        context.coordinator.anchor = anchor
        anchor.updatePresentation = { [weak coordinator = context.coordinator] in coordinator?.update() }
        return anchor
    }
    func updateUIViewController(_ controller: Anchor, context: Context) {
        context.coordinator.sheet = $sheet
        DispatchQueue.main.async { context.coordinator.update() }
    }
}

import AidokuRunner
import AsyncDisplayKit
import CoreData
import Combine
import Foundation
import Testing
import UIKit
@testable import Midoku

@MainActor
@Suite("Reader resume and resource limits", .serialized)
struct ReaderReliabilityTests {
    @Test func readingAcrossChaptersKeepsProgressInMemoryUntilExplicitSave() async throws {
        let manga = AidokuRunner.Manga(sourceKey: "reader.lifecycle", key: UUID().uuidString, title: "Lifecycle")
        let chapters = [AidokuRunner.Chapter(key: "one", chapterNumber: 1),
                        AidokuRunner.Chapter(key: "two", chapterNumber: 2),
                        AidokuRunner.Chapter(key: "three", chapterNumber: 3)]
        let identifiers = chapters.map {
            ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: $0.key)
        }
        let manager = CoreDataManager.shared
        defer {
            for identifier in identifiers {
                if let history = manager.getHistory(chapterId: identifier, context: manager.context) {
                    manager.context.delete(history)
                }
            }
            try? manager.context.save()
            ReaderProgressStore.remove(chapterIDs: identifiers)
        }
        let reader = MCReaderGestureProbe(source: nil, manga: manga, chapter: chapters[0])
        let pages = (0..<3).map { Page(sourceId: manga.sourceKey, chapterId: "one", index: $0) }
        reader.setPages(pages)
        reader.setCurrentPage(3, position: 0.5)
        reader.setChapter(chapters[1])
        reader.setPages(pages)
        reader.setCurrentPage(3, position: 0.75)
        reader.setChapter(chapters[2])
        reader.setPages(pages)
        reader.setCurrentPage(2, position: 0.25)

        // Neither chapter crossings, completion, nor a pause should write history.
        try await Task.sleep(for: .milliseconds(2200))
        for identifier in identifiers {
            #expect(manager.getHistory(chapterId: identifier, context: manager.context) == nil)
        }
        #expect(ReaderProgressStore.position(for: identifiers[2])?.page == 2)
        #expect(ReaderProgressStore.position(for: identifiers[2])?.scrollPosition == 0.25)

        // Closing/backgrounding drains all chapters, not just the current one.
        await reader.updateReadPosition()
        #expect(manager.getProgress(chapterId: identifiers[0]).completed)
        #expect(manager.getProgress(chapterId: identifiers[1]).completed)
        #expect(!manager.getProgress(chapterId: identifiers[2]).completed)
        #expect(manager.getHistory(chapterId: identifiers[2], context: manager.context)?.progress == 2)
    }

    @Test func tallPanelsKeepTheProgressDrawingSurfaceSmall() {
        let node = ReaderWebtoonPageNode(source: nil, page: Page(sourceId: "test", chapterId: "tall"),
            temporaryPageStore: ReaderTemporaryPageStore(), pillarboxLayoutState: ReaderPillarboxLayoutState())
        node.pillarbox = false
        node.ratio = 40
        let size = CGSize(width: 320, height: 12_800)
        _ = node.layoutThatFits(ASSizeRange(min: size, max: size))
        #expect(node.progressNode.calculatedSize == CGSize(width: 44, height: 44))
        #expect(!node.progressNode.isNodeLoaded)
        #expect(node.getHeight(for: size) == 12_800)
    }

    @Test func imageResizesOnlyCompensateForGeometryAboveTheViewport() {
        let layout = MCMeasuredWebtoonLayout()
        let dataSource = MCWebtoonLayoutDataSource()
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 600), collectionViewLayout: layout)
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "page")
        collection.dataSource = dataSource
        collection.reloadData()
        collection.layoutIfNeeded()
        collection.contentOffset.y = 250
        layout.prepare()
        _ = layout.consumeOffsetAdjustment()

        // Two images finish together, one above and one below the reader.
        layout.pageHeights[0] = 150
        layout.pageHeights[10] = 300
        layout.invalidateLayout()
        layout.prepare()
        #expect(layout.consumeOffsetAdjustment() == 50)
        #expect(layout.consumeOffsetAdjustment() == 0)
        collection.contentOffset.y = 300
        #expect(layout.indexPath(at: CGPoint(x: 10, y: 300))?.item == 2)

        // A second layout before the first correction is applied must accumulate
        // the true delta without changing which panel is anchored.
        layout.pageHeights[0] = 175
        layout.invalidateLayout()
        layout.prepare()
        layout.pageHeights[1] = 140
        layout.invalidateLayout()
        layout.prepare()
        #expect(layout.consumeOffsetAdjustment() == 65)
        collection.contentOffset.y = 365

        layout.pageHeights[10] = 100
        layout.invalidateLayout()
        layout.prepare()
        #expect(layout.consumeOffsetAdjustment() == 0)
        #expect(collection.contentOffset.y == 365)
    }

    @Test func delayedContentSizeUpdatesKeepTheLiveScrollPosition() async {
        let layout = MCFixedContentLayout()
        let zoomView = ZoomableCollectionView(layout: layout)
        zoomView.frame = CGRect(x: 0, y: 0, width: 320, height: 600)
        zoomView.scrollNode.frame = zoomView.frame
        zoomView.collectionNode.frame = zoomView.frame
        zoomView.adjustContentSize()

        for offset: CGFloat in [500, 420, 700, 300] {
            zoomView.scheduleContentSizeUpdate()
            zoomView.scrollNode.view.contentOffset.y = offset
            // The collection can still hold the previous frame's mirrored offset.
            zoomView.collectionNode.contentOffset.y = offset - 20
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async { continuation.resume() }
            }
            #expect(zoomView.scrollNode.view.contentOffset.y == offset)
            #expect(zoomView.collectionNode.contentOffset.y == offset)
        }
    }

    @Test func staticPanelsDoNotAllocateGIFAnimationState() {
        let view = ReaderImageView(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
        view.image = UIGraphicsImageRenderer(size: view.bounds.size).image { context in
            UIColor.white.setFill()
            context.fill(view.bounds)
        }
        view.layer.setNeedsDisplay()
        view.layer.displayIfNeeded()
        #expect(view.animator == nil)

        let gif = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")!
        view.displayGIF(gif)
        #expect(view.animator != nil)
        view.clearGIF()
        #expect(view.animator == nil)
    }

    @Test func webtoonPagesKeepTheirCollectionPositionWhenAnImageLoads() {
        let node = ReaderWebtoonPageNode(
            source: nil,
            page: Page(sourceId: "test", chapterId: "one"),
            temporaryPageStore: ReaderTemporaryPageStore(),
            pillarboxLayoutState: ReaderPillarboxLayoutState()
        )
        node.pillarbox = false
        let size = CGSize(width: 320, height: 640)
        _ = node.layoutThatFits(ASSizeRange(min: size, max: size))
        node.frame = CGRect(origin: CGPoint(x: 24, y: 900), size: size)
        node.image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        node.displayPage()
        #expect(node.frame.origin == CGPoint(x: 24, y: 900))
        node.displayPage()
        #expect(node.frame.origin == CGPoint(x: 24, y: 900))

        // Scrolling just outside the display range must not discard a preloaded page.
        node.didExitDisplayState()
        #expect(node.image != nil)
        node.didExitPreloadState()
        #expect(node.image == nil)
        #expect(node.imageNode.image == nil)
        #expect(node.getHeight(for: size) == 640) // Unloading preserves page geometry.
    }

    @Test func readerPanelPlacesProgressAboveOrderedActions() {
        for width: CGFloat in [288, 358, 600] {
            let panel = ReaderControlsView()
            let height = panel.systemLayoutSizeFitting(
                CGSize(width: width, height: 0),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
            panel.frame = CGRect(x: 0, y: 0, width: width, height: height)
            panel.layoutIfNeeded()
            let controls: [UIView] = [panel.closeButton, panel.webButton, panel.chaptersButton,
                                      panel.panelsButton, panel.autoScrollButton, panel.settingsButton]
            let frames = controls.map { $0.convert($0.bounds, to: panel) }
            let progressFrame = panel.toolbar.convert(panel.toolbar.bounds, to: panel)
            #expect(height <= 120)
            #expect(frames.allSatisfy { $0.minY == frames.first?.minY })
            for frame in frames {
                #expect(frame.minY >= progressFrame.maxY)
                #expect(frame.minX >= 0 && frame.maxX <= width)
            }
            for index in 1..<frames.count {
                #expect(frames[index - 1].maxX <= frames[index].minX)
            }
        }
    }

    @Test func scrollingLongChaptersReusesGeometryAndFindsOnlyVisiblePages() {
        let layout = MCMeasuredWebtoonLayout()
        let dataSource = MCWebtoonLayoutDataSource()
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 600), collectionViewLayout: layout)
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "page")
        collection.dataSource = dataSource
        collection.reloadData()
        collection.layoutIfNeeded()
        layout.prepare()
        let initialMeasurements = layout.measurements
        #expect(initialMeasurements >= 1_000)

        for page in stride(from: 10, through: 900, by: 10) {
            let viewport = CGRect(x: 0, y: CGFloat(page * 100), width: 320, height: 600)
            #expect(!layout.shouldInvalidateLayout(forBoundsChange: viewport))
            layout.prepare()
            let rect = viewport.insetBy(dx: 0, dy: 1)
            let attributes = layout.layoutAttributesForElements(in: rect) ?? []
            #expect(attributes.map(\.indexPath.item) == Array(page..<(page + 6)))
            #expect(layout.indexPath(at: CGPoint(x: 10, y: rect.minY + 50))?.item == page)
        }
        #expect(layout.measurements == initialMeasurements)

        // Loaded image dimensions and zoom must still invalidate cached geometry.
        layout.pageHeight = 200
        layout.invalidateLayout()
        layout.prepare()
        #expect(layout.collectionViewContentSize.height == 200_000)
        #expect(layout.indexPath(at: CGPoint(x: 10, y: 250))?.item == 1)
        layout.setScale(2)
        layout.prepare()
        #expect(layout.collectionViewContentSize.height == 400_000)
        #expect(layout.indexPath(at: CGPoint(x: 10, y: 450))?.item == 1)
        #expect(layout.shouldInvalidateLayout(forBoundsChange: CGRect(x: 0, y: 0, width: 600, height: 320)))
    }

    @Test func backGestureDoesNotMakeVerticalReaderPansWait() {
        let manga = AidokuRunner.Manga(sourceKey: "gesture", key: "book", title: "Book")
        let reader = MCReaderGestureProbe(source: nil, manga: manga, chapter: .init(key: "one"))
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.loadViewIfNeeded()
        navigation.pushViewController(reader, animated: false)
        reader.loadViewIfNeeded()
        let scroll = UIScrollView()
        reader.view.addSubview(scroll)
        let delegate = ReaderPopGestureDelegate(reader: reader)
        delegate.install(on: navigation)
        defer { delegate.restore() }
        let back = navigation.interactivePopGestureRecognizer!
        let pan = scroll.panGestureRecognizer

        for mode: ReadingMode in [.webtoon, .continuous, .vertical] {
            reader.readingMode = mode
            #expect(delegate.gestureRecognizer(back, shouldRecognizeSimultaneouslyWith: pan))
        }
        for mode: ReadingMode in [.rtl, .ltr] {
            reader.readingMode = mode
            #expect(!delegate.gestureRecognizer(back, shouldRecognizeSimultaneouslyWith: pan))
        }
        // Switching back from horizontal paging must not leave a permanent failure dependency.
        reader.readingMode = .webtoon
        #expect(delegate.gestureRecognizer(back, shouldRecognizeSimultaneouslyWith: pan))
        let unrelatedScroll = UIScrollView()
        #expect(!delegate.gestureRecognizer(back, shouldRecognizeSimultaneouslyWith: unrelatedScroll.panGestureRecognizer))
    }

    @Test func readerUsesAndRestoresNativePopRecognizer() {
        let manga = AidokuRunner.Manga(sourceKey: "gesture", key: "book", title: "Book")
        let reader = MCReaderGestureProbe(source: nil, manga: manga, chapter: .init(key: "one"))
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.loadViewIfNeeded()
        navigation.pushViewController(reader, animated: false)
        reader.loadViewIfNeeded()
        let recognizer = navigation.interactivePopGestureRecognizer!
        let originalDelegate = recognizer.delegate
        let count = navigation.view.gestureRecognizers?.count
        let delegate = ReaderPopGestureDelegate(reader: reader)
        delegate.install(on: navigation)
        #expect(navigation.interactivePopGestureRecognizer === recognizer)
        #expect(navigation.view.gestureRecognizers?.count == count)
        #expect(recognizer.delegate === delegate)
        navigation.setViewControllers([reader], animated: false)
        #expect(!delegate.gestureRecognizerShouldBegin(recognizer))
        delegate.restore()
        #expect(recognizer.delegate === originalDelegate)
    }

    @Test func repeatedSwipeToHideDoesNotRetriggerReaderTransitions() {
        let manga = AidokuRunner.Manga(sourceKey: "controls", key: "book", title: "Book")
        let reader = ReaderViewController(source: nil, manga: manga, chapter: .init(key: "one"))
        reader.loadViewIfNeeded()
        var hidingEvents = 0
        var showingEvents = 0
        let hiding = NotificationCenter.default.publisher(for: .readerHidingBars).sink { _ in hidingEvents += 1 }
        let showing = NotificationCenter.default.publisher(for: .readerShowingBars).sink { _ in showingEvents += 1 }
        defer { hiding.cancel(); showing.cancel() }

        reader.setReaderControlsVisible(false, animated: false)
        for _ in 0..<20 { reader.setReaderControlsVisible(false, animated: false) }
        #expect(hidingEvents == 1)
        #expect(!reader.readerControlsVisible)
        reader.setReaderControlsVisible(true, animated: false)
        for _ in 0..<20 { reader.setReaderControlsVisible(true, animated: false) }
        #expect(showingEvents == 1)
        #expect(reader.readerControlsVisible)
    }

    @Test func completedChaptersRestartWhileUnfinishedChaptersResume() throws {
        let manga = AidokuRunner.Manga(sourceKey: "mc.restart", key: UUID().uuidString, title: "Restart")
        let chapter = AidokuRunner.Chapter(key: "chapter", chapterNumber: 1)
        let identifier = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key)
        let manager = CoreDataManager.shared
        defer {
            if let history = manager.getHistory(chapterId: identifier, context: manager.context) {
                manager.context.delete(history)
                try? manager.context.save()
            }
        }
        manager.setProgress(18, chapterId: identifier, totalPages: 20, scrollPosition: 0.9, completed: false, context: manager.context)
        let unfinished = ReaderViewController(source: nil, manga: manga, chapter: chapter)
        let probe = MCReaderStartProbe()
        unfinished.reader = probe
        unfinished.loadCurrentChapter()
        #expect(probe.startPage == 18)
        manager.setProgress(20, chapterId: identifier, totalPages: 20, scrollPosition: 1, completed: true, context: manager.context)
        let finished = ReaderViewController(source: nil, manga: manga, chapter: chapter)
        finished.reader = probe
        finished.loadCurrentChapter()
        #expect(probe.startPage == 0) // Fresh start also bypasses saved text/webtoon offsets.
        #expect(manager.getProgress(chapterId: identifier).completed)
    }

    @Test func pageViewsAreCreatedOnlyForPagesBeingLoaded() async throws {
        let store = ReaderTemporaryPageStore()
        let page = ReaderPageViewController(type: .page, delegate: nil, temporaryPageStore: store)
        #expect(page.pageView == nil)
        page.loadViewIfNeeded()
        #expect(page.pageView != nil)
        page.clearPage()
        #expect(page.page == nil)
        await store.removeAll()
    }

    @Test func diskBudgetEvictsOldCacheFilesWithoutTouchingDownloads() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let old = cache.appendingPathComponent("old")
        let recent = cache.appendingPathComponent("recent")
        let download = root.appendingPathComponent("download")
        for file in [old, recent, download] { try Data(repeating: 0, count: 20).write(to: file) }
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: old.path)
        ArtworkDiskBudget.trim(directory: cache, limit: 25)
        #expect(!old.exists)
        #expect(recent.exists)
        #expect(download.exists)
    }

    @Test func refreshTimesOutEvenWhenASourceIgnoresCancellation() async throws {
        let runner = MCSlowRefreshRunner()
        let source = AidokuRunner.Source(url: nil, key: "mc.timeout", name: "Timeout", version: 1,
            languages: ["en"], contentRating: .safe, runner: runner)
        let manga = AidokuRunner.Manga(sourceKey: source.key, key: "one", title: "One")
        do {
            _ = try await LibraryRefreshRequest.fetch(source: source, manga: manga, needsDetails: true, timeoutSeconds: 0.02)
            Issue.record("A stalled source should time out")
        } catch {
            #expect((error as? URLError)?.code == .timedOut)
        }
        // Complete the ignored request late; it must not resume the timeout continuation twice.
        runner.finish(manga)
        await Task.yield()
    }

    @Test func failedRefreshResetsStateAndPreservesChaptersOnRetry() async throws {
        await SourceManager.shared.waitForSourcesLoad()
        let sources = SourceStore.shared.sourcesByKey
        let disabled = SourceStore.shared.disabledSourceKeys
        defer { SourceStore.shared.update(sourcesByKey: sources, disabledSourceKeys: disabled) }
        let key = "mc.refresh.failure.\(UUID().uuidString)"
        var testSources = sources
        testSources[key] = AidokuRunner.Source(url: nil, key: key, name: "Failure", version: 1,
            languages: ["en"], contentRating: .safe, runner: MCFailedRefreshRunner())
        SourceStore.shared.update(sourcesByKey: testSources, disabledSourceKeys: disabled)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MCCollectionStore(fileURL: root.appendingPathComponent("collection.json"))
        let id = try store.add(.init(sourceKey: key, key: "one", title: "One"), chapters: [.init(key: "chapter")])
        let slots = try #require(store.library.entry(id)?.slots)
        for _ in 0..<2 {
            await store.refresh()
            #expect(!store.isRefreshing)
            #expect(store.error?.contains("unexpected data") == true)
            #expect(store.library.entry(id)?.slots.map(\.id) == slots.map(\.id))
            #expect(store.chapterCount(entryID: id) == 1)
        }
    }

    @Test func globalRefreshSkipsStaticGalleriesButExplicitRefreshReportsFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MCCollectionStore(fileURL: root.appendingPathComponent("collection.json"))
        let key = "mc.static.unavailable.\(UUID().uuidString)"
        let id = try store.add(.init(sourceKey: key, key: "one", title: "One", updateStrategy: .never),
            chapters: [.init(key: "chapter")])
        await store.refresh()
        #expect(store.error == nil)
        #expect(!store.isRefreshing)
        await store.refresh(entryID: id)
        #expect(store.error?.contains("source unavailable") == true)
        #expect(!store.isRefreshing)
        #expect(store.chapterCount(entryID: id) == 1)
    }

    @Test func asyncPersistencePreservesAnEditMadeWhileEncoding() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MCCollectionStore(fileURL: root.appendingPathComponent("collection.json"))
        let id = try store.add(AidokuRunner.Manga(sourceKey: "async", key: "one", title: "One"), chapters: [])
        let task = Task {
            try await store.changeAsync { state in try state.library.editEntry(id) { $0.descriptionOverride = "Refreshed" } }
        }
        await Task.yield()
        try store.change { state in try state.library.editEntry(id) { $0.titleOverride = "My title" } }
        try await task.value
        #expect(store.library.entry(id)?.titleOverride == "My title")
        #expect(store.library.entry(id)?.descriptionOverride == "Refreshed")
        #expect(MCCollectionStore(fileURL: root.appendingPathComponent("collection.json")).library.entry(id)?.titleOverride == "My title")
    }
}

private struct MCFailedRefreshRunner: AidokuRunner.Runner {
    let features = AidokuRunner.SourceFeatures()
    func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga {
        throw AidokuRunner.SourceError.jsonParseError
    }
    func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult {
        .init(entries: [], hasNextPage: false)
    }
    func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] { [] }
}

private final class MCSlowRefreshRunner: AidokuRunner.Runner, @unchecked Sendable {
    let features = AidokuRunner.SourceFeatures()
    private let lock = NSLock()
    private var pending: CheckedContinuation<AidokuRunner.Manga, Never>?
    func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga {
        await withCheckedContinuation { continuation in
            lock.lock(); pending = continuation; lock.unlock()
        }
    }
    func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult {
        .init(entries: [], hasNextPage: false)
    }
    func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] { [] }
    func finish(_ manga: AidokuRunner.Manga) {
        lock.lock(); let continuation = pending; pending = nil; lock.unlock()
        continuation?.resume(returning: manga)
    }
}

@MainActor
private final class MCReaderStartProbe: UIViewController, ReaderReaderDelegate {
    var readingMode = ReadingMode.rtl
    weak var delegate: ReaderHoldingDelegate?
    var startPage: Int?
    func moveLeft() {}
    func moveRight() {}
    func sliderMoved(value: CGFloat) {}
    func sliderStopped(value: CGFloat) {}
    func setChapter(_ chapter: AidokuRunner.Chapter, startPage: Int) { self.startPage = startPage }
}

@MainActor
private final class MCMeasuredWebtoonLayout: VerticalContentOffsetPreservingLayout {
    var measurements = 0
    var pageHeight: CGFloat = 100
    var pageHeights: [Int: CGFloat] = [:]
    override func getHeight(for indexPath: IndexPath) -> CGFloat {
        measurements += 1
        return pageHeights[indexPath.item] ?? pageHeight
    }
}

@MainActor
private final class MCFixedContentLayout: UICollectionViewLayout {
    override var collectionViewContentSize: CGSize { CGSize(width: 320, height: 10_000) }
}

@MainActor
private final class MCWebtoonLayoutDataSource: NSObject, UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 1_000 }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(withReuseIdentifier: "page", for: indexPath)
    }
}

@MainActor
private final class MCReaderGestureProbe: ReaderViewController {
    override func configure() { view.addSubview(controlsView) }
    override func constrain() {}
    override func observe() {}
}

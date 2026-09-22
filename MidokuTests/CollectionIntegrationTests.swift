import AidokuRunner
import Foundation
import Testing
import UIKit
@testable import Midoku

@MainActor
@Suite("Collection persistence and physical reader routing", .serialized)
struct CollectionIntegrationTests {
    @Test func pageLoadingAndPreloadingUsePhysicalChapterIdentity() async throws {
        await SourceManager.shared.waitForSourcesLoad()
        let sources = SourceStore.shared.sourcesByKey
        let disabled = SourceStore.shared.disabledSourceKeys
        defer { SourceStore.shared.update(sourcesByKey: sources, disabledSourceKeys: disabled) }
        var testSources = sources
        for key in ["mc.routing.a", "mc.routing.b"] {
            testSources[key] = AidokuRunner.Source(url: nil, key: key, name: key, version: 1,
                languages: ["en"], contentRating: .safe, runner: MCPageRoutingRunner())
        }
        SourceStore.shared.update(sourcesByKey: testSources, disabledSourceKeys: disabled)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MCCollectionStore(fileURL: root.appendingPathComponent("collection.json"))
        let a = AidokuRunner.Manga(sourceKey: "mc.routing.a", key: "book", title: "A")
        let b = AidokuRunner.Manga(sourceKey: "mc.routing.b", key: "book", title: "B")
        let entry = try store.add(a, chapters: [.init(key: "same", chapterNumber: 20), .init(key: "last", chapterNumber: 22)])
        try store.addChapter(.init(key: "same", chapterNumber: 21), from: b, to: entry, title: "Chapter 21")
        let sequence = try MCReaderSequence(entryID: entry, slotID: try #require(store.library.entry(entry)?.slots.first).id, store: store)
        let model = ReaderPagedViewModel(source: testSources[a.sourceKey], manga: a)
        model.collectionSequence = sequence
        await model.loadPages(chapter: sequence.chapters[0])
        #expect(model.pages.first?.text == "mc.routing.a/book/same")
        await model.preload(chapter: sequence.chapters[1])
        #expect(model.preloadedPages.first?.sourceId == "mc.routing.b")
        await model.loadPages(chapter: sequence.chapters[1])
        #expect(model.pages.first?.text == "mc.routing.b/book/same")
        #expect(model.source?.key == "mc.routing.b")
        await model.loadPages(chapter: sequence.chapters[2])
        #expect(model.pages.first?.text == "mc.routing.a/book/last")
        await model.loadPages(chapter: sequence.chapters[1])
        #expect(model.pages.first?.text == "mc.routing.b/book/same")
        #expect(model.pages.first?.chapterId == sequence.chapters[1].key)
    }

    @Test func readerRoutesIdenticalChapterKeysToTheirOwnSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("collection.json")
        let store = MCCollectionStore(fileURL: file)
        let a = AidokuRunner.Manga(sourceKey: "source-a", key: "same-manga", title: "Original A")
        let b = AidokuRunner.Manga(sourceKey: "source-b", key: "same-manga", title: "Original B")
        let entry = try store.add(a, chapters: [.init(key: "same-chapter", chapterNumber: 20), .init(key: "22", chapterNumber: 22)])
        try store.addChapter(.init(key: "same-chapter", chapterNumber: 21), from: b, to: entry, title: "Chapter 21")
        let reloaded = MCCollectionStore(fileURL: file)
        let personal = try #require(reloaded.library.entry(entry))
        let sequence = try MCReaderSequence(entryID: entry, slotID: try #require(personal.slots.first).id, store: reloaded)
        #expect(sequence.routes.map { $0.identifier.sourceKey } == ["source-a", "source-b", "source-a"])
        #expect(Set(sequence.chapters.map(\.key)).count == 3)
        #expect(sequence.routes[0].chapter.key == sequence.routes[1].chapter.key)
        let next = try #require(sequence.adjacent(to: sequence.chapters[0], offset: 1))
        #expect(sequence.route(next)?.identifier.sourceKey == "source-b")
        #expect(sequence.route(next)?.identifier.chapterKey == "same-chapter")
        try reloaded.snapshot.validate()
    }

    @Test func failedPersistenceDoesNotPublishChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("collection.json")
        let store = MCCollectionStore(fileURL: file)
        try store.change { _ = try $0.library.createManual(title: "Keep me") }
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try store.change { _ = try $0.library.createManual(title: "Do not publish") } }
        #expect(store.library.entries.count == 1)
    }

    @Test func invalidRestoreDoesNotReplaceCollection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MCCollectionStore(fileURL: root.appendingPathComponent("collection.json"))
        try store.change { _ = try $0.library.createManual(title: "Keep me") }
        let before = try store.backupData()
        var corrupt = store.snapshot; corrupt.version = 999
        #expect(throws: (any Error).self) { try store.restore(JSONEncoder().encode(corrupt)) }
        #expect(store.library.entries.count == 1)
        try store.restore(before)
        #expect(store.library.title(try #require(store.library.entries.first)) == "Keep me")
    }
    @Test func addDetailsAndReaderCoversSurviveRestartWithoutChangingSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("collection.json")
        let store = MCCollectionStore(fileURL: file)
        let a = AidokuRunner.Manga(sourceKey: "cover-a", key: "same", title: "Original A", description: "Source summary")
        let b = AidokuRunner.Manga(sourceKey: "cover-b", key: "same", title: "Original B")
        let entry = try store.add(a, chapters: [.init(key: "shared", chapterNumber: 1)], title: "Edited on add", description: "My summary",
                                  author: "My author", artist: "My artist")
        let other = try store.add(b, chapters: [.init(key: "shared", chapterNumber: 2)])
        try store.addChapter(.init(key: "shared", chapterNumber: 2), from: b, to: entry, title: "Chapter 2")
        let personal = try #require(store.library.entry(entry))
        let slot = try #require(personal.slots.last)
        let variant = try #require(slot.preferred)
        let target = try #require(store.coverTarget(identifier: .init(sourceKey: b.sourceKey, mangaKey: b.key, chapterKey: "shared"), entryID: entry, variantID: variant.id))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }
        let data = try #require(image.pngData())
        try store.setCover(data: data, target: target, forEntry: false)
        try store.setCover(data: data, target: target, forEntry: true)
        let reloaded = MCCollectionStore(fileURL: file)
        let edited = try #require(reloaded.library.entry(entry))
        #expect(reloaded.library.title(edited) == "Edited on add")
        #expect(reloaded.library.description(edited) == "My summary")
        #expect(edited.authorOverride == "My author")
        #expect(edited.artistOverride == "My artist")
        #expect(edited.coverID != nil)
        #expect(edited.slots.last?.preferred?.edits.coverID != nil)
        #expect(edited.slots.first?.preferred?.edits.coverID == nil)
        #expect(reloaded.library.entry(other)?.coverID == nil)
        #expect(reloaded.library.entry(other)?.slots.first?.preferred?.edits.coverID == nil)
        #expect(reloaded.snapshot.manga.first { $0.listingID == edited.primaryListingID }?.manga.title == "Original A")
        try reloaded.change { try $0.library.resetChapterDetails(entryID: entry, slotID: slot.id) }
        #expect(reloaded.library.entry(entry)?.coverID != nil)
        try reloaded.change { try $0.library.removeSlots(entryID: entry, slotIDs: [slot.id]) }
        let count = reloaded.library.covers.count
        #expect(throws: (any Error).self) { try reloaded.setCover(data: data, target: target, forEntry: false) }
        #expect(reloaded.library.covers.count == count)
    }

    @Test func sliderTapsRespectDirectionBoundsAndCustomRange() {
        let slider = ReaderSliderView(frame: CGRect(x: 0, y: 0, width: 210, height: 32))
        slider.layoutIfNeeded()
        #expect(slider.value(at: CGPoint(x: 5, y: 16)) == 0)
        #expect(slider.value(at: CGPoint(x: 205, y: 16)) == 1)
        #expect(abs(slider.value(at: CGPoint(x: 55, y: 16)) - 0.25) < 0.001)
        slider.direction = .backward
        #expect(slider.value(at: CGPoint(x: 5, y: 16)) == 1)
        #expect(slider.value(at: CGPoint(x: 205, y: 16)) == 0)
        #expect(abs(slider.value(at: CGPoint(x: 55, y: 16)) - 0.75) < 0.001)
        slider.minimumValue = 2; slider.maximumValue = 6
        #expect(slider.value(at: CGPoint(x: 105, y: 16)) == 4)
        #expect(slider.value(at: CGPoint(x: -100, y: 16)) == 6)
        #expect(slider.value(at: CGPoint(x: 999, y: 16)) == 2)
        let toolbar = ReaderToolbarView()
        toolbar.frame = CGRect(x: 0, y: 0, width: 340, height: 44)
        toolbar.layoutIfNeeded()
        #expect(toolbar.hitTest(toolbar.sliderView.center, with: nil) === toolbar.sliderView)
        #expect(toolbar.previousChapterButton.frame.maxX <= toolbar.sliderView.frame.minX)
        #expect(toolbar.nextChapterButton.frame.minX >= toolbar.sliderView.frame.maxX)
    }

    @Test func failedDirectAddSaveKeepsEntryUnchanged() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("collection.json")
        let store = MCCollectionStore(fileURL: file)
        let manga = AidokuRunner.Manga(sourceKey: "paste", key: "book", title: "Title")
        let entry = try store.add(manga, chapters: [.init(key: "one", chapterNumber: 1)])
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) {
            try store.addChapter(.init(key: "two", chapterNumber: 2), from: manga, to: entry, title: "Chapter 2")
        }
        #expect(store.library.entry(entry)?.slots.count == 1)
    }

    @Test func directAddsContinueTargetChapterNames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MCCollectionStore(fileURL: root.appendingPathComponent("collection.json"))
        let targetManga = AidokuRunner.Manga(sourceKey: "target", key: "book", title: "Target")
        let sourceManga = AidokuRunner.Manga(sourceKey: "source", key: "book", title: "Source")
        let target = try store.add(targetManga, chapters: [.init(key: "four", chapterNumber: 4)])
        let suggested = store.suggestedChapterName(for: target)
        #expect(suggested == "Chapter 5")
        try store.addChapter(.init(key: "forty", chapterNumber: 40), from: sourceManga, to: target, title: suggested)
        let added = try #require(store.library.entry(target)?.slots.last?.preferred)
        #expect(store.library.chapterDisplayTitle(added) == "Chapter 5")
        #expect(added.edits.number == "5")
    }

    @Test func readerActionsStayBelowProgressAtPhoneWidths() {
        for width in [288.0, 370.0, 600.0] {
            let controls = ReaderControlsView()
            controls.titleLabel.text = "Chapter 21"
            controls.toolbar.totalPages = 25
            controls.toolbar.currentPage = 1
            controls.frame = CGRect(x: 0, y: 0, width: width, height: 130)
            controls.layoutIfNeeded()
            let slider = controls.toolbar.sliderView
            let sliderFrame = slider.convert(slider.bounds, to: controls)
            for button in [controls.closeButton, controls.chaptersButton, controls.settingsButton, controls.webButton] {
                let frame = button.convert(button.bounds, to: controls)
                #expect(frame.minY > sliderFrame.maxY)
                #expect(frame.height >= 44 && frame.width >= 44)
                #expect(frame.maxX <= controls.bounds.maxX)
            }
            #expect(controls.toolbar.hitTest(slider.center, with: nil) === slider)
        }
    }

    @Test func readerBackSwipeRequiresIntentionalRightwardMovement() {
        #expect(ReaderNavigationController.shouldCloseReader(translation: .init(x: 100, y: 5), velocity: .zero, width: 390))
        #expect(ReaderNavigationController.shouldCloseReader(translation: .init(x: 20, y: 0), velocity: .init(x: 700, y: 0), width: 390))
        #expect(!ReaderNavigationController.shouldCloseReader(translation: .init(x: 5, y: 0), velocity: .init(x: 700, y: 0), width: 390))
        #expect(!ReaderNavigationController.shouldCloseReader(translation: .init(x: -100, y: 0), velocity: .init(x: -700, y: 0), width: 390))
        #expect(!ReaderNavigationController.shouldCloseReader(translation: .init(x: 50, y: 0), velocity: .zero, width: 390))
    }

}

private struct MCPageRoutingRunner: AidokuRunner.Runner {
    let features = AidokuRunner.SourceFeatures()
    func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult {
        .init(entries: [], hasNextPage: false)
    }
    func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga { manga }
    func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] {
        [.init(content: .text("\(manga.sourceKey)/\(manga.key)/\(chapter.key)"))]
    }
}

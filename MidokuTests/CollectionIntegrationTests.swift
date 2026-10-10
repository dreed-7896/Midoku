import AidokuRunner
import Foundation
import Observation
import SwiftUI
import Testing
import UIKit
@testable import Midoku

@MainActor
@Suite("Collection persistence and physical reader routing", .serialized)
struct CollectionIntegrationTests {
    @Test func mergedChaptersPersistWithExactRoutingAndReassignedBookmarks() throws {
        let defaultsKey = "Reader.panelBookmarks.v1"
        let previous = UserDefaults.standard.data(forKey: defaultsKey)
        defer { UserDefaults.standard.set(previous, forKey: defaultsKey) }
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("collection.json")
        let store = MCCollectionStore(fileURL: file)
        let a = try store.add(.init(sourceKey: "merge.a", key: "book", title: "A"), chapters: [.init(key: "one", chapterNumber: 10)])
        let b = try store.add(.init(sourceKey: "merge.b", key: "book", title: "B"), chapters: [.init(key: "one", chapterNumber: 20)])
        let slot = try #require(store.library.entry(a)?.slots.first)
        try MCPanelBookmarks.toggleChapter(entryID: a, slotID: slot.id, store: store)
        MCPanelBookmarks.add(.init(id: UUID(), titleKey: a.uuidString, slotID: slot.id,
            sourceKey: "merge.a", mangaKey: "book", chapterKey: "one", chapterTitle: "Chapter 10",
            chapterNumber: 10, page: 3, preview: nil))
        let merged = try store.groupEntries([b, a], details: .init(title: "Merged"), mode: .mergeChapters, naming: .numberInOrder)
        #expect(store.chapterCount(entryID: merged) == 2 && store.library.entries.count == 1)
        #expect(MCPanelBookmarks.all.count == 2)
        #expect(MCPanelBookmarks.all.allSatisfy { $0.titleKey == merged.uuidString && $0.slotID == slot.id && $0.chapterTitle == "Chapter 2" })
        let reopened = MCCollectionStore(fileURL: file)
        for bookmark in MCPanelBookmarks.all {
            let reader = try MCPanelBookmarks.reader(for: bookmark, store: reopened)
            let route = try #require(reader.sequence.route(key: reader.sequence.initialKey))
            #expect(route.entryID == merged && route.slotID == slot.id)
            #expect(route.identifier.sourceKey == "merge.a" && route.identifier.chapterKey == "one")
            #expect(reader.startPage == (bookmark.isChapter ? 1 : 3))
        }
    }

    @Test func failedMergeSaveLeavesOriginalEntriesAndBookmarksIntact() throws {
        let defaultsKey = "Reader.panelBookmarks.v1"
        let previous = UserDefaults.standard.data(forKey: defaultsKey)
        defer { UserDefaults.standard.set(previous, forKey: defaultsKey) }
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("collection.json")
        let store = MCCollectionStore(fileURL: file)
        let a = try store.add(.init(sourceKey: "merge.a", key: "book", title: "A"), chapters: [.init(key: "one")])
        let b = try store.add(.init(sourceKey: "merge.b", key: "book", title: "B"), chapters: [.init(key: "one")])
        try MCPanelBookmarks.toggleChapter(entryID: a, slotID: try #require(store.library.entry(a)?.slots.first?.id), store: store)
        let bookmarks = UserDefaults.standard.data(forKey: defaultsKey)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) {
            try store.groupEntries([a, b], details: .init(title: "Merged"), mode: .mergeChapters, naming: .numberInOrder)
        }
        #expect(store.library.entries.map(\.id) == [a, b])
        #expect(UserDefaults.standard.data(forKey: defaultsKey) == bookmarks)
    }

    @Test func chapterBookmarksKeepPanelsAndExactPhysicalRouting() throws {
        let defaultsKey = "Reader.panelBookmarks.v1"
        let previous = UserDefaults.standard.data(forKey: defaultsKey)
        defer { UserDefaults.standard.set(previous, forKey: defaultsKey) }
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MCCollectionStore(fileURL: root.appendingPathComponent("collection.json"))
        let manga = AidokuRunner.Manga(sourceKey: "bookmarks.a", key: "book", title: "A")
        let entryID = try store.add(manga, chapters: [.init(key: "one", chapterNumber: 1)])
        let otherID = try store.add(.init(sourceKey: "bookmarks.b", key: "book", title: "B"),
                                    chapters: [.init(key: "one", chapterNumber: 1)])
        let slot = try #require(store.library.entry(entryID)?.slots.first)
        let otherSlot = try #require(store.library.entry(otherID)?.slots.first)
        let panel = MCPanelBookmark(id: UUID(), titleKey: entryID.uuidString, slotID: slot.id,
            sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: "one",
            chapterTitle: "Chapter 1", chapterNumber: 1, page: 1, preview: nil)
        MCPanelBookmarks.add(panel)
        try MCPanelBookmarks.toggleChapter(entryID: entryID, slotID: slot.id, store: store)
        #expect(MCPanelBookmarks.all.count == 2)
        #expect(MCPanelBookmarks.bookmarkedSlotIDs == [slot.id])
        #expect(!MCPanelBookmarks.bookmarkedSlotIDs.contains(otherSlot.id))
        let savedBookmark = MCPanelBookmarks.all.first { $0.isChapter }
        let saved = try #require(savedBookmark)
        let reader = try MCPanelBookmarks.reader(for: saved, store: store)
        #expect(reader.startPage == 1)
        let route = try #require(reader.sequence.route(key: reader.sequence.initialKey))
        #expect(route.slotID == slot.id)
        #expect(route.identifier.sourceKey == manga.sourceKey)
        #expect(route.identifier.chapterKey == "one")
        try store.change { state in
            _ = try state.remember(manga, chapters: [.init(key: "one", title: "Refreshed", chapterNumber: 1)],
                                   sourceName: "A", complete: true)
        }
        #expect(MCPanelBookmarks.all.contains { $0.id == saved.id })
        try MCPanelBookmarks.toggleChapter(entryID: entryID, slotID: slot.id, store: store)
        #expect(MCPanelBookmarks.all.map(\.id) == [panel.id])
        #expect(MCPanelBookmarks.bookmarkedSlotIDs.isEmpty)
    }

    @Test func releaseDatesFollowPhysicalChaptersRefreshAndRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("collection.json")
        let store = MCCollectionStore(fileURL: file)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let manga = AidokuRunner.Manga(sourceKey: "dates", key: "book", title: "Dates")
        let id = try store.add(manga, chapters: [.init(key: "one", dateUploaded: date), .init(key: "unknown")])
        let known = try #require(store.library.chapters.first { $0.record.id == "one" })
        let unknown = try #require(store.library.chapters.first { $0.record.id == "unknown" })
        #expect(store.chapterReleaseDate(known.id) == date)
        #expect(store.chapterReleaseDate(unknown.id) == nil)
        #expect(MCCollectionStore(fileURL: file).chapterReleaseDate(known.id) == date)
        let updated = date.addingTimeInterval(86_400)
        try await store.changeAsync { state in
            _ = try state.remember(manga, chapters: [.init(key: "one", dateUploaded: updated)],
                                   sourceName: "Dates", complete: false)
        }
        #expect(store.chapterReleaseDate(known.id) == updated)
        #expect(store.library.entry(id) != nil)
    }

    @Test func groupedTitlesPersistAndNestedTitlesRemainIndependentRandomPicks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("collection.json")
        let store = MCCollectionStore(fileURL: file)
        let x = try store.add(.init(sourceKey: "group.x", key: "book", title: "X"), chapters: [.init(key: "one", chapterNumber: 1)])
        let y = try store.add(.init(sourceKey: "group.y", key: "book", title: "Y"), chapters: [.init(key: "two", chapterNumber: 2)])
        let z = try store.add(.init(sourceKey: "group.z", key: "book", title: "Z"), chapters: [.init(key: "three", chapterNumber: 3)])
        try store.change { try $0.library.moveEntry(z, into: y) }
        let zSlot = try #require(store.library.entry(z)?.slots.first)
        try store.change { _ = try $0.library.setRead(entryID: z, slotIDs: [zSlot.id], read: true) }
        var group = UUID()
        try store.change { group = try $0.library.groupEntries([x, y], details: .init(title: "Grouped", author: "Author")) }
        #expect(store.chapterCount(entryID: group) == 3 && store.unreadCount(entryID: group) == 2)
        #expect(store.addToReading([group]))
        #expect(Set(store.library.entriesIncludingDescendants(of: Set(store.library.readingIDs)).map(\.id)) == [group, x, y, z])
        #expect(store.addRandomToReading(count: 100)) // Exhausting the pool makes this deterministic.
        #expect(Set(store.library.readingIDs) == [group, x, y, z] && store.library.readingIDs.count == 4)
        #expect(store.addRandomToReading(count: 100))
        #expect(store.library.readingIDs.count == 4)
        let reopened = MCCollectionStore(fileURL: file)
        #expect(reopened.library.rootEntries.map(\.id) == [group])
        #expect(reopened.library.entry(z)?.parentEntryID == y)
        #expect(reopened.library.entry(group)?.authorOverride == "Author")
        #expect(Set(reopened.library.readingIDs) == [group, x, y, z])
        let sequence = try MCReaderSequence(entryID: z, slotID: zSlot.id, store: reopened)
        #expect(sequence.routes.map(\.entryID) == [x, y, z])
        #expect(sequence.routes.last?.identifier.sourceKey == "group.z")
        #expect(sequence.initialKey == sequence.chapters.last?.key)
        #expect(sequence.routes.last?.initiallyRead == true)
    }

    @Test func nestedReaderFreezesOrderAndPreservesPhysicalRoutesAcrossBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("collection.json")
        let store = MCCollectionStore(fileURL: file)
        let x = try store.add(.init(sourceKey: "nested.x", key: "book", title: "X"),
            chapters: [.init(key: "one", chapterNumber: 1), .init(key: "four", chapterNumber: 4)])
        let y = try store.add(.init(sourceKey: "nested.y", key: "book", title: "Y"),
            chapters: [.init(key: "one", chapterNumber: 2), .init(key: "three", chapterNumber: 3)])
        let z = try store.add(.init(sourceKey: "nested.z", key: "book", title: "Z"), chapters: [.init(key: "one", chapterNumber: 1)])
        let xs = try #require(store.library.entry(x)).slots, ys = try #require(store.library.entry(y)).slots
        try store.change { state in
            try state.library.moveEntry(y, into: x)
            try state.library.moveEntry(z, into: y)
            try state.library.reorderContents(entryID: x, order: [.chapter(xs[0].id), .title(y), .chapter(xs[1].id)])
            try state.library.reorderContents(entryID: y, order: [.chapter(ys[0].id), .title(z), .chapter(ys[1].id)])
        }
        // Opening a child still allows the reader to leave it and continue in its parent.
        let sequence = try MCReaderSequence(entryID: y, slotID: ys[0].id, store: store)
        #expect(sequence.routes.map(\.entryID) == [x, y, z, y, x])
        #expect(sequence.routes.map(\.identifier.sourceKey) == ["nested.x", "nested.y", "nested.z", "nested.y", "nested.x"])
        #expect(sequence.adjacent(to: sequence.chapters[3], offset: 1)?.key == sequence.chapters[4].key)
        #expect(sequence.adjacent(to: sequence.chapters[1], offset: -1)?.key == sequence.chapters[0].key)
        let route = sequence.routes[2]
        let target = try #require(store.coverTarget(identifier: route.identifier, entryID: route.entryID,
            variantID: UUID(uuidString: route.displayChapter.key)))
        #expect(target.entryID == z)
        try store.change { _ = try $0.library.setRead(entryID: x, slotIDs: [xs[0].id, ys[0].id], read: true) }
        #expect(store.chapterCount(entryID: x) == 5 && store.unreadCount(entryID: x) == 3)
        #expect(store.chapterCount(entryID: y) == 3 && store.unreadCount(entryID: y) == 2)
        let backup = try store.backupData()
        let restored = MCCollectionStore(fileURL: root.appendingPathComponent("restored.json"))
        try restored.restore(backup)
        let restoredSequence = try MCReaderSequence(entryID: x, slotID: xs[0].id, store: restored)
        #expect(restoredSequence.routes.map(\.identifier) == sequence.routes.map(\.identifier))
        #expect(restored.unreadCount(entryID: x) == 3)
        try store.change { try $0.library.moveEntry(y, into: nil) }
        #expect(sequence.routes.count == 5) // In-flight reader sessions never reorder beneath the reader.
        #expect(store.chapterCount(entryID: x) == 2)
        #expect(MCCollectionStore(fileURL: file).library.entry(y)?.parentEntryID == nil)
    }

    @Test func libraryReaderLoadsClosesAndReopens() async throws {
        await SourceManager.shared.waitForSourcesLoad()
        let sources = SourceStore.shared.sourcesByKey
        let disabled = SourceStore.shared.disabledSourceKeys
        defer { SourceStore.shared.update(sourcesByKey: sources, disabledSourceKeys: disabled) }
        let key = "mc.presentation.\(UUID().uuidString)"
        var testSources = sources
        testSources[key] = AidokuRunner.Source(url: nil, key: key, name: "Presentation", version: 1,
            languages: ["en"], contentRating: .safe, runner: MCPageRoutingRunner())
        SourceStore.shared.update(sourcesByKey: testSources, disabledSourceKeys: disabled)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MCCollectionStore(fileURL: root.appendingPathComponent("collection.json"))
        let manga = AidokuRunner.Manga(sourceKey: key, key: "book", title: "Presentation")
        let id = try store.add(manga, chapters: [.init(key: "one", chapterNumber: 1), .init(key: "two", chapterNumber: 2)])
        let entry = try #require(store.library.entry(id))
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let state = MCReaderPresentationTestState()
        let host = UIHostingController(rootView: MCReaderPresentationTestHost(state: state))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        try #require(await Self.waitForPresentation { host.viewIfLoaded?.window != nil })
        for slot in entry.slots {
            let sequence = try MCReaderSequence(entryID: id, slotID: slot.id, store: store)
            state.sheet = MCReaderSheet(sequence: sequence)
            try #require(await Self.waitForPresentation { Self.presentedReader(in: host) != nil })
            let reader = try #require(Self.presentedReader(in: host))
            try #require(await Self.waitForPresentation {
                reader.viewIfLoaded?.window != nil && reader.transitionCoordinator == nil && !reader.pages.isEmpty
            })
            #expect(reader.collectionSequence === sequence)
            #expect(reader.chapter.key == sequence.initialKey)
            #expect(reader.pages.first?.sourceId == key)
            #expect(host.presentedViewController == nil)
            #expect(reader.isNavigationScreen)
            #expect((reader.navigationController?.viewControllers.count ?? 0) > 1)
            reader.close()
            try #require(await Self.waitForPresentation { state.sheet == nil && Self.presentedReader(in: host) == nil })
        }
    }

    private static func presentedReader(in controller: UIViewController?) -> ReaderViewController? {
        guard let controller else { return nil }
        if let reader = controller as? ReaderViewController { return reader }
        if let navigation = controller as? UINavigationController {
            return presentedReader(in: navigation.topViewController)
        }
        return controller.children.lazy.compactMap { presentedReader(in: $0) }.first
    }

    private static func waitForPresentation(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return false }
        }
        return condition()
    }

    @Test func unreadCountsFollowSavedProgressOverridesAndRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("collection.json")
        let store = MCCollectionStore(fileURL: file)
        let manga = AidokuRunner.Manga(sourceKey: "counts", key: "book", title: "Counts")
        let id = try store.add(manga, chapters: [.init(key: "one", chapterNumber: 1), .init(key: "two", chapterNumber: 2)])
        #expect(store.unreadCount(entryID: id) == 2)
        let first = try #require(store.library.entry(id)?.slots.first)
        try store.change { _ = try $0.library.setRead(entryID: id, slotIDs: [first.id], read: true) }
        #expect(store.unreadCount(entryID: id) == 1)
        try store.change { state in
            try state.library.editEntry(id) { $0.slots[0].completionOverride = false }
        }
        #expect(store.unreadCount(entryID: id) == 2)
        #expect(MCCollectionStore(fileURL: file).unreadCount(entryID: id) == 2)
    }

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

    @Test func aibRoundTripPreservesCustomCoversAndMixedChapterVariants() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = MCCollectionStore(fileURL: root.appendingPathComponent("original.json"))
        let first = AidokuRunner.Manga(sourceKey: "first-source", key: "book", title: "First")
        let second = AidokuRunner.Manga(sourceKey: "second-source", key: "book", title: "Second")
        let entryID = try store.add(first, chapters: [.init(key: "same", chapterNumber: 1)])
        try store.addChapter(.init(key: "same", chapterNumber: 1), from: second, to: entryID, title: "Alternate")
        let secondEntry = try store.add(AidokuRunner.Manga(sourceKey: "third", key: "other", title: "Other"),
                                        chapters: [.init(key: "other", chapterNumber: 2)])
        #expect(store.addToReading([entryID, secondEntry]))
        try store.change { state in
            try state.library.editEntry(entryID) { entry in
                let alternative = try #require(entry.slots.last?.preferred)
                entry.slots[0].variants.append(alternative)
                entry.slots[0].preferredID = alternative.id
                entry.slots.removeLast()
                entry.titleOverride = "My custom entry"
            }
        }
        let variantID = try #require(store.library.entry(entryID)?.slots.first?.preferredID)
        let target = try #require(store.coverTarget(
            identifier: .init(sourceKey: second.sourceKey, mangaKey: second.key, chapterKey: "same"),
            entryID: entryID, variantID: variantID
        ))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        let coverData = try #require(image.pngData())
        try store.setCover(data: coverData, target: target, forEntry: true)
        try store.setCover(data: coverData, target: target, forEntry: false)
        let slotID = try #require(store.library.entry(entryID)?.slots.first?.id)
        try store.change { state in
            _ = try state.library.setRead(entryID: entryID, slotIDs: [slotID], read: true)
        }

        let backup = Backup(
            collectionData: try store.backupData(), collectionEntryCount: store.library.entries.count,
            library: [], history: [], manga: [], chapters: [],
            trackItems: [], readingSessions: [], vocabulary: [], updates: [], categories: [],
            sources: [], sourceLists: [], settings: nil, date: .now, name: nil, automatic: true, version: "test"
        )
        let backupURL = root.appendingPathComponent("Midoku-Latest.aib")
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        try encoder.encode(backup).write(to: backupURL)
        let loaded = try #require(Backup.load(from: backupURL))
        #expect(BackupInfo.load(from: backupURL)?.counts.collection == 2)
        let restored = MCCollectionStore(fileURL: root.appendingPathComponent("restored.json"))
        try restored.restore(try #require(loaded.collectionData))

        #expect(restored.library.entries.map(\.id) == [entryID, secondEntry])
        #expect(restored.library.readingIDs == [entryID, secondEntry])
        let entry = try #require(restored.library.entry(entryID))
        #expect(restored.library.title(entry) == "My custom entry")
        #expect(entry.slots.count == 1)
        #expect(entry.slots[0].variants.count == 2)
        #expect(entry.slots[0].preferredID == variantID)
        #expect(restored.library.isRead(entry.slots[0]))
        #expect(restored.library.covers.first(where: { $0.id == entry.coverID })?.data != nil)
        #expect(restored.library.covers.first(where: { $0.id == entry.slots[0].preferred?.edits.coverID })?.data != nil)
        #expect(restored.library.chapter(entry.slots[0].preferred?.chapterID ?? UUID())?.identity.listing.externalID == second.key)
        try restored.snapshot.validate()
    }

    @Test func readingQueueSurvivesRestartAndPrunesDeletedEntries() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("collection.json")
        let store = MCCollectionStore(fileURL: file)
        try store.change { state in
            _ = try state.library.createManual(title: "One")
            _ = try state.library.createManual(title: "Two")
            _ = try state.library.createManual(title: "Three")
        }
        let ids = store.library.entries.map(\.id)
        #expect(store.addToReading([ids[0], ids[1]]))
        #expect(store.addToReading([ids[0]]))
        #expect(store.library.readingIDs == Array(ids.prefix(2)))
        #expect(store.addRandomToReading(count: 10))
        #expect(store.library.readingIDs == ids)
        #expect(MCCollectionStore(fileURL: file).readingEntries.map(\.id) == ids)
        try store.change { $0.library.removeEntries([ids[1]]) }
        #expect(store.library.readingIDs == [ids[0], ids[2]])
        #expect(MCCollectionStore(fileURL: file).readingEntries.map(\.id) == [ids[0], ids[2]])
        #expect(store.removeFromReading(Set(store.library.readingIDs)))
        #expect(store.library.readingIDs.isEmpty)
        #expect(store.library.entries.map(\.id) == [ids[0], ids[2]])
        #expect(MCCollectionStore(fileURL: file).readingEntries.isEmpty)

        // Collections saved before Reading mode do not have a readingEntryIDs key.
        var legacy = try #require(JSONSerialization.jsonObject(with: store.backupData()) as? [String: Any])
        var library = try #require(legacy["library"] as? [String: Any])
        library.removeValue(forKey: "readingEntryIDs")
        legacy["library"] = library
        let decoded = try JSONDecoder().decode(MCCollectionSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.library.readingIDs.isEmpty)
        try decoded.validate()
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
            controls.toolbar.totalPages = 25
            controls.toolbar.currentPage = 1
            let host = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 800))
            controls.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(controls)
            NSLayoutConstraint.activate([
                controls.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                controls.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                controls.bottomAnchor.constraint(equalTo: host.bottomAnchor)
            ])
            host.layoutIfNeeded()
            let slider = controls.toolbar.sliderView
            let sliderFrame = slider.convert(slider.bounds, to: controls)
            for button in [controls.closeButton, controls.webButton, controls.chaptersButton, controls.autoScrollButton, controls.settingsButton] {
                let frame = button.convert(button.bounds, to: controls)
                #expect(frame.minY >= sliderFrame.maxY)
                #expect(button.configuration?.title == nil)
                #expect(frame.height >= 44 && frame.width >= 44)
                #expect(frame.maxX <= controls.bounds.maxX)
            }
            #expect(controls.toolbar.hitTest(slider.center, with: nil) === slider)
        }
    }

}

@MainActor @Observable
private final class MCReaderPresentationTestState {
    var sheet: MCReaderSheet?
}

private struct MCReaderPresentationTestHost: View {
    @Bindable var state: MCReaderPresentationTestState
    var body: some View {
        NavigationStack {
            Color.clear.modifier(MCReaderPresentation(sheet: $state.sheet))
        }
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

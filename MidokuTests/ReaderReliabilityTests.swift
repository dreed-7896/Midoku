import AidokuRunner
import Foundation
import Testing
import UIKit
@testable import Midoku

@MainActor
@Suite("Reader resume and resource limits", .serialized)
struct ReaderReliabilityTests {
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

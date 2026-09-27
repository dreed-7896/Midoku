#if DEBUG
import AidokuRunner
import Foundation
import UIKit

@MainActor
enum MCCollectionPreview {
    static var entryID: UUID?
    static func prepare() {
        guard ProcessInfo.processInfo.arguments.contains("--collection-preview") else { return }
        let args = ProcessInfo.processInfo.arguments
        AppSettings.flags.libraryRefreshInProgress.reset()
        AppSettings.appearance.accent.set(args.contains("--accent-preview") ? "#AF52DE" : MidokuAccent.defaultHex)
        AppSettings.appearance.chapterGridStyle.set(args.contains("--chapter-compact-preview") ? .compact : args.contains("--chapter-clean-preview") ? .clean : .standard)
        AppSettings.appearance.layout.set(args.contains("--compact-preview") ? .compact : .standard)
        UserDefaults.standard.set(true, forKey: "Midoku.collectionGrid")
        UserDefaults.standard.set(args.contains(where: { $0.hasPrefix("--chapter-") }), forKey: "Midoku.chapterGrid")
        let store = MCCollectionStore.shared
        do {
            try store.change { $0 = MCCollectionSnapshot() }
            let a = AidokuRunner.Manga(sourceKey: "preview.a", key: "book", title: "The Paper Lantern",
                authors: ["Midoku Preview"], description: "An editable edition with chapters collected from different sources.")
            let b = AidokuRunner.Manga(sourceKey: "preview.b", key: "book", title: "The Paper Lantern")
            let id = try store.add(a, chapters: [20, 22, 23, 24].map { .init(key: "c\($0)", title: $0 == 24 ? nil : "Across the quiet city", chapterNumber: Float($0)) }, status: .reading)
            try store.addChapter(.init(key: "c21", title: "The missing chapter", chapterNumber: 21), from: b, to: id, title: "Chapter 21")
            try store.change { state in
                let category = MCCategory(name: "Reading")
                state.categories = [category, MCCategory(name: "Favorites")]
                state.legacyCategoriesImported = true
                try state.library.editEntry(id) { $0.categoryIDs = [category.id] }
                if let data = UIImage(named: "MidokuArtwork")?.jpegData(compressionQuality: 0.6) {
                    let cover = MCLibraryCover(data: data); state.library.covers.append(cover)
                    try state.library.editEntry(id) { entry in
                        entry.coverID = cover.id
                        for i in entry.slots.indices { entry.slots[i].variants[0].edits.coverID = cover.id }
                    }
                }
                for i in state.connections.indices { state.connections[i].name = i == 0 ? "Source A" : "Source B" }
                let other = try state.library.createManual(title: "Weekend reading", description: "Your next collection starts here.")
                if let cover = state.library.covers.first { try state.library.editEntry(other) { $0.coverID = cover.id } }
                _ = try state.library.createManual(title: "Stories for later")
            }
            entryID = id
            if args.contains("--empty-preview") { try store.change { $0.library.entries.removeAll() } }
        } catch { store.error = error.localizedDescription }
    }

    static func installReaderSources() async {
        await SourceManager.shared.waitForSourcesLoad()
        await SourceManager.shared.installPreviewSources(["preview.a", "preview.b"].map { key in
            AidokuRunner.Source(url: nil, key: key, name: key, version: 1, languages: ["en"], contentRating: .safe, runner: MCPreviewRunner())
        })
    }
}

private struct MCPreviewRunner: AidokuRunner.Runner {
    let features = AidokuRunner.SourceFeatures()
    func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult { .init(entries: [], hasNextPage: false) }
    func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga { manga }
    func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] {
        await MainActor.run {
            guard let image = UIImage(named: "MidokuArtwork") else { return [] }
            return (0..<8).map { _ in .init(content: .image(image)) }
        }
    }
}
#endif

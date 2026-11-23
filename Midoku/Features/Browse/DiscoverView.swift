import AidokuRunner
import SwiftUI

struct MCDiscoverFeed: Codable, Identifiable {
    var id = UUID()
    let sourceKey: String
    let sourceName: String
    let listingID: String
    var listingName: String
    /// Search shelves run a query and/or filters instead of a listing tab.
    var query: String?
    var filters: [FilterValue]?
    /// Left over from the removed multi-extension artist shelves; such shelves are dropped on load.
    var artists: [String]?
    /// Artist shelves: the newest titles by these artists.
    var artistNames: [String]?
    /// Artist shelves: the extensions searched together; `sourceKey` is the first.
    var sourceKeys: [String]?
    /// How the shelf shows its titles; nil uses the default for its position.
    var layout: MCShelfLayout?
    /// Feed shelves: tabs from several extensions merged into one list, newest first.
    var feedTabs: [MCFeedTab]?
    /// Feed shelves: covers per row in the feed grid.
    var feedColumns: Int?

    var isLegacyArtists: Bool { artists != nil }
    var isArtists: Bool { artistNames != nil }
    var isSearch: Bool { query != nil || filters != nil }
    var isFeed: Bool { feedTabs != nil }
    var columns: Int { min(max(feedColumns ?? 3, 2), 5) }
    var allSourceKeys: [String] {
        if let feedTabs {
            var seen = Set<String>()
            return feedTabs.map(\.sourceKey).filter { seen.insert($0).inserted }
        }
        return sourceKeys ?? [sourceKey]
    }
    var subtitle: String {
        if let feedTabs {
            let sources = allSourceKeys.count
            return "Feed · \(feedTabs.count) tab\(feedTabs.count == 1 ? "" : "s") · \(sources) extension\(sources == 1 ? "" : "s")"
        }
        if let artistNames {
            return "\(sourceName) · \(artistNames.count) artist\(artistNames.count == 1 ? "" : "s")"
        }
        guard isSearch else { return sourceName }
        let count = filters?.count ?? 0
        return count > 0 ? "\(sourceName) · Search · \(count) filter\(count == 1 ? "" : "s")" : "\(sourceName) · Search"
    }
}

struct MCFeedTab: Codable, Hashable {
    let sourceKey: String
    let listingID: String
    var listingName: String
}

/// Feed shelves: the first page of each of several extension tabs merged into one list of at most
/// `limit` titles, newest first where extensions report an upload time. A title found in
/// several tabs shows once, from whichever comes first.
enum MCFeedShelfQuery {
    static let limit = 100

    /// Fails only when every tab fails. Each extension gets one task that loads its tabs one
    /// after another (an extension runs one call at a time anyway), and every call goes through
    /// `MCSourceCallLimiter` so a big feed can't starve the app's other extension calls.
    static func load(tabs: [(tab: MCFeedTab, source: AidokuRunner.Source)]) async throws -> [AidokuRunner.Manga] {
        var order: [String] = []
        var grouped: [String: (source: AidokuRunner.Source, tabs: [(index: Int, tab: MCFeedTab)])] = [:]
        for (index, item) in tabs.enumerated() {
            if grouped[item.tab.sourceKey] == nil {
                order.append(item.tab.sourceKey)
                grouped[item.tab.sourceKey] = (item.source, [])
            }
            grouped[item.tab.sourceKey]?.tabs.append((index, item.tab))
        }
        let results = await withTaskGroup(of: [(Int, Result<[AidokuRunner.Manga], Error>)].self) { group in
            for key in order {
                guard let entry = grouped[key] else { continue }
                let source = entry.source, sourceTabs = entry.tabs
                group.addTask {
                    var listings: [AidokuRunner.Listing] = []
                    var listingsError: Error?
                    do {
                        listings = try await MCSourceCallLimiter.shared.run { try await source.getListings() }
                    } catch {
                        listingsError = error
                    }
                    var out: [(Int, Result<[AidokuRunner.Manga], Error>)] = []
                    for (index, tab) in sourceTabs {
                        if Task.isCancelled { break }
                        if let listingsError {
                            out.append((index, .failure(listingsError)))
                            continue
                        }
                        guard let listing = listings.first(where: { $0.id == tab.listingID }) else {
                            out.append((index, .failure(MCFeedShelfError.missingTab(tab.listingName))))
                            continue
                        }
                        do {
                            let page = try await MCSourceCallLimiter.shared.run {
                                try await source.getMangaList(listing: listing, page: 1)
                            }
                            out.append((index, .success(page.entries)))
                        } catch {
                            out.append((index, .failure(error)))
                        }
                    }
                    return out
                }
            }
            var collected: [(Int, Result<[AidokuRunner.Manga], Error>)] = []
            for await part in group { collected += part }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
        var lists: [[AidokuRunner.Manga]] = []
        var firstError: Error?
        for result in results {
            switch result {
                case .success(let entries): lists.append(entries)
                case .failure(let error): firstError = firstError ?? error
            }
        }
        if lists.isEmpty, let firstError { throw firstError }
        return merge(lists, limit: limit)
    }

    /// When every title has an upload time the lists are sorted together by it. Otherwise
    /// they're merged head by head (each tab is assumed newest first): dated heads by time,
    /// the rest by position, ties going to the earlier tab. Repeats are dropped as they come.
    static func merge(_ lists: [[AidokuRunner.Manga]], limit: Int) -> [AidokuRunner.Manga] {
        let now = Date().timeIntervalSince1970
        var seenIDs = Set<String>()
        var seenTitles = Set<String>()
        var result: [AidokuRunner.Manga] = []
        func accept(_ manga: AidokuRunner.Manga) {
            let id = "\(manga.sourceKey)|\(manga.key)"
            let title = titleKey(manga.title)
            guard !seenIDs.contains(id), title.isEmpty || !seenTitles.contains(title) else { return }
            seenIDs.insert(id)
            if !title.isEmpty { seenTitles.insert(title) }
            result.append(manga)
        }

        let all = lists.flatMap { $0 }
        if !all.isEmpty, all.allSatisfy({ uploadTime($0, now: now) != nil }) {
            typealias Item = (tab: Int, position: Int, manga: AidokuRunner.Manga, time: TimeInterval)
            var items: [Item] = []
            for (tab, list) in lists.enumerated() {
                for (position, manga) in list.enumerated() {
                    items.append((tab: tab, position: position, manga: manga, time: uploadTime(manga, now: now) ?? 0))
                }
            }
            let ordered = items.sorted { lhs, rhs in
                if lhs.time != rhs.time { return lhs.time > rhs.time }
                if lhs.tab != rhs.tab { return lhs.tab < rhs.tab }
                return lhs.position < rhs.position
            }
            for item in ordered where result.count < limit { accept(item.manga) }
            return result
        }

        var positions = Array(repeating: 0, count: lists.count)
        while result.count < limit {
            var best: Int?
            for index in lists.indices where positions[index] < lists[index].count {
                guard let current = best else { best = index; continue }
                let left = uploadTime(lists[index][positions[index]], now: now)
                let right = uploadTime(lists[current][positions[current]], now: now)
                if let left, let right, left != right {
                    if left > right { best = index }
                } else if positions[index] < positions[current] {
                    best = index
                }
            }
            guard let best else { break }
            let manga = lists[best][positions[best]]
            positions[best] += 1
            accept(manga)
        }
        return result
    }

    /// When the title was uploaded: extensions report it in `nextUpdateTime` on results, or on
    /// chapters. Times in the future are real next-update times and are ignored.
    static func uploadTime(_ manga: AidokuRunner.Manga, now: TimeInterval = Date().timeIntervalSince1970) -> TimeInterval? {
        if let time = manga.nextUpdateTime, time > 0, TimeInterval(time) <= now + 86_400 {
            return TimeInterval(time)
        }
        return manga.chapters?.compactMap(\.dateUploaded).max()?.timeIntervalSince1970
    }

    /// The title without artist, circle, event and language tags, so
    /// "[Artist (Circle)] Title [English]" and "Title" match. Bracketed parts are dropped;
    /// parenthesised ones too unless they number the work, like "(Part 2)".
    static func titleKey(_ title: String) -> String {
        var stripped = title.replacing(#/\[[^\]]*\]|\{[^}]*\}|【[^】]*】|［[^］]*］/#, with: " ")
        stripped = stripped.replacing(#/\([^)]*\)|（[^）]*）/#) { match in
            let inner = String(match.output)
            return inner.wholeMatch(of: #/(?i)[(（]\s*(part|vol\.?|volume|ch\.?|chapter|season|book|\#)?\s*\d+\s*[)）]/#) != nil ? inner : " "
        }
        let core = normalized(stripped)
        return core.isEmpty ? normalized(title) : core
    }

    private static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}

enum MCFeedShelfError: LocalizedError {
    case missingTab(String)
    var errorDescription: String? {
        switch self {
        case .missingTab(let name): "The tab “\(name)” is no longer available. Edit the shelf and pick another tab."
        }
    }
}

/// Home's extension calls run at most `limit` at a time. An extension holds a Swift
/// concurrency thread while its network requests run, so many calls at once use up the shared
/// thread pool and every extension in the app stops loading. Waiting here holds no thread.
actor MCSourceCallLimiter {
    static let shared = MCSourceCallLimiter(limit: 2)
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func run<T>(_ operation: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// How an artist shelf asks its extension for the artists' newest titles: the extension's
/// Artist field with the names joined by `|`, sorted by latest when it offers that.
enum MCArtistShelfQuery {
    static func filters(for artists: [String], source: AidokuRunner.Source) async throws -> [FilterValue] {
        let available = try await source.getSearchFilters()
        var artistID: String?
        var authorID: String?
        var sort: SortFilterValue?
        for filter in available {
            let label = "\(filter.id) \(filter.title ?? "")".lowercased()
            switch filter.value {
                case .text:
                    if label.contains("artist") {
                        artistID = artistID ?? filter.id
                    } else if label.contains("author") || label.contains("creator") {
                        authorID = authorID ?? filter.id
                    }
                case let .sort(_, options, _):
                    guard sort == nil else { continue }
                    let keywords = ["latest", "date added", "newest", "recent", "updated"]
                    if let index = options.firstIndex(where: { option in keywords.contains { option.lowercased().contains($0) } }) {
                        sort = SortFilterValue(id: filter.id, index: index, ascending: false)
                    }
                default: break
            }
        }
        guard let id = artistID ?? authorID else {
            throw MCArtistShelfError.noArtistField
        }
        var values: [FilterValue] = [.text(id: id, value: artists.joined(separator: "|"))]
        if let sort { values.append(.sort(sort)) }
        return values
    }

    /// The newest titles by the artists from every extension at once, newest first by upload
    /// time. A title found in several extensions shows once, from the first one in the shelf.
    /// Fails only when every extension fails.
    static func load(artists: [String], sources: [AidokuRunner.Source]) async throws -> [AidokuRunner.Manga] {
        let results = await withTaskGroup(of: (Int, Result<[AidokuRunner.Manga], Error>).self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask {
                    do {
                        let result = try await MCSourceCallLimiter.shared.run {
                            let values = try await Self.filters(for: artists, source: source)
                            return try await source.getSearchMangaList(query: nil, page: 1, filters: values)
                        }
                        return (index, .success(result.entries))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var collected: [(Int, Result<[AidokuRunner.Manga], Error>)] = []
            for await item in group { collected.append(item) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
        var lists: [[AidokuRunner.Manga]] = []
        var firstError: Error?
        for result in results {
            switch result {
                case .success(let entries): lists.append(entries)
                case .failure(let error): firstError = firstError ?? error
            }
        }
        if lists.isEmpty, let firstError { throw firstError }
        return merge(lists)
    }

    /// Interleaves the lists by position (each is newest first), then orders by upload time
    /// where extensions report one, dropping repeated titles.
    static func merge(_ lists: [[AidokuRunner.Manga]]) -> [AidokuRunner.Manga] {
        var interleaved: [AidokuRunner.Manga] = []
        let longest = lists.map(\.count).max() ?? 0
        for index in 0..<longest {
            for list in lists where index < list.count { interleaved.append(list[index]) }
        }
        var seen = Set<String>()
        let unique = interleaved.filter { manga in
            let title = MCFeedShelfQuery.titleKey(manga.title)
            let key = title.isEmpty ? "\(manga.sourceKey)|\(manga.key)" : title
            return seen.insert(key).inserted && seen.insert("\(manga.sourceKey)|\(manga.key)").inserted
        }
        guard lists.count > 1 else { return unique }
        let dated: [(offset: Int, manga: AidokuRunner.Manga, time: TimeInterval?)] = unique.enumerated().map { item in
            (offset: item.offset, manga: item.element, time: item.element.nextUpdateTime.map { TimeInterval($0) })
        }
        return dated.sorted { lhs, rhs in
            switch (lhs.time, rhs.time) {
                case let (left?, right?) where left != right: return left > right
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.offset < rhs.offset
            }
        }.map(\.manga)
    }

    /// Names typed or picked, split on `|`, without blanks or repeats.
    static func names(from text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}

enum MCArtistShelfError: LocalizedError {
    case noArtistField
    var errorDescription: String? {
        "This extension has no Artist search. Edit the shelf and pick another extension."
    }
}

/// Midoku Web's three shelf styles: the paged `.hero` cards, the cover `.rail` and the `.grid3` panel.
enum MCShelfLayout: String, Codable, CaseIterable {
    case hero, rail, grid

    var title: String {
        switch self {
        case .hero: "Featured cards"
        case .rail: "Cover row"
        case .grid: "Two-row grid"
        }
    }

    var systemImage: String {
        switch self {
        case .hero: "rectangle.portrait.on.rectangle.portrait"
        case .rail: "rectangle.split.3x1"
        case .grid: "square.grid.3x2"
        }
    }
}

@MainActor
final class MCDiscoverModel: ObservableObject {
    private static let key = "Midoku.discoverFeeds.v1"
    private static let seenKey = "Midoku.discoverSeen.v1"
    @Published var feeds: [MCDiscoverFeed] = []
    @Published var entries: [UUID: [AidokuRunner.Manga]] = [:]
    /// Results a search shelf had not shown before its latest load.
    @Published var newKeys: [UUID: Set<String>] = [:]
    private var seen: [String: [String]] = [:]
    @Published var errors: [UUID: String] = [:]
    @Published var loading = Set<UUID>()

    private var restoreObserver: NSObjectProtocol?

    init() {
        loadSaved()
        restoreObserver = NotificationCenter.default.addObserver(forName: .midokuAppStateRestored, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.entries = [:]; self.errors = [:]; self.newKeys = [:]
                self.loadSaved()
                Task { await self.reload() }
            }
        }
    }

    private func loadSaved() {
        if let data = UserDefaults.standard.data(forKey: Self.key), let feeds = try? JSONDecoder().decode([MCDiscoverFeed].self, from: data) {
            self.feeds = feeds.filter { !$0.isLegacyArtists }
            if self.feeds.count != feeds.count { save() }
        }
        seen = UserDefaults.standard.dictionary(forKey: Self.seenKey) as? [String: [String]] ?? [:]
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(feeds), forKey: Self.key) }
    func add(source: AidokuRunner.Source, listing: AidokuRunner.Listing) {
        guard !feeds.contains(where: { $0.sourceKey == source.key && $0.listingID == listing.id }) else { return }
        feeds.append(.init(sourceKey: source.key, sourceName: source.name, listingID: listing.id, listingName: listing.name))
        save()
    }
    func append(_ feed: MCDiscoverFeed) {
        feeds.append(feed)
        save()
        Task { await load(feed, force: true) }
    }
    /// Replaces a shelf after editing and reloads it if what it shows changed.
    func update(_ feed: MCDiscoverFeed) {
        guard let index = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        let old = feeds[index]
        feeds[index] = feed
        save()
        if old.sourceKey != feed.sourceKey || old.listingID != feed.listingID || old.query != feed.query
            || old.artistNames != feed.artistNames || old.sourceKeys != feed.sourceKeys || old.feedTabs != feed.feedTabs
            || (try? JSONEncoder().encode(old.filters)) != (try? JSONEncoder().encode(feed.filters)) {
            entries[feed.id] = nil; errors[feed.id] = nil; newKeys[feed.id] = nil
            seen[feed.id.uuidString] = nil
            UserDefaults.standard.set(seen, forKey: Self.seenKey)
            Task { await load(feed, force: true) }
        }
    }
    func addSearch(source: AidokuRunner.Source, query: String, filters: [FilterValue], name: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        feeds.append(.init(
            sourceKey: source.key, sourceName: source.name, listingID: "",
            listingName: title.isEmpty ? (trimmed.isEmpty ? "Filtered search" : "“\(trimmed)”") : title,
            query: trimmed, filters: filters
        ))
        save()
    }
    /// Marks results the shelf has not shown before; the first load only records what exists.
    private func recordSeen(_ feed: MCDiscoverFeed, keys: [String]) {
        newKeys[feed.id] = recordSeenTokens(feed, tokens: keys)
    }
    /// Returns the tokens not seen on earlier loads and remembers them.
    func recordSeenTokens(_ feed: MCDiscoverFeed, tokens keys: [String]) -> Set<String> {
        let id = feed.id.uuidString
        var fresh = Set<String>()
        if let previous = seen[id] {
            let known = Set(previous)
            fresh = Set(keys.filter { !known.contains($0) })
            var merged = keys
            merged.append(contentsOf: previous.filter { !Set(keys).contains($0) })
            seen[id] = Array(merged.prefix(1000))
        } else {
            seen[id] = keys
        }
        UserDefaults.standard.set(seen, forKey: Self.seenKey)
        return fresh
    }
    func layout(of feed: MCDiscoverFeed) -> MCShelfLayout {
        feed.layout ?? (feeds.first?.id == feed.id ? .hero : .rail)
    }
    func setLayout(_ layout: MCShelfLayout, for feed: MCDiscoverFeed) {
        guard let index = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        feeds[index].layout = layout
        save()
    }
    func setColumns(_ columns: Int, for feed: MCDiscoverFeed) {
        guard let index = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        feeds[index].feedColumns = columns
        save()
    }
    func load(_ feed: MCDiscoverFeed, force: Bool = false) async {
        guard !loading.contains(feed.id), force || entries[feed.id] == nil else { return }
        // Sources load after launch; the shelf retries when its source appears.
        guard SourceStore.shared.hasLoaded else { return }
        if let tabs = feed.feedTabs {
            let available = tabs.compactMap { tab -> (tab: MCFeedTab, source: AidokuRunner.Source)? in
                guard !SourceStore.shared.isDisabled(sourceKey: tab.sourceKey),
                      let source = SourceStore.shared.source(for: tab.sourceKey) else { return nil }
                return (tab, source)
            }
            guard !available.isEmpty else {
                errors[feed.id] = "These extensions are unavailable. Open Extensions to enable or install them."
                return
            }
            loading.insert(feed.id); errors[feed.id] = nil
            defer { loading.remove(feed.id) }
            do {
                let items = try await MCFeedShelfQuery.load(tabs: available)
                try Task.checkCancellation()
                entries[feed.id] = items
                recordSeen(feed, keys: items.map(\.key))
            } catch is CancellationError { }
            catch { errors[feed.id] = error.midokuDescription() }
            return
        }
        if let artists = feed.artistNames {
            let sources = feed.allSourceKeys.compactMap { key in
                SourceStore.shared.isDisabled(sourceKey: key) ? nil : SourceStore.shared.source(for: key)
            }
            guard !sources.isEmpty else {
                errors[feed.id] = "These extensions are unavailable. Open Extensions to enable or install them."
                return
            }
            loading.insert(feed.id); errors[feed.id] = nil
            defer { loading.remove(feed.id) }
            do {
                let items = try await MCArtistShelfQuery.load(artists: artists, sources: sources)
                try Task.checkCancellation()
                entries[feed.id] = items
                recordSeen(feed, keys: items.map(\.key))
            } catch is CancellationError { }
            catch { errors[feed.id] = error.midokuDescription() }
            return
        }
        guard let source = SourceStore.shared.source(for: feed.sourceKey), !SourceStore.shared.isDisabled(sourceKey: feed.sourceKey) else {
            errors[feed.id] = "This extension is unavailable. Open Extensions to enable or install it."
            return
        }
        loading.insert(feed.id); errors[feed.id] = nil
        defer { loading.remove(feed.id) }
        do {
            let isSearch = feed.isSearch, query = feed.query ?? "", filters = feed.filters ?? [], listingID = feed.listingID
            let fetched: AidokuRunner.MangaPageResult? = try await MCSourceCallLimiter.shared.run {
                if isSearch {
                    return try await source.getSearchMangaList(query: query.isEmpty ? nil : query, page: 1, filters: filters)
                }
                guard let listing = try await source.getListings().first(where: { $0.id == listingID }) else { return nil }
                return try await source.getMangaList(listing: listing, page: 1)
            }
            guard let result = fetched else {
                errors[feed.id] = "This tab is no longer available. Remove this shelf and add another tab."
                return
            }
            try Task.checkCancellation()
            var unique = Set<String>()
            let items = result.entries.filter { unique.insert($0.key).inserted }
            entries[feed.id] = items
            if feed.isSearch { recordSeen(feed, keys: items.map(\.key)) }
        } catch is CancellationError { }
        catch { errors[feed.id] = error.midokuDescription() }
    }
    func remove(_ feed: MCDiscoverFeed) {
        feeds.removeAll { $0.id == feed.id }
        entries[feed.id] = nil; errors[feed.id] = nil; newKeys[feed.id] = nil
        seen[feed.id.uuidString] = nil
        UserDefaults.standard.set(seen, forKey: Self.seenKey)
        save()
    }
    func move(_ feed: MCDiscoverFeed, by offset: Int) {
        guard let index = feeds.firstIndex(where: { $0.id == feed.id }), feeds.indices.contains(index + offset) else { return }
        feeds.swapAt(index, index + offset)
        save()
    }
    func reload() async {
        // Each shelf keeps its covers and previous results while refreshing.
        for feed in feeds { await load(feed, force: true) }
    }
}

final class DiscoverViewController: UIHostingController<MCDiscoverView> {
    private let model: MCDiscoverModel

    init() {
        let model = MCDiscoverModel()
        self.model = model
        super.init(rootView: MCDiscoverView(model: model))
        rootView.openManga = { [weak self] manga in
            guard let self else { return }
            navigationController?.pushViewController(MangaViewController(source: SourceStore.shared.source(for: manga.sourceKey), manga: manga, parent: self), animated: true)
        }
        rootView.openListing = { [weak self] feed in
            guard let self else { return }
            if let tab = feed.feedTabs?.first {
                self.openFeedTab(tab)
                return
            }
            guard let source = SourceStore.shared.source(for: feed.sourceKey) else { return }
            // Opens the extension's own page: on the shelf's tab, or searching with the shelf's term and filters.
            if let artists = feed.artistNames {
                Task { @MainActor in
                    let filters = (try? await MCArtistShelfQuery.filters(for: artists, source: source)) ?? []
                    self.navigationController?.pushViewController(NewSourceViewController(source: source, initialFilters: filters), animated: true)
                }
                return
            }
            if feed.isSearch {
                let controller = NewSourceViewController(source: source, searchQuery: feed.query, initialFilters: feed.filters ?? [])
                navigationController?.pushViewController(controller, animated: true)
                return
            }
            Task { @MainActor in
                let index = (try? await source.getListings())?.firstIndex { $0.id == feed.listingID }
                self.navigationController?.pushViewController(NewSourceViewController(source: source, initialListingIndex: index), animated: true)
            }
        }
        rootView.openShelves = { [weak self] in self?.showShelves() }
        rootView.openUpdates = { [weak self] page in
            self?.navigationController?.pushViewController(UpdatesHistoryController(page: page), animated: true)
        }
        rootView.openExtensions = { [weak self] in
            self?.navigationController?.pushViewController(BrowseViewController(), animated: true)
        }
        rootView.openSource = { [weak self] source in
            let controller: UIViewController = if let legacySource = source.legacySource {
                SourceViewController(source: legacySource)
            } else {
                NewSourceViewController(source: source)
            }
            self?.navigationController?.pushViewController(controller, animated: true)
        }
        title = "Home"
        navigationItem.largeTitleDisplayMode = .always
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func openFeedTab(_ tab: MCFeedTab) {
        guard let source = SourceStore.shared.source(for: tab.sourceKey) else { return }
        Task { @MainActor in
            let index = (try? await source.getListings())?.firstIndex { $0.id == tab.listingID }
            self.navigationController?.pushViewController(NewSourceViewController(source: source, initialListingIndex: index), animated: true)
        }
    }

    private func showShelves(kind: MCDiscoverConfiguration.Kind = .tab) {
        guard presentedViewController == nil else { return }
        present(UIHostingController(rootView: MCDiscoverConfiguration(model: model, kind: kind).midokuAccent()), animated: true)
    }
}

/// Discover has one entry point per action: the extension strip opens sources and
/// Manage, each shelf carries its own menu, and the final tile adds a shelf.
struct MCDiscoverView: View {
    @ObservedObject var model: MCDiscoverModel
    @ObservedObject private var sources = SourceStore.shared
    @State private var extensionUpdates = 0
    @State private var collection = MCCollectionStore.shared
    /// When Updates was last opened; newer updates count on the bell, like the web's `seenAt`.
    @AppStorage("Midoku.updatesSeenAt") private var updatesSeenAt: Double = 0

    private var newUpdates: Int {
        collection.library.updates.reduce(0) { $0 + ($1.discoveredAt.timeIntervalSince1970 > updatesSeenAt ? 1 : 0) }
    }
    var openManga: (AidokuRunner.Manga) -> Void = { _ in }
    var openListing: (MCDiscoverFeed) -> Void = { _ in }
    var openShelves: () -> Void = {}
    var openExtensions: () -> Void = {}
    var openUpdates: (UpdatesHistoryView.Page) -> Void = { _ in }
    var openSource: (AidokuRunner.Source) -> Void = { _ in }

    /// Enabled extensions with pinned ones first, so the most used are one tap away.
    private var installedSources: [AidokuRunner.Source] {
        let pinned = AppSettings.browse.pinnedList.get()
        return sources.sourcesByKey.values
            .filter { !sources.isDisabled(sourceKey: $0.key) }
            .sorted { lhs, rhs in
                let left = pinned.firstIndex(of: lhs.key) ?? .max, right = pinned.firstIndex(of: rhs.key) ?? .max
                return left != right ? left < right : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    init(model: MCDiscoverModel) {
        self.model = model
    }

    var body: some View {
        midokuBody.font(.mdBody)
    }

    @ViewBuilder private var midokuBody: some View {
        let installed = installedSources
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                let fresh = newUpdates
                MDPageHeader(kicker: "\(Date.now.formatted(.dateTime.weekday(.wide))) · \(fresh) new", title: "Home") {
                    MDIconButton(systemImage: "clock", label: "History") { openUpdates(.history) }
                    MDIconButton(systemImage: "bell", label: fresh > 0 ? "Updates, \(fresh) new" : "Updates", badge: fresh > 0 ? fresh : nil) {
                        updatesSeenAt = Date.now.timeIntervalSince1970
                        openUpdates(.updates)
                    }
                }
                if installed.isEmpty && sources.hasLoaded {
                    welcomeCard
                }
                // Shelves stay visible while sources load at launch; they fill in once sources arrive.
                if !installed.isEmpty || !sources.hasLoaded {
                    if !model.feeds.isEmpty {
                        ForEach(Array(model.feeds.enumerated()), id: \.element.id) { index, feed in
                            MCDiscoverShelf(feed: feed, index: index, model: model, openManga: openManga, openListing: openListing)
                                .task(id: "\(feed.id)-\(sources.hasLoaded)-\(sources.source(for: feed.sourceKey) != nil)") { await model.load(feed) }
                        }
                        addShelfTile
                    } else if !installed.isEmpty {
                        firstShelfCard
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color.mdBg)
        .refreshable { await model.reload() }
        .onAppear { extensionUpdates = AppSettings.browse.updateCount.get() }
        .midokuAccent()
    }

    // MARK: Extensions

    private func extensionStrip(_ installed: [AidokuRunner.Source]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Extensions").font(.mdTitle3.bold())
                Spacer()
                Button(action: openExtensions) {
                    HStack(spacing: 6) {
                        if extensionUpdates > 0 {
                            Text("\(extensionUpdates)")
                                .font(.mdCaption2.bold()).monospacedDigit().foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(.red, in: Rectangle())
                        }
                        Text("Manage")
                        Image(systemName: "chevron.right").font(.mdCaption.weight(.semibold))
                    }
                    .font(.mdSubheadline.weight(.medium))
                }
                .accessibilityLabel(extensionUpdates > 0 ? "Manage extensions, \(extensionUpdates) updates available" : "Manage extensions")
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(installed, id: \.key) { source in
                        Button { openSource(source) } label: {
                            VStack(spacing: 6) {
                                SourceIconView(sourceId: source.key, imageUrl: source.imageUrl, iconSize: 58)
                                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                                Text(source.name).font(.mdCaption).lineLimit(1).foregroundStyle(.primary)
                            }
                            .frame(width: 70)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Browse \(source.name)")
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var welcomeCard: some View {
        promptCard(
            symbol: "puzzlepiece.extension.fill",
            title: "Add your first extension",
            message: "Extensions are where stories come from. Install one to browse its catalogue and build your Home feed.",
            button: "Browse extensions",
            action: openExtensions
        )
    }

    // MARK: Shelves

    private var firstShelfCard: some View {
        promptCard(
            symbol: "rectangle.stack.badge.plus",
            title: "Build your feed",
            message: "Shelves show a tab from an extension, like Popular or Latest, rerun a search with filters, follow artists from your library, or merge tabs from several extensions into one feed. Add a few to see everything new in one place.",
            button: "Add a shelf",
            action: openShelves
        )
    }

    private var addShelfTile: some View {
        Button(action: openShelves) {
            Label("Add or reorder shelves", systemImage: "plus")
                .font(.mdSubheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 0)
                        .strokeBorder(Color.accentColor.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                )
                .contentShape(RoundedRectangle(cornerRadius: 0))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal)
    }

    private func promptCard(symbol: String, title: String, message: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol).font(.mdSystem(size: 34)).foregroundStyle(Color.accentColor)
            Text(title).font(.mdTitle2.bold())
            Text(message).font(.mdSubheadline).foregroundStyle(.secondary)
            Button(action: action) {
                Text(button).font(.mdHeadline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 0))
        .padding(.horizontal)
    }
}

private struct MCDiscoverNewBadge: View {
    var body: some View {
        Text("NEW").font(.mdCaption2.weight(.heavy)).foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.accentColor, in: Rectangle())
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

/// The first shelf: large paged cards with the cover, ranking, author and tags.
private struct MCDiscoverHero: View {
    let items: [AidokuRunner.Manga]
    let label: String
    let newKeys: Set<String>
    /// The extension of each title (artist shelves mix several).
    let source: (AidokuRunner.Manga) -> AidokuRunner.Source?
    let open: (AidokuRunner.Manga) -> Void
    @State private var position: String?

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.key) { index, manga in
                        Button { open(manga) } label: { card(manga, rank: index + 1) }
                            .buttonStyle(.plain)
                            .containerRelativeFrame(.horizontal)
                            .scrollTransition(axis: .horizontal) { content, phase in
                                content.scaleEffect(phase.isIdentity ? 1 : 0.94).opacity(phase.isIdentity ? 1 : 0.7)
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position)
            if items.count > 1 { dots }
        }
    }

    private var dots: some View {
        let current = items.firstIndex { $0.key == position } ?? 0
        return HStack(spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                Rectangle()
                    .fill(index == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityHidden(true)
    }

    private func card(_ manga: AidokuRunner.Manga, rank: Int) -> some View {
        let author = manga.authors?.first ?? manga.artists?.first
        let tags = Array((manga.tags ?? []).prefix(3))
        return Group {
            HStack(alignment: .bottom, spacing: 16) {
                image(manga, width: 128, height: 192)
                    .clipShape(RoundedRectangle(cornerRadius: 0))
                    .overlay(RoundedRectangle(cornerRadius: 0).strokeBorder(.white.opacity(0.15), lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("#\(rank)").font(.mdCaption.weight(.heavy)).monospacedDigit()
                        Text(label).font(.mdCaption.weight(.semibold)).lineLimit(1).opacity(0.8)
                        if newKeys.contains(manga.key) { MCDiscoverNewBadge() }
                    }
                    Text(manga.title).font(.mdTitle3.bold()).lineLimit(4).minimumScaleFactor(0.85)
                    if let author { Text(author).font(.mdSubheadline).lineLimit(1).opacity(0.8) }
                    if !tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag).font(.mdCaption2.weight(.semibold)).lineLimit(1)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(.white.opacity(0.18), in: Rectangle())
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, minHeight: 250, maxHeight: 250, alignment: .bottomLeading)
        .background {
            SourceImageView(source: source(manga), imageUrl: manga.cover ?? "", downsampleWidth: 200)
                .scaleEffect(1.4)
                .blur(radius: 30)
                .saturation(1.3)
                .overlay(LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .contentShape(RoundedRectangle(cornerRadius: 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Number \(rank), \(manga.title)\(author.map { ", by \($0)" } ?? "")")
    }

    private func image(_ manga: AidokuRunner.Manga, width: CGFloat, height: CGFloat) -> some View {
        SourceImageView(source: source(manga), imageUrl: manga.cover ?? "", width: width, height: height,
                        placeholder: "MidokuCoverPlaceholder").frame(width: width, height: height).clipped()
    }
}

struct MCDiscoverConfiguration: View {
    enum Kind: String, CaseIterable { case tab = "Tab", search = "Search", artists = "Artists", feed = "Feed" }

    @ObservedObject var model: MCDiscoverModel
    @ObservedObject private var sources = SourceStore.shared
    @Environment(\.dismiss) private var dismiss
    /// The shelf being edited; nil adds a new one.
    @State private var editingID: UUID?
    /// Opened from a shelf's options: only the editor, no shelf list.
    private let editOnly: Bool
    @State private var sourceKey = ""
    @State private var kind: Kind = .tab
    @State private var listingID = ""
    @State private var listings: [AidokuRunner.Listing] = []
    @State private var searchFilters: [AidokuRunner.Filter] = []
    @State private var query = ""
    @State private var enabledFilters: [FilterValue] = []
    @State private var shelfName = ""
    /// Artist shelves: names joined by `|`, typed or picked from the library.
    @State private var artistText = ""
    /// Artist shelves: the extensions picked, in the order picked.
    @State private var artistSourceKeys: [String] = []
    @State private var layout: MCShelfLayout?
    /// Feed shelves: the extensions picked, the tabs picked from them, each extension's tabs.
    @State private var feedSourceKeys: [String] = []
    @State private var feedTabs: [MCFeedTab] = []
    @State private var feedListings: [String: [AidokuRunner.Listing]] = [:]
    @State private var feedColumns = 3
    @State private var showFilters = false
    @State private var loading = false
    @State private var error: String?
    /// Keeps the edited shelf's tab and filters while its extension's options load.
    @State private var keepSelection = false

    init(model: MCDiscoverModel, kind: Kind = .tab, editing: MCDiscoverFeed? = nil) {
        self.model = model
        editOnly = editing != nil
        _kind = State(initialValue: kind)
        if let editing {
            _editingID = State(initialValue: editing.id)
            _sourceKey = State(initialValue: editing.sourceKey)
            _kind = State(initialValue: Self.kind(of: editing))
            _listingID = State(initialValue: editing.listingID)
            _query = State(initialValue: editing.query ?? "")
            _artistText = State(initialValue: (editing.artistNames ?? []).joined(separator: "|"))
            _artistSourceKeys = State(initialValue: editing.isArtists ? editing.allSourceKeys : [])
            _enabledFilters = State(initialValue: editing.filters ?? [])
            _shelfName = State(initialValue: editing.listingName)
            _layout = State(initialValue: editing.layout)
            _feedSourceKeys = State(initialValue: editing.isFeed ? editing.allSourceKeys : [])
            _feedTabs = State(initialValue: editing.feedTabs ?? [])
            _feedColumns = State(initialValue: editing.columns)
        }
        _keepSelection = State(initialValue: editing != nil)
    }

    private static func kind(of feed: MCDiscoverFeed) -> Kind {
        feed.isFeed ? .feed : feed.isArtists ? .artists : feed.isSearch ? .search : .tab
    }

    private func startEditing(_ feed: MCDiscoverFeed) {
        keepSelection = true
        editingID = feed.id
        sourceKey = feed.sourceKey
        kind = Self.kind(of: feed)
        listingID = feed.listingID
        query = feed.query ?? ""
        artistText = (feed.artistNames ?? []).joined(separator: "|")
        artistSourceKeys = feed.isArtists ? feed.allSourceKeys : []
        enabledFilters = feed.filters ?? []
        shelfName = feed.listingName
        layout = feed.layout
        feedSourceKeys = feed.isFeed ? feed.allSourceKeys : []
        feedTabs = feed.feedTabs ?? []
        feedColumns = feed.columns
    }

    private func resetForm() {
        editingID = nil
        query = ""; enabledFilters = []; shelfName = ""; artistText = ""; artistSourceKeys = []; layout = nil
        feedSourceKeys = []; feedTabs = []; feedColumns = 3
        listingID = listings.first?.id ?? ""
    }

    private var installed: [AidokuRunner.Source] {
        sources.sourcesByKey.values.filter { !sources.isDisabled(sourceKey: $0.key) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var canSave: Bool {
        guard sources.source(for: sourceKey) != nil else { return false }
        switch kind {
        case .tab:
            guard listings.contains(where: { $0.id == listingID }) else { return false }
            return editingID != nil || !model.feeds.contains { $0.sourceKey == sourceKey && $0.listingID == listingID && !$0.isSearch && !$0.isArtists }
        case .search:
            return !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !enabledFilters.isEmpty
        case .artists:
            return !MCArtistShelfQuery.names(from: artistText).isEmpty
        case .feed:
            return !pickedFeedTabs.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !editOnly && !model.feeds.isEmpty { shelfList }
                    editor
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            .mdSheet(editOnly ? "Edit shelf" : "Shelves", count: editOnly ? nil : model.feeds.count, onClose: { dismiss() },
                     secondary: editingID != nil && !editOnly ? MDSheetAction(title: "Cancel edit") { resetForm() } : nil,
                     primary: MDSheetAction(title: editingID == nil ? "Add shelf" : "Save shelf", disabled: !canSave) { save() })
            .sheet(isPresented: $showFilters) {
                FilterListSheetView(filters: searchFilters, search: $query, enabledFilters: $enabledFilters)
            }
            .task(id: "\(sourceKey)-\(kind.rawValue)") { await loadOptions() }
            .task(id: kind == .feed ? pickedFeedSources.joined(separator: ",") : "") { await loadFeedListings() }
        }
        .midokuAccent()
    }

    // MARK: Shelf list

    private var shelfList: some View {
        group("Your shelves") {
            VStack(spacing: 0) {
                ForEach(Array(model.feeds.enumerated()), id: \.element.id) { index, feed in
                    HStack(spacing: 10) {
                        Image(systemName: feed.isFeed ? "square.grid.3x3" : feed.isArtists ? "person.2" : feed.isSearch ? "magnifyingglass" : "rectangle.stack")
                            .font(.system(size: 15)).foregroundStyle(Color.mdText2)
                            .frame(width: 34, height: 34).background(Color.mdS3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feed.listingName).font(.mdSystem(size: 15, weight: .medium)).foregroundStyle(Color.mdText).lineLimit(1)
                            Text("\(feed.subtitle) · \(feed.isFeed ? "\(feed.columns) per row" : model.layout(of: feed).title)").font(.mdSystem(size: 12)).foregroundStyle(Color.mdText3).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        smallSquare("arrow.up", label: "Move up", disabled: index == 0) { model.move(feed, by: -1) }
                        smallSquare("arrow.down", label: "Move down", disabled: index == model.feeds.count - 1) { model.move(feed, by: 1) }
                        smallSquare("pencil", label: "Edit \(feed.listingName)", active: editingID == feed.id) { startEditing(feed) }
                        smallSquare("trash", label: "Remove \(feed.listingName)", destructive: true) {
                            if editingID == feed.id { resetForm() }
                            model.remove(feed)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(editingID == feed.id ? Color.mdAccentSoft : Color.mdS1)
                    .overlay(alignment: .top) { if index > 0 { Rectangle().fill(Color.mdLine).frame(height: 1) } }
                }
            }
            .overlay(Rectangle().strokeBorder(Color.mdLine, lineWidth: 1))
        }
    }

    private func smallSquare(_ image: String, label: String, disabled: Bool = false, active: Bool = false,
                             destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(destructive ? Color.mdAccent : active ? Color(uiColor: MDColor.onAccent) : Color.mdText2)
                .frame(width: 30, height: 30)
                .background(active ? Color.mdAccent : Color.mdS2)
                .overlay(Rectangle().strokeBorder(Color.mdLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(label)
    }

    // MARK: Editor

    @ViewBuilder private var editor: some View {
        if installed.isEmpty {
            MDEmpty(systemImage: "puzzlepiece.extension", title: "No extensions", detail: Text("Install an extension from Sources first."), compact: true)
        } else {
            VStack(alignment: .leading, spacing: 20) {
                if !editOnly {
                    Text(editingID == nil ? "Add a shelf" : "Edit shelf")
                        .font(.mdDisplay(19, weight: .bold)).foregroundStyle(Color.mdText)
                }
                group("Shelf type") {
                    MDSegmented(options: Kind.allCases, selection: $kind) { $0.rawValue }
                    Text(kindHelp)
                        .font(.mdSystem(size: 12)).foregroundStyle(Color.mdText3)
                }
                group(kind == .artists || kind == .feed ? "Extensions" : "Extension") {
                    MDFlow {
                        ForEach(installed, id: \.key) { source in
                            if kind == .feed {
                                chip(source.name, on: pickedFeedSources.contains(source.key)) { toggleFeedSource(source.key) }
                            } else if kind == .artists {
                                chip(source.name, on: pickedArtistSources.contains(source.key)) { toggleArtistSource(source.key) }
                            } else {
                                chip(source.name, on: sourceKey == source.key) {
                                    keepSelection = false
                                    sourceKey = source.key
                                }
                            }
                        }
                    }
                    if kind == .artists {
                        Text("Pick one or more. They're searched at the same time and the results are sorted by upload date.")
                            .font(.mdSystem(size: 12)).foregroundStyle(Color.mdText3)
                    } else if kind == .feed {
                        Text("Pick one or more, then the tabs to merge. Each tab's first page is combined and repeats are shown once.")
                            .font(.mdSystem(size: 12)).foregroundStyle(Color.mdText3)
                    }
                }
                if loading {
                    MDLoading(label: "Loading", shape: .rows, count: 1)
                } else if !sourceKey.isEmpty {
                    switch kind {
                    case .tab: tabFields
                    case .search: searchFields
                    case .artists: artistFields
                    case .feed: feedFields
                    }
                }
                if let error { Text(error).font(.mdSystem(size: 12)).foregroundStyle(Color.mdText3) }
                if !sourceKey.isEmpty {
                    group("Name") {
                        fieldBox {
                            TextField(kind == .tab ? "Tab name" : kind == .artists ? "Shelf name (optional, e.g. Artist updates)" : kind == .feed ? "Shelf name (optional, e.g. Latest)" : "Shelf name (optional)", text: $shelfName)
                                .font(.mdSystem(size: 15)).foregroundStyle(Color.mdText)
                        }
                    }
                    if kind == .feed {
                        group("Items per row") {
                            MDFlow {
                                ForEach(2...5, id: \.self) { count in
                                    chip("\(count)", on: feedColumns == count, systemImage: "square.grid.3x3") { feedColumns = count }
                                }
                            }
                            Text("Shows up to \(MCFeedShelfQuery.limit) titles, newest first when the extensions give upload dates.")
                                .font(.mdSystem(size: 12)).foregroundStyle(Color.mdText3)
                        }
                    } else {
                        group("Layout") {
                            MDFlow {
                                chip("Automatic", on: layout == nil) { layout = nil }
                                ForEach(MCShelfLayout.allCases, id: \.self) { option in
                                    chip(option.title, on: layout == option, systemImage: option.systemImage) { layout = option }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var tabFields: some View {
        if listings.isEmpty {
            Text("This extension does not provide discovery tabs. Try a search shelf.").font(.mdSystem(size: 13)).foregroundStyle(Color.mdText3)
        } else {
            group("Tab") {
                MDFlow {
                    ForEach(listings, id: \.id) { listing in
                        chip(listing.name, on: listingID == listing.id) {
                            if shelfName.isEmpty || listings.contains(where: { $0.name == shelfName }) { shelfName = listing.name }
                            listingID = listing.id
                        }
                    }
                }
            }
        }
    }

    /// The extensions an artist shelf searches; switching from another type keeps its extension.
    private var pickedArtistSources: [String] {
        artistSourceKeys.isEmpty && !sourceKey.isEmpty ? [sourceKey] : artistSourceKeys
    }

    private func toggleArtistSource(_ key: String) {
        var keys = pickedArtistSources
        if let index = keys.firstIndex(of: key) { keys.remove(at: index) } else { keys.append(key) }
        artistSourceKeys = keys
        keepSelection = true
        sourceKey = keys.first ?? ""
    }

    /// The extensions a feed shelf merges; switching from another type keeps its extension.
    private var pickedFeedSources: [String] {
        feedSourceKeys.isEmpty && !sourceKey.isEmpty ? [sourceKey] : feedSourceKeys
    }

    /// Picked tabs whose extension is still picked, in the order picked.
    private var pickedFeedTabs: [MCFeedTab] {
        let keys = Set(pickedFeedSources)
        return feedTabs.filter { keys.contains($0.sourceKey) }
    }

    private func toggleFeedSource(_ key: String) {
        var keys = pickedFeedSources
        if let index = keys.firstIndex(of: key) {
            keys.remove(at: index)
            feedTabs.removeAll { $0.sourceKey == key }
        } else {
            keys.append(key)
        }
        feedSourceKeys = keys
        keepSelection = true
        sourceKey = keys.first ?? ""
    }

    private func toggleFeedTab(_ tab: MCFeedTab) {
        if let index = feedTabs.firstIndex(where: { $0.sourceKey == tab.sourceKey && $0.listingID == tab.listingID }) {
            feedTabs.remove(at: index)
        } else {
            feedTabs.append(tab)
        }
    }

    @ViewBuilder private var feedFields: some View {
        ForEach(pickedFeedSources, id: \.self) { key in
            let name = sources.source(for: key)?.name ?? key
            let picked = pickedFeedTabs.filter { $0.sourceKey == key }.count
            group(picked > 0 ? "\(name) tabs · \(picked)" : "\(name) tabs") {
                if let listings = feedListings[key] {
                    if listings.isEmpty {
                        Text("This extension does not provide discovery tabs.").font(.mdSystem(size: 13)).foregroundStyle(Color.mdText3)
                    } else {
                        MDFlow {
                            ForEach(listings, id: \.id) { listing in
                                let tab = MCFeedTab(sourceKey: key, listingID: listing.id, listingName: listing.name)
                                chip(listing.name, on: feedTabs.contains { $0.sourceKey == key && $0.listingID == listing.id }) { toggleFeedTab(tab) }
                            }
                        }
                    }
                } else {
                    MDLoading(label: "Loading tabs", shape: .rows, count: 1)
                }
            }
        }
    }

    private func loadFeedListings() async {
        for key in pickedFeedSources where feedListings[key] == nil {
            guard let source = sources.source(for: key) else { continue }
            let loaded = (try? await MCSourceCallLimiter.shared.run { try await source.getListings() }) ?? []
            if Task.isCancelled { return }
            feedListings[key] = loaded
        }
    }

    private var kindHelp: String {
        switch kind {
        case .tab: "Shows a tab from the extension, like Popular or Latest."
        case .search: "Reruns your term and filters each time Home refreshes. Results you haven't seen before are marked New."
        case .artists: "The newest titles by these artists, refreshed like your other shelves. Titles you haven't seen before are marked New."
        case .feed: "Merges tabs from several extensions into one grid of the latest titles, sorted by upload date where possible. Titles you haven't seen before are marked New."
        }
    }

    @ViewBuilder private var artistFields: some View {
        let count = MCArtistShelfQuery.names(from: artistText).count
        group(count > 0 ? "Artists · \(count)" : "Artists") {
            fieldBox {
                Image(systemName: "person.2").font(.system(size: 14, weight: .medium)).foregroundStyle(Color.mdText3)
                TextField("Artist names, separated by |", text: $artistText)
                    .font(.mdSystem(size: 15)).foregroundStyle(Color.mdText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                if !artistText.isEmpty {
                    Button { artistText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color.mdText3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear artists")
                }
            }
            LibraryArtistChips(text: $artistText).padding(.horizontal, -16)
        }
    }

    @ViewBuilder private var searchFields: some View {
        group("Search") {
            fieldBox {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(Color.mdText3)
                TextField("Search term, e.g. several artists", text: $query)
                    .font(.mdSystem(size: 15)).foregroundStyle(Color.mdText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
            }
            if !searchFilters.isEmpty {
                HStack(spacing: 10) {
                    Button { showFilters = true } label: {
                        Label(enabledFilters.isEmpty ? "Filters" : "Filters · \(enabledFilters.count)", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MDGhostButtonStyle(small: false))
                    if !enabledFilters.isEmpty {
                        Button { enabledFilters = [] } label: { Text("Clear").frame(maxWidth: .infinity) }
                            .buttonStyle(MDGhostButtonStyle(small: false))
                    }
                }
            }
        }
    }

    private func fieldBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(Color.mdS1)
            .overlay(Rectangle().strokeBorder(Color.mdLine2, lineWidth: 1))
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).mdLabel()
            content()
        }
    }

    private func chip(_ title: String, on: Bool, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { MDChip(title: title, active: on, systemImage: systemImage, large: false) }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func save() {
        guard let source = sources.source(for: sourceKey) else { return }
        let trimmedName = shelfName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var feed: MCDiscoverFeed
        switch kind {
        case .tab:
            guard let listing = listings.first(where: { $0.id == listingID }) else { return }
            feed = MCDiscoverFeed(sourceKey: source.key, sourceName: source.name, listingID: listing.id,
                                  listingName: trimmedName.isEmpty ? listing.name : trimmedName)
        case .search:
            feed = MCDiscoverFeed(sourceKey: source.key, sourceName: source.name, listingID: "",
                                  listingName: trimmedName.isEmpty ? (trimmedQuery.isEmpty ? "Filtered search" : "“\(trimmedQuery)”") : trimmedName,
                                  query: trimmedQuery, filters: enabledFilters)
        case .artists:
            let picked = pickedArtistSources.compactMap { sources.source(for: $0) }
            guard let first = picked.first else { return }
            feed = MCDiscoverFeed(sourceKey: first.key, sourceName: picked.map(\.name).joined(separator: " + "), listingID: "",
                                  listingName: trimmedName.isEmpty ? "Artist updates" : trimmedName,
                                  artistNames: MCArtistShelfQuery.names(from: artistText),
                                  sourceKeys: picked.map(\.key))
        case .feed:
            let tabs = pickedFeedTabs
            guard let first = tabs.first else { return }
            var seen = Set<String>()
            let names = tabs.map(\.sourceKey).filter { seen.insert($0).inserted }.map { sources.source(for: $0)?.name ?? $0 }
            feed = MCDiscoverFeed(sourceKey: first.sourceKey, sourceName: names.joined(separator: " + "), listingID: "",
                                  listingName: trimmedName.isEmpty ? "Feed" : trimmedName,
                                  feedTabs: tabs, feedColumns: feedColumns)
        }
        feed.layout = layout
        if let editingID {
            feed.id = editingID
            model.update(feed)
        } else {
            model.append(feed)
        }
        if editOnly { dismiss() } else { resetForm() }
    }

    private func loadOptions() async {
        let keep = keepSelection
        listings = []; searchFilters = []; error = nil
        if !keep { listingID = "" }
        guard let source = sources.source(for: sourceKey) else { return }
        loading = true
        defer { loading = false }
        do {
            switch kind {
                case .tab:
                    let loaded = try await MCSourceCallLimiter.shared.run { try await source.getListings() }
                    try Task.checkCancellation()
                    listings = loaded
                    if !loaded.contains(where: { $0.id == listingID }) { listingID = loaded.first?.id ?? "" }
                case .search:
                    let loaded = try await MCSourceCallLimiter.shared.run { try await source.getSearchFilters() }
                    try Task.checkCancellation()
                    searchFilters = loaded
                    // Filters from another extension don't apply here.
                    let ids = Set(loaded.map(\.id))
                    enabledFilters.removeAll { !ids.contains($0.id) }
                case .artists, .feed:
                    break
            }
        } catch is CancellationError { }
        catch { self.error = error.midokuDescription() }
    }
}

/// One Home shelf in the layout picked for it, with the web options sheet behind its ⋯ button.
private struct MCDiscoverShelf: View {
    let feed: MCDiscoverFeed
    let index: Int
    @ObservedObject var model: MCDiscoverModel
    let openManga: (AidokuRunner.Manga) -> Void
    let openListing: (MCDiscoverFeed) -> Void
    @ObservedObject private var sources = SourceStore.shared
    @State private var showOptions = false
    @State private var editing = false

    private var layout: MCShelfLayout { model.layout(of: feed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header.padding(.horizontal, 16)
            content
        }
        .mdActionSheet(isPresented: $showOptions, title: feed.listingName) { optionRows() }
        .sheet(isPresented: $editing) {
            MCDiscoverConfiguration(model: model, editing: feed).presentationDetents([.large])
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Button { openListing(feed) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        if feed.isFeed || feed.isArtists || feed.isSearch {
                            Image(systemName: feed.isFeed ? "square.grid.3x3" : feed.isArtists ? "person.2" : "magnifyingglass").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.mdText3)
                        }
                        Text(feed.listingName).font(.mdDisplay(21, weight: .bold)).tracking(-0.3).foregroundStyle(Color.mdText).lineLimit(1)
                        if let count = model.newKeys[feed.id]?.count, count > 0 {
                            Text("\(count) new").font(.mdMono(11, weight: .semibold)).foregroundStyle(Color(uiColor: MDColor.onAccent))
                                .padding(.horizontal, 6).padding(.vertical, 2).background(Color.mdAccent)
                        }
                    }
                    Text(feed.subtitle).font(.mdSystem(size: 13)).foregroundStyle(Color.mdText3).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(feed.listingName) from \(feed.sourceName), see all")
            MDIconButton(systemImage: "ellipsis", label: "Shelf options") { showOptions = true }
        }
    }

    private func optionRows() -> [MDActionRow] {
        var rows: [MDActionRow] = []
        if let tabs = feed.feedTabs {
            for tab in tabs {
                let name = sources.source(for: tab.sourceKey)?.name ?? tab.sourceKey
                let single = MCDiscoverFeed(sourceKey: tab.sourceKey, sourceName: name, listingID: tab.listingID, listingName: tab.listingName)
                rows.append(MDActionRow(systemImage: "puzzlepiece.extension", title: "Open tab in \(name)", detail: tab.listingName) { openListing(single) })
            }
            rows += [
                MDActionRow(systemImage: "pencil", title: "Edit shelf", detail: "Name, tabs, extensions, items per row") { editing = true },
                MDActionRow(systemImage: "arrow.clockwise", title: "Refresh") { Task { await model.load(feed, force: true) } }
            ]
            for count in 2...5 {
                rows.append(MDActionRow(systemImage: feed.columns == count ? "checkmark" : "square.grid.3x3", title: "\(count) per row",
                                        detail: feed.columns == count ? "Current layout" : "Layout", keepsOpen: true) {
                    model.setColumns(count, for: feed)
                })
            }
            rows.append(MDActionRow(systemImage: "arrow.up", title: "Move up", disabled: index == 0) { model.move(feed, by: -1) })
            rows.append(MDActionRow(systemImage: "arrow.down", title: "Move down", disabled: index == model.feeds.count - 1) { model.move(feed, by: 1) })
            rows.append(MDActionRow(systemImage: "trash", title: "Remove shelf", destructive: true) { model.remove(feed) })
            return rows
        }
        if feed.isArtists {
            // One row per extension the shelf searches.
            for key in feed.allSourceKeys {
                let name = sources.source(for: key)?.name ?? key
                let single = MCDiscoverFeed(sourceKey: key, sourceName: name, listingID: "", listingName: feed.listingName,
                                            artistNames: feed.artistNames)
                rows.append(MDActionRow(systemImage: "puzzlepiece.extension", title: "Open search in \(name)", detail: "Same artists") { openListing(single) })
            }
        } else {
            rows.append(MDActionRow(systemImage: "puzzlepiece.extension", title: feed.isSearch ? "Open search in \(feed.sourceName)" : "Open tab in \(feed.sourceName)",
                                    detail: feed.isSearch ? "Same term and filters" : feed.listingName) { openListing(feed) })
        }
        rows += [
            MDActionRow(systemImage: "pencil", title: "Edit shelf",
                        detail: feed.isArtists ? "Name, artists, extensions" : feed.isSearch ? "Name, search term, filters, extension" : "Name, tab, extension") { editing = true },
            MDActionRow(systemImage: "arrow.clockwise", title: "Refresh") { Task { await model.load(feed, force: true) } }
        ]
        for option in MCShelfLayout.allCases {
            rows.append(MDActionRow(systemImage: layout == option ? "checkmark" : option.systemImage, title: option.title,
                                    detail: layout == option ? "Current layout" : "Layout", keepsOpen: true) {
                model.setLayout(option, for: feed)
            })
        }
        rows.append(MDActionRow(systemImage: "arrow.up", title: "Move up", disabled: index == 0) { model.move(feed, by: -1) })
        rows.append(MDActionRow(systemImage: "arrow.down", title: "Move down", disabled: index == model.feeds.count - 1) { model.move(feed, by: 1) })
        rows.append(MDActionRow(systemImage: "trash", title: "Remove shelf", destructive: true) { model.remove(feed) })
        return rows
    }

    @ViewBuilder private var content: some View {
        if let items = model.entries[feed.id], !items.isEmpty {
            let fresh = model.newKeys[feed.id] ?? []
            if feed.isFeed {
                feedGrid(items, fresh: fresh)
            } else {
                switch layout {
                case .hero:
                    MCDiscoverHero(items: Array(items.prefix(10)), label: feed.listingName, newKeys: fresh,
                                   source: { sources.source(for: $0.sourceKey) }, open: openManga)
                case .rail:
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(items.prefix(30), id: \.key) { manga in
                                Button { openManga(manga) } label: { railCard(manga, isNew: fresh.contains(manga.key)) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, 16)
                    }
                    .scrollTargetBehavior(.viewAligned)
                case .grid:
                    // Two rows of small covers that scroll sideways together.
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHGrid(rows: [GridItem(.fixed(150), spacing: 14, alignment: .top), GridItem(.fixed(150), alignment: .top)], spacing: 10) {
                            ForEach(items.prefix(40), id: \.key) { manga in
                                Button { openManga(manga) } label: { gridCard(manga, isNew: fresh.contains(manga.key)) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, 16)
                    }
                    .scrollTargetBehavior(.viewAligned)
                }
            }
        } else if let error = model.errors[feed.id] {
            MDEmpty(systemImage: "exclamationmark.triangle", title: "Couldn’t load \(feed.listingName)",
                    detail: Text(String(error.prefix(140))),
                    action: MDStateAction(label: "Try again") { Task { await model.load(feed, force: true) } },
                    tone: .error, compact: true)
                .padding(.horizontal, 16)
        } else if model.loading.contains(feed.id) || model.entries[feed.id] == nil {
            MDLoading(label: "Loading", shape: feed.isFeed ? .grid : layout == .hero ? .rows : .rail,
                      count: feed.isFeed ? 6 : layout == .hero ? 1 : 4)
                .padding(.horizontal, 16)
        } else {
            MDEmpty(systemImage: "info.circle", title: "Nothing here yet", compact: true).padding(.horizontal, 16)
        }
    }

    /// Feed shelves: a vertical grid of up to 100 covers, with each title's extension and age.
    private func feedGrid(_ items: [AidokuRunner.Manga], fresh: Set<String>) -> some View {
        let count = feed.columns
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: count)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(items.prefix(MCFeedShelfQuery.limit), id: \.feedID) { manga in
                Button { openManga(manga) } label: { feedCard(manga, isNew: fresh.contains(manga.key), columns: count) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private func feedCard(_ manga: AidokuRunner.Manga, isNew: Bool, columns: Int) -> some View {
        let sourceName = sources.source(for: manga.sourceKey)?.name
        let age = MCFeedShelfQuery.uploadTime(manga).map {
            Date(timeIntervalSince1970: $0).formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        }
        let meta = [columns <= 3 ? sourceName : nil, age].compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay { cover(manga) }
                .clipped()
                .overlay(alignment: .topLeading) { if isNew { MCDiscoverNewBadge().padding(4) } }
            Text(manga.title)
                .font(.mdSystem(size: columns <= 2 ? 14 : columns == 3 ? 12 : 11, weight: .semibold))
                .foregroundStyle(Color.mdText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !meta.isEmpty {
                Text(meta).font(.mdSystem(size: columns <= 3 ? 11 : 10)).foregroundStyle(Color.mdText3).lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([isNew ? "New: \(manga.title)" : manga.title, sourceName, age].compactMap { $0 }.joined(separator: ", "))
    }

    private func railCard(_ manga: AidokuRunner.Manga, isNew: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            cover(manga).frame(width: 118, height: 177)
                .overlay(alignment: .topLeading) { if isNew { MCDiscoverNewBadge().padding(6) } }
            Text(manga.title).font(.mdSystem(size: 13, weight: .semibold)).foregroundStyle(Color.mdText)
                .lineLimit(2).frame(width: 118, alignment: .leading)
        }
        .frame(width: 118)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isNew ? "New: \(manga.title)" : manga.title)
    }

    private func gridCard(_ manga: AidokuRunner.Manga, isNew: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            cover(manga).frame(width: 82, height: 123)
                .overlay(alignment: .topLeading) { if isNew { MCDiscoverNewBadge().padding(4) } }
            Text(manga.title).font(.mdSystem(size: 11, weight: .semibold)).foregroundStyle(Color.mdText)
                .lineLimit(1).frame(width: 82, alignment: .leading)
        }
        .frame(width: 82)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isNew ? "New: \(manga.title)" : manga.title)
    }

    private func cover(_ manga: AidokuRunner.Manga) -> some View {
        GeometryReader { geometry in
            SourceImageView(source: sources.source(for: manga.sourceKey), imageUrl: manga.cover ?? "",
                            width: geometry.size.width, height: geometry.size.height,
                            placeholder: "MidokuCoverPlaceholder", placeholderTitle: manga.title)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
    }
}

private extension AidokuRunner.Manga {
    /// Unique across extensions, for lists that mix several.
    var feedID: String { "\(sourceKey)|\(key)" }
}

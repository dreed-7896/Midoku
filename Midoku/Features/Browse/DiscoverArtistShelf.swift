import AidokuRunner
import SwiftUI

// MARK: - Data

/// One title found for a followed artist, with the date of its newest chapter.
struct MCArtistRelease: Codable, Identifiable, Hashable, Sendable {
    let sourceKey: String
    let key: String
    var title: String
    var cover: String?
    var authors: [String]
    var artists: [String]
    /// Upload date of the newest chapter, when the extension reports one.
    var date: Date?
    var chapterLabel: String?
    /// Followed artists this title was found for.
    var matched: [String]
    var checked: Date

    var id: String { "\(sourceKey)|\(key)" }
    var manga: AidokuRunner.Manga {
        AidokuRunner.Manga(sourceKey: sourceKey, key: key, title: title, cover: cover,
                           artists: artists.isEmpty ? nil : artists, authors: authors.isEmpty ? nil : authors)
    }
    /// Identifies this release, so a new chapter of a known title still counts as new.
    var seenToken: String { "\(id)@\(Int(date?.timeIntervalSince1970 ?? 0))" }
}

struct MCLibraryArtist: Sendable, Hashable {
    let name: String
    var count: Int
}

struct MCArtistProgress: Equatable {
    var done: Int
    var total: Int
}

enum MCArtistShelf {
    static let shelfLimit = 15
    static let resultLimit = 200
    /// Results kept from each artist search in each extension.
    static let candidatesPerSearch = 40
    /// Saved results are shown without searching again for this long.
    static let cacheLifetime: TimeInterval = 4 * 60 * 60
    /// A search that takes longer is skipped, so one stuck extension can't hold up the shelf.
    static let searchTimeout: Double = 20
    /// Searches running at once. Each blocks a shared worker thread until its network call returns,
    /// so this stays below the thread count to leave room for the network work itself.
    static let concurrency = 4

    // MARK: Name matching

    static func normalize(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Lenient match that also accepts reversed name order ("Oda Eiichiro" / "Eiichiro Oda").
    static func matches(_ candidate: String, _ artist: String) -> Bool {
        let lhs = normalize(candidate), rhs = normalize(artist)
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        if lhs == rhs { return true }
        if min(lhs.count, rhs.count) >= 4, lhs.contains(rhs) || rhs.contains(lhs) { return true }
        return lhs.split(separator: " ").sorted() == rhs.split(separator: " ").sorted()
    }

    static func matching(_ names: [String], artists: [String]) -> [String] {
        artists.filter { artist in names.contains { matches($0, artist) } }
    }

    // MARK: Search plan

    struct Plan: Sendable {
        var textFilterID: String?
        var sort: SortFilterValue?
    }

    /// Uses an extension's artist/author field and a "latest" sort when it offers them.
    static func plan(for filters: [AidokuRunner.Filter]) -> Plan {
        var plan = Plan()
        var authorFilter: String?
        for filter in filters {
            let label = "\(filter.id) \(filter.title ?? "")".lowercased()
            switch filter.value {
                case .text:
                    if label.contains("artist") || label.contains("illustrat") {
                        plan.textFilterID = plan.textFilterID ?? filter.id
                    } else if label.contains("author") || label.contains("creator") {
                        authorFilter = authorFilter ?? filter.id
                    }
                case let .sort(_, options, _):
                    guard plan.sort == nil else { continue }
                    let keywords = ["latest", "updated", "update", "recent", "newest", "last"]
                    if let index = options.firstIndex(where: { option in keywords.contains { option.lowercased().contains($0) } }) {
                        plan.sort = SortFilterValue(id: filter.id, index: index, ascending: false)
                    }
                default: break
            }
        }
        plan.textFilterID = plan.textFilterID ?? authorFilter
        return plan
    }

    struct SearchResult: Sendable {
        let sourceKey: String
        let artist: String
        let entries: [AidokuRunner.Manga]
        /// The extension filtered by artist itself, so names need no further check.
        let trusted: Bool
        let failed: Bool
    }

    static func search(source: AidokuRunner.Source, artist: String, plan: Plan) async -> SearchResult {
        var filters: [FilterValue] = []
        var query: String? = artist
        if let id = plan.textFilterID { filters.append(.text(id: id, value: artist)); query = nil }
        if let sort = plan.sort { filters.append(.sort(sort)) }
        if !filters.isEmpty, let entries = try? await source.getSearchMangaList(query: query, page: 1, filters: filters).entries, !entries.isEmpty {
            return .init(sourceKey: source.key, artist: artist, entries: entries, trusted: plan.textFilterID != nil, failed: false)
        }
        do {
            let entries = try await source.getSearchMangaList(query: artist, page: 1, filters: []).entries
            return .init(sourceKey: source.key, artist: artist, entries: entries, trusted: false, failed: false)
        } catch {
            return .init(sourceKey: source.key, artist: artist, entries: [], trusted: false, failed: true)
        }
    }

    /// Returns nil when `operation` outlasts `seconds`. The operation is left to finish on its own,
    /// since an extension blocked on the network may not respond to cancellation.
    static func withTimeout<T: Sendable>(_ seconds: Double, _ operation: @escaping @Sendable () async -> T) async -> T? {
        let gate = MCTimeoutGate<T>()
        return await withCheckedContinuation { continuation in
            gate.install(continuation)
            Task { gate.resume(await operation()) }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                gate.resume(nil)
            }
        }
    }

    // MARK: Storage

    private static var directory: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MidokuArtistShelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private static func resultsURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    static func loadResults(_ id: UUID) -> (results: [MCArtistRelease], saved: Date)? {
        let url = resultsURL(id)
        guard let data = try? Data(contentsOf: url), let results = try? JSONDecoder().decode([MCArtistRelease].self, from: data) else { return nil }
        let saved = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return (results, saved)
    }
    static func saveResults(_ results: [MCArtistRelease], for id: UUID) {
        try? JSONEncoder().encode(results).write(to: resultsURL(id), options: .atomic)
    }
    static func removeResults(_ id: UUID) { try? FileManager.default.removeItem(at: resultsURL(id)) }

    /// Artists credited in the personal collection, most frequent first. Edits win over source
    /// credits, and a cleared credit stays cleared. Authors stand in only when an entry has no artist.
    @MainActor static func libraryArtists() -> [MCLibraryArtist] {
        let library = MCCollectionStore.shared.library
        func names(_ override: String?, _ source: [String]?) -> [String] {
            let raw = override.map { [$0] } ?? source ?? []
            return raw.flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",;")) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        var counts: [String: MCLibraryArtist] = [:]
        for entry in library.rootEntries {
            let details = library.listing(entry.primaryListingID)?.details
            var credited = names(entry.artistOverride, details?.artists)
            if credited.isEmpty { credited = names(entry.authorOverride, details?.authors) }
            var seen = Set<String>()
            for name in credited {
                let key = normalize(name)
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                counts[key, default: MCLibraryArtist(name: name, count: 0)].count += 1
            }
        }
        return counts.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: min(date, Date()), relativeTo: Date())
    }
}

/// Resumes a continuation once, from whichever finishes first: the work or its timeout.
final class MCTimeoutGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?
    private var finished = false
    private var early: T?
    private var hasEarly = false

    func install(_ continuation: CheckedContinuation<T?, Never>) {
        lock.lock()
        if hasEarly {
            let value = early
            lock.unlock()
            continuation.resume(returning: value)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func resume(_ value: T?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: value)
        } else {
            early = value; hasEarly = true
            lock.unlock()
        }
    }
}

// MARK: - Loading

extension MCDiscoverModel {
    func saveArtistShelf(artists: [String], sourceKeys: [String], name: String) {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let listingName = title.isEmpty ? "New from your artists" : title
        if let index = feeds.firstIndex(where: \.isArtists) {
            feeds[index].artists = artists
            feeds[index].sourceKeys = sourceKeys
            feeds[index].listingName = listingName
            artistRefreshed.remove(feeds[index].id)
        } else {
            // The artist shelf leads Discover.
            feeds.insert(.init(sourceKey: "", sourceName: "", listingID: "", listingName: listingName,
                               artists: artists, sourceKeys: sourceKeys), at: 0)
        }
        save()
    }

    func loadArtists(_ feed: MCDiscoverFeed, force: Bool) async {
        guard !loading.contains(feed.id), force || !artistRefreshed.contains(feed.id) else { return }
        if releases[feed.id] == nil, let cached = MCArtistShelf.loadResults(feed.id) {
            releases[feed.id] = cached.results
            artistUpdated[feed.id] = cached.saved
        }
        // Saved results stay for four hours unless the shelf is refreshed.
        if !force, let updated = artistUpdated[feed.id], Date().timeIntervalSince(updated) < MCArtistShelf.cacheLifetime {
            artistRefreshed.insert(feed.id)
            return
        }
        guard SourceStore.shared.hasLoaded else { return }
        let names = feed.artists ?? []
        let sources = (feed.sourceKeys ?? []).compactMap { key -> AidokuRunner.Source? in
            SourceStore.shared.isDisabled(sourceKey: key) ? nil : SourceStore.shared.source(for: key)
        }
        guard !names.isEmpty else { errors[feed.id] = "Choose at least one artist for this shelf."; return }
        guard !sources.isEmpty else { errors[feed.id] = "None of this shelf's extensions are available. Edit the shelf to choose others."; return }

        loading.insert(feed.id); errors[feed.id] = nil; artistSkipped[feed.id] = nil
        artistRefreshed.insert(feed.id)
        defer { loading.remove(feed.id); artistProgress[feed.id] = nil }

        struct Pair: Sendable { let source: AidokuRunner.Source; let artist: String }
        struct Outcome: Sendable { let pair: Pair; let result: MCArtistShelf.SearchResult? }
        struct Found { let pair: Pair; let entries: [AidokuRunner.Manga] }
        // Artist by artist, so searches running together go to different extensions.
        let pairs = names.flatMap { artist in sources.map { Pair(source: $0, artist: artist) } }
        let sourceRank = Dictionary(sources.enumerated().map { ($0.element.key, $0.offset) }, uniquingKeysWith: { lhs, _ in lhs })
        let artistRank = Dictionary(names.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { lhs, _ in lhs })
        var lists: [Found] = []
        var skipped = Set<String>(), failures = 0, done = 0
        var plans: [String: Task<MCArtistShelf.Plan, Never>] = [:]
        for source in sources {
            plans[source.key] = Task {
                let filters = (try? await source.getSearchFilters()) ?? []
                return MCArtistShelf.plan(for: filters)
            }
        }
        let planTasks = plans

        func publish() {
            // Interleave by position: each extension's first results, then the second ones, and so on.
            // Extensions sort newest first where they can, so this keeps the newest near the top.
            struct Ranked { let rank: Int; let manga: AidokuRunner.Manga; let pair: Pair }
            let ordered = lists.flatMap { list in list.entries.enumerated().map { Ranked(rank: $0.offset, manga: $0.element, pair: list.pair) } }
                .sorted { lhs, rhs in
                    if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                    let lhsSource = sourceRank[lhs.pair.source.key] ?? 0, rhsSource = sourceRank[rhs.pair.source.key] ?? 0
                    if lhsSource != rhsSource { return lhsSource < rhsSource }
                    return (artistRank[lhs.pair.artist] ?? 0) < (artistRank[rhs.pair.artist] ?? 0)
                }
            var byTitle: [String: Int] = [:], byKey: [String: Int] = [:]
            var results: [MCArtistRelease] = []
            for item in ordered {
                let manga = item.manga, artist = item.pair.artist
                let id = "\(item.pair.source.key)|\(manga.key)"
                let title = MCArtistShelf.normalize(manga.title)
                // The same title from several extensions or artists shows once, from the first extension in the order.
                if let index = byKey[id] ?? (title.isEmpty ? nil : byTitle[title]) {
                    if !results[index].matched.contains(artist) { results[index].matched.append(artist) }
                    continue
                }
                guard results.count < MCArtistShelf.resultLimit else { continue }
                byKey[id] = results.count
                if !title.isEmpty { byTitle[title] = results.count }
                results.append(MCArtistRelease(
                    sourceKey: item.pair.source.key, key: manga.key, title: manga.title, cover: manga.cover,
                    authors: manga.authors ?? [], artists: manga.artists ?? [], date: nil, chapterLabel: nil,
                    matched: [artist], checked: Date()
                ))
            }
            releases[feed.id] = results
        }

        artistProgress[feed.id] = .init(done: 0, total: pairs.count)
        await forEachLimited(pairs, limit: MCArtistShelf.concurrency, work: { pair in
            let result = await MCArtistShelf.withTimeout(MCArtistShelf.searchTimeout) {
                let plan = await planTasks[pair.source.key]?.value ?? MCArtistShelf.Plan()
                return await MCArtistShelf.search(source: pair.source, artist: pair.artist, plan: plan)
            }
            return Outcome(pair: pair, result: result)
        }, handle: { outcome in
            done += 1
            artistProgress[feed.id] = .init(done: done, total: pairs.count)
            guard let result = outcome.result else { skipped.insert(outcome.pair.source.name); failures += 1; return }
            if result.failed { failures += 1; return }
            var unique = Set<String>()
            let entries = result.entries.filter { manga in
                guard unique.insert(manga.key).inserted else { return false }
                if result.trusted { return true }
                let credited = (manga.artists ?? []) + (manga.authors ?? [])
                return credited.isEmpty || credited.contains { MCArtistShelf.matches($0, result.artist) }
            }
            lists.append(Found(pair: outcome.pair, entries: Array(entries.prefix(MCArtistShelf.candidatesPerSearch))))
            publish()
        })
        guard !Task.isCancelled else { return }
        artistSkipped[feed.id] = skipped.isEmpty ? nil : skipped.sorted()
        if failures == pairs.count {
            errors[feed.id] = skipped.isEmpty
                ? "Searches failed in every extension. Check your connection and try again."
                : "No extension responded in time. Try again, or remove slow extensions from this shelf."
            return
        }
        publish()
        let results = releases[feed.id] ?? []
        MCArtistShelf.saveResults(results, for: feed.id)
        artistUpdated[feed.id] = Date()
        newKeys[feed.id] = recordSeenTokens(feed, tokens: results.map(\.id))
    }

    /// Runs `work` over `items` with at most `limit` running at once; `handle` sees each result on the main actor.
    private func forEachLimited<T: Sendable, R: Sendable>(
        _ items: [T], limit: Int, work: @escaping @Sendable (T) async -> R, handle: (R) -> Void
    ) async {
        await withTaskGroup(of: R.self) { group in
            var iterator = items.makeIterator()
            for _ in 0..<limit {
                guard let next = iterator.next() else { break }
                group.addTask { await work(next) }
            }
            while let result = await group.next() {
                handle(result)
                if Task.isCancelled { group.cancelAll(); continue }
                if let next = iterator.next() { group.addTask { await work(next) } }
            }
        }
    }
}

// MARK: - Shelf

/// The artist shelf: three rows of recent releases that page sideways, filterable by artist.
struct MCArtistShelfView: View {
    let feed: MCDiscoverFeed
    let index: Int
    @ObservedObject var model: MCDiscoverModel
    var openManga: (AidokuRunner.Manga) -> Void
    var openAll: () -> Void
    var edit: () -> Void
    @State private var artist: String?

    private var all: [MCArtistRelease] { model.releases[feed.id] ?? [] }
    private var visible: [MCArtistRelease] {
        let filtered = artist.map { name in all.filter { $0.matched.contains(name) } } ?? all
        return Array(filtered.prefix(MCArtistShelf.shelfLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header.padding(.horizontal)
            if (feed.artists ?? []).count > 1 {
                MCArtistChips(artists: feed.artists ?? [], selection: $artist)
            }
            content
            if let skipped = model.artistSkipped[feed.id] {
                Label("No response from \(skipped.joined(separator: ", ")); skipped.", systemImage: "clock.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }
        }
    }

    private var subtitle: String {
        if let progress = model.artistProgress[feed.id] {
            return "Searching \(progress.done) of \(progress.total)…"
        }
        if let updated = model.artistUpdated[feed.id] {
            return "\(feed.subtitle) · \(MCArtistShelf.relativeDate(updated))"
        }
        return feed.subtitle
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: openAll) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Image(systemName: "paintbrush.pointed.fill").font(.subheadline.weight(.bold)).foregroundStyle(Color.accentColor)
                            Text(feed.listingName).font(.title2.bold()).foregroundStyle(.primary).lineLimit(1)
                            if let count = model.newKeys[feed.id]?.count, count > 0 {
                                Text("\(count) new").font(.caption.bold()).foregroundStyle(.white)
                                    .padding(.horizontal, 7).padding(.vertical, 2).background(Color.accentColor, in: Capsule())
                            }
                        }
                        HStack(spacing: 6) {
                            if model.artistProgress[feed.id] != nil { ProgressView().controlSize(.mini) }
                            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
                        }
                    }
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(feed.listingName), see all")
            Spacer()
            Menu {
                Button("See all", systemImage: "list.bullet") { openAll() }
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.load(feed, force: true) } }
                Button("Edit artists", systemImage: "pencil") { edit() }
                Divider()
                Button("Move up", systemImage: "arrow.up") { model.move(feed, by: -1) }.disabled(index == 0)
                Button("Move down", systemImage: "arrow.down") { model.move(feed, by: 1) }.disabled(index == model.feeds.count - 1)
                Button("Remove shelf", systemImage: "trash", role: .destructive) { model.remove(feed) }
            } label: {
                Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(width: 36, height: 36).background(Color(uiColor: .secondarySystemBackground), in: Circle())
            }
            .accessibilityLabel("Shelf options")
        }
    }

    @ViewBuilder private var content: some View {
        let items = visible
        if !items.isEmpty {
            let fresh = model.newKeys[feed.id] ?? []
            let rows = Array(repeating: GridItem(.fixed(MCArtistReleaseRow.height), spacing: 12), count: min(3, items.count))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: rows, spacing: 16) {
                    ForEach(items) { release in
                        Button { openManga(release.manga) } label: {
                            MCArtistReleaseRow(release: release, isNew: fresh.contains(release.id))
                        }
                        .buttonStyle(.plain)
                        .containerRelativeFrame(.horizontal) { width, _ in width * 0.86 }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        } else if let error = model.errors[feed.id] {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        Button("Try again") { Task { await model.load(feed, force: true) } }
                        Button("Edit shelf", action: edit)
                    }.font(.subheadline.weight(.semibold))
                }
                Spacer(minLength: 0)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        } else if model.loading.contains(feed.id) || model.releases[feed.id] == nil {
            VStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in MCArtistReleaseRow.placeholder }
            }
            .padding(.horizontal)
            .accessibilityLabel("Loading")
        } else {
            Text(artist == nil ? "No releases found for these artists in the chosen extensions." : "No releases found for \(artist ?? "").")
                .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal)
        }
    }
}

struct MCArtistChips: View {
    let artists: [String]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: selection == nil) { selection = nil }
                ForEach(artists, id: \.self) { name in
                    chip(name, selected: selection == name) { selection = selection == name ? nil : name }
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.accentColor : Color(uiColor: .secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct MCArtistReleaseRow: View {
    static let height: CGFloat = 96
    let release: MCArtistRelease
    let isNew: Bool
    @ObservedObject private var sources = SourceStore.shared

    var body: some View {
        HStack(spacing: 12) {
            SourceImageView(source: sources.source(for: release.sourceKey), imageUrl: release.cover ?? "", width: 64, height: 96,
                            placeholder: "MidokuCoverPlaceholder")
                .frame(width: 64, height: 96).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                .overlay(alignment: .topLeading) { if isNew { MCArtistNewBadge().padding(4) } }
            VStack(alignment: .leading, spacing: 4) {
                Text(release.title).font(.subheadline.weight(.semibold)).lineLimit(3).foregroundStyle(.primary)
                Text(release.matched.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(sources.source(for: release.sourceKey)?.name ?? "").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: Self.height)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([isNew ? "New" : nil, release.title, release.matched.joined(separator: ", ")].compactMap { $0 }.joined(separator: ", "))
    }

    static var placeholder: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .secondarySystemBackground)).frame(width: 64, height: 96)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(Color(uiColor: .secondarySystemBackground)).frame(width: 180, height: 14)
                RoundedRectangle(cornerRadius: 4).fill(Color(uiColor: .secondarySystemBackground)).frame(width: 110, height: 10)
            }
            Spacer()
        }
        .frame(height: height)
    }
}

private struct MCArtistNewBadge: View {
    var body: some View {
        Text("NEW").font(.caption2.weight(.heavy)).foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color.accentColor, in: Capsule())
    }
}

// MARK: - See all

/// Every result the artist shelf found, up to 200, newest first, as a cover grid like the library.
struct MCArtistReleasesView: View {
    let feedID: UUID
    @ObservedObject var model: MCDiscoverModel
    var openManga: (AidokuRunner.Manga) -> Void = { _ in }
    @State private var artist: String?
    @State private var columns = HomeGridView.getColumns()
    @ObservedObject private var sources = SourceStore.shared

    private var feed: MCDiscoverFeed? { model.feeds.first { $0.id == feedID } }

    private var items: [MCArtistRelease] {
        let all = model.releases[feedID] ?? []
        return artist.map { name in all.filter { $0.matched.contains(name) } } ?? all
    }

    var body: some View {
        let fresh = model.newKeys[feedID] ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let artists = feed?.artists, artists.count > 1 {
                    MCArtistChips(artists: artists, selection: $artist)
                }
                if let progress = model.artistProgress[feedID] {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Searching \(progress.done) of \(progress.total)…")
                            .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .padding(.horizontal)
                }
                LazyVGrid(columns: columns, spacing: HomeGridView.spacing) {
                    ForEach(items) { release in
                        Button { openManga(release.manga) } label: {
                            MangaGridItem(source: sources.source(for: release.sourceKey), title: release.title, coverImage: release.cover ?? "")
                                .overlay(alignment: .topLeading) {
                                    if fresh.contains(release.id) { MCArtistNewBadge().padding(6) }
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel([fresh.contains(release.id) ? "New" : nil, release.title,
                                                     release.matched.joined(separator: ", ")].compactMap { $0 }.joined(separator: ", "))
                        }
                        .buttonStyle(MangaGridButtonStyle())
                    }
                }
                .padding([.horizontal, .bottom])
            }
            .padding(.top, 4)
        }
        .overlay {
            if (model.releases[feedID] ?? []).isEmpty, model.artistProgress[feedID] == nil {
                ContentUnavailableView("No releases yet", systemImage: "paintbrush.pointed",
                                       description: Text(model.errors[feedID] ?? "Pull to refresh to search your artists again."))
            }
        }
        .refreshable { if let feed { await model.load(feed, force: true) } }
        .onReceive(NotificationCenter.default.publisher(for: .orientationDidChange)) { _ in
            columns = HomeGridView.getColumns()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init(AppSettings.appearance.layout.key))) { _ in
            columns = HomeGridView.getColumns()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    if let feed { Task { await model.load(feed, force: true) } }
                }
                .disabled(model.loading.contains(feedID))
            }
        }
        .navigationTitle(feed?.listingName ?? "Artists")
        .navigationBarTitleDisplayMode(.large)
        .midokuAccent()
    }
}

// MARK: - Configuration

/// Picks artists from library credits or by typing names.
struct MCArtistPicker: View {
    @Binding var selected: [String]
    @State private var library: [MCLibraryArtist] = []
    @State private var loaded = false
    @State private var manual = ""
    @State private var filter = ""

    private var filteredLibrary: [MCLibraryArtist] {
        let query = MCArtistShelf.normalize(filter)
        guard !query.isEmpty else { return library }
        return library.filter { MCArtistShelf.normalize($0.name).contains(query) }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Artist name", text: $manual)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(addManual)
                    Button("Add", action: addManual)
                        .disabled(manual.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: { Text("Enter manually") } footer: { Text("Use the name as the extensions spell it.") }

            if !selected.isEmpty {
                Section("Selected (\(selected.count))") {
                    ForEach(selected, id: \.self) { name in
                        Text(name)
                    }
                    .onDelete { selected.remove(atOffsets: $0) }
                    .onMove { selected.move(fromOffsets: $0, toOffset: $1) }
                }
            }

            Section {
                if !loaded {
                    ProgressView()
                } else if library.isEmpty {
                    Text("No artist credits in your library yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(filteredLibrary, id: \.name) { entry in
                        let isOn = contains(entry.name)
                        Button {
                            toggle(entry.name)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name).foregroundStyle(.primary)
                                    Text("\(entry.count) title\(entry.count == 1 ? "" : "s") in library").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                                    .font(.title3)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: { Text("From your library") }
        }
        .searchable(text: $filter, prompt: "Filter library artists")
        .navigationTitle("Artists")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if !selected.isEmpty { EditButton() } }
        .task {
            guard !loaded else { return }
            library = MCArtistShelf.libraryArtists()
            loaded = true
        }
    }

    private func contains(_ name: String) -> Bool {
        let key = MCArtistShelf.normalize(name)
        return selected.contains { MCArtistShelf.normalize($0) == key }
    }
    private func toggle(_ name: String) {
        let key = MCArtistShelf.normalize(name)
        if contains(name) { selected.removeAll { MCArtistShelf.normalize($0) == key } } else { selected.append(name) }
    }
    private func addManual() {
        let name = manual.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if !contains(name) { selected.append(name) }
        manual = ""
    }
}

/// Picks the extensions an artist shelf searches, in order. The order decides which extension's
/// copy shows when several have the same title, and which results come first.
struct MCSourceMultiPicker: View {
    @Binding var selected: [String]
    @ObservedObject private var sources = SourceStore.shared

    private var installed: [AidokuRunner.Source] {
        sources.sourcesByKey.values.filter { !sources.isDisabled(sourceKey: $0.key) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let available = installed.filter { !selected.contains($0.key) }
        List {
            Section {
                if selected.isEmpty {
                    Text("Add extensions below.").foregroundStyle(.secondary)
                }
                ForEach(selected, id: \.self) { key in
                    row(key: key, name: sources.source(for: key)?.name ?? key, imageUrl: sources.source(for: key)?.imageUrl)
                }
                .onMove { selected.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { selected.remove(atOffsets: $0) }
            } header: { Text("Search order") } footer: {
                Text("Drag to reorder. When several extensions have the same title, the one higher in this list is shown.")
            }
            if !available.isEmpty {
                Section("Add extensions") {
                    ForEach(available, id: \.key) { source in
                        Button {
                            selected.append(source.key)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill").foregroundStyle(.green).font(.title3)
                                SourceIconView(sourceId: source.key, imageUrl: source.imageUrl, iconSize: 32)
                                Text(source.name).foregroundStyle(.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Extensions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button(available.isEmpty ? "Clear" : "Add all") {
                if available.isEmpty { selected = [] } else { selected.append(contentsOf: available.map(\.key)) }
            }
        }
    }

    private func row(key: String, name: String, imageUrl: URL?) -> some View {
        HStack(spacing: 12) {
            SourceIconView(sourceId: key, imageUrl: imageUrl, iconSize: 32)
            Text(name)
        }
    }
}

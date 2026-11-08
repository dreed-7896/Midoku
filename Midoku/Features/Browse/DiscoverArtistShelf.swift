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
    var searching: Bool
}

enum MCArtistShelf {
    static let shelfLimit = 15
    static let resultLimit = 200
    /// Search results checked per artist per extension.
    static let candidatesPerSearch = 20
    /// Chapter lists newer than this are reused instead of being fetched again.
    static let detailLifetime: TimeInterval = 6 * 60 * 60

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

    static func chapterLabel(_ chapter: AidokuRunner.Chapter) -> String? {
        if let number = chapter.chapterNumber {
            let text = number.rounded() == number ? String(Int(number)) : String(number)
            return "Ch. \(text)"
        }
        if let title = chapter.title, !title.isEmpty { return title }
        if let volume = chapter.volumeNumber { return "Vol. \(volume.rounded() == volume ? String(Int(volume)) : String(volume))" }
        return nil
    }

    /// Fetches details and chapters, then records the newest chapter.
    static func details(source: AidokuRunner.Source, manga: AidokuRunner.Manga) async -> MCArtistRelease? {
        guard let updated = try? await source.getMangaUpdate(manga: manga, needsDetails: true, needsChapters: true) else { return nil }
        let newest = (updated.chapters ?? []).filter { $0.dateUploaded != nil }.max { ($0.dateUploaded ?? .distantPast) < ($1.dateUploaded ?? .distantPast) }
        return MCArtistRelease(
            sourceKey: source.key, key: manga.key,
            title: updated.title.isEmpty ? manga.title : updated.title,
            cover: updated.cover ?? manga.cover,
            authors: updated.authors ?? manga.authors ?? [],
            artists: updated.artists ?? manga.artists ?? [],
            date: newest?.dateUploaded,
            chapterLabel: (newest ?? updated.chapters?.first).flatMap(chapterLabel),
            matched: [], checked: Date()
        )
    }

    // MARK: Storage

    private static var directory: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MidokuArtistShelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private static var detailsURL: URL { directory.appendingPathComponent("details.json") }
    private static func resultsURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    static func loadDetails() -> [String: MCArtistRelease] {
        guard let data = try? Data(contentsOf: detailsURL) else { return [:] }
        return (try? JSONDecoder().decode([String: MCArtistRelease].self, from: data)) ?? [:]
    }
    static func saveDetails(_ details: [String: MCArtistRelease]) {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let kept = details.filter { $0.value.checked > cutoff }
        try? JSONEncoder().encode(kept).write(to: detailsURL, options: .atomic)
    }
    static func loadResults(_ id: UUID) -> [MCArtistRelease]? {
        guard let data = try? Data(contentsOf: resultsURL(id)) else { return nil }
        return try? JSONDecoder().decode([MCArtistRelease].self, from: data)
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

    static func sorted(_ releases: [MCArtistRelease]) -> [MCArtistRelease] {
        releases.sorted { lhs, rhs in
            switch (lhs.date, rhs.date) {
                case let (left?, right?): return left != right ? left > right : lhs.title < rhs.title
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }

    static func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: min(date, Date()), relativeTo: Date())
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
        if releases[feed.id] == nil, let cached = MCArtistShelf.loadResults(feed.id) { releases[feed.id] = cached }
        guard SourceStore.shared.hasLoaded else { return }
        let names = feed.artists ?? []
        let sources = (feed.sourceKeys ?? []).compactMap { key -> AidokuRunner.Source? in
            SourceStore.shared.isDisabled(sourceKey: key) ? nil : SourceStore.shared.source(for: key)
        }
        guard !names.isEmpty else { errors[feed.id] = "Choose at least one artist for this shelf."; return }
        guard !sources.isEmpty else { errors[feed.id] = "None of this shelf's extensions are available. Edit the shelf to choose others."; return }

        loading.insert(feed.id); errors[feed.id] = nil
        artistRefreshed.insert(feed.id)
        // Let the other shelves finish first so their extension calls and ours don't pile up.
        for _ in 0..<60 where !loading.subtracting([feed.id]).isEmpty {
            try? await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { break }
        }
        defer { loading.remove(feed.id); artistProgress[feed.id] = nil }

        // Each extension is asked how it searches by artist and sorts by latest.
        var plans: [String: MCArtistShelf.Plan] = [:]
        await forEachLimited(sources, limit: Self.extensionConcurrency, work: { source in
            let filters = (try? await source.getSearchFilters()) ?? []
            return (source.key, MCArtistShelf.plan(for: filters))
        }, handle: { result in plans[result.0] = result.1 })
        guard !Task.isCancelled else { return }

        struct Pair: Sendable { let source: AidokuRunner.Source; let artist: String; let plan: MCArtistShelf.Plan }
        struct Candidate { let source: AidokuRunner.Source; let manga: AidokuRunner.Manga; var matched: [String]; var trusted: Bool }
        let pairs = sources.flatMap { source in names.map { Pair(source: source, artist: $0, plan: plans[source.key] ?? .init()) } }
        var candidates: [String: Candidate] = [:]
        var order: [String] = []
        var failures = 0, done = 0
        artistProgress[feed.id] = .init(done: 0, total: pairs.count, searching: true)
        let sourcesByKey = Dictionary(sources.map { ($0.key, $0) }, uniquingKeysWith: { lhs, _ in lhs })
        await forEachLimited(pairs, limit: Self.extensionConcurrency, work: { pair in
            await MCArtistShelf.search(source: pair.source, artist: pair.artist, plan: pair.plan)
        }, handle: { result in
            done += 1
            artistProgress[feed.id] = .init(done: done, total: pairs.count, searching: true)
            if result.failed { failures += 1; return }
            guard let source = sourcesByKey[result.sourceKey] else { return }
            var unique = Set<String>()
            let entries = result.entries.filter { manga in
                guard unique.insert(manga.key).inserted else { return false }
                if result.trusted { return true }
                let credited = (manga.artists ?? []) + (manga.authors ?? [])
                return credited.isEmpty || credited.contains { MCArtistShelf.matches($0, result.artist) }
            }
            for manga in entries.prefix(MCArtistShelf.candidatesPerSearch) {
                let id = "\(result.sourceKey)|\(manga.key)"
                if var existing = candidates[id] {
                    if !existing.matched.contains(result.artist) { existing.matched.append(result.artist) }
                    existing.trusted = existing.trusted || result.trusted
                    candidates[id] = existing
                } else {
                    candidates[id] = Candidate(source: source, manga: manga, matched: [result.artist], trusted: result.trusted)
                    order.append(id)
                }
            }
        })
        guard !Task.isCancelled else { return }
        if failures == pairs.count {
            errors[feed.id] = "Searches failed in every extension. Check your connection and try again."
            return
        }

        // Chapter lists give each title's newest release date.
        var details = MCArtistShelf.loadDetails()
        var found: [String: MCArtistRelease] = [:]
        func accept(_ release: MCArtistRelease, for candidate: Candidate) {
            var release = release
            let credited = release.artists + release.authors
            if !candidate.trusted, !credited.isEmpty {
                release.matched = MCArtistShelf.matching(credited, artists: candidate.matched)
                guard !release.matched.isEmpty else { return }
            } else {
                release.matched = candidate.matched
            }
            found[release.id] = release
        }
        func publish() {
            releases[feed.id] = Array(MCArtistShelf.sorted(Array(found.values)).prefix(MCArtistShelf.resultLimit))
        }
        var stale: [Candidate] = []
        for id in order {
            guard let candidate = candidates[id] else { continue }
            if let cached = details[id], Date().timeIntervalSince(cached.checked) < MCArtistShelf.detailLifetime {
                accept(cached, for: candidate)
            } else {
                stale.append(candidate)
            }
        }
        publish()
        done = 0
        artistProgress[feed.id] = .init(done: 0, total: stale.count, searching: false)
        struct Fetch: Sendable { let source: AidokuRunner.Source; let manga: AidokuRunner.Manga; let id: String }
        let fetches = stale.map { Fetch(source: $0.source, manga: $0.manga, id: "\($0.source.key)|\($0.manga.key)") }
        await forEachLimited(fetches, limit: Self.extensionConcurrency, work: { fetch in
            let release = await MCArtistShelf.details(source: fetch.source, manga: fetch.manga)
            return (fetch.id, release)
        }, handle: { result in
            let (id, release) = result
            done += 1
            artistProgress[feed.id] = .init(done: done, total: fetches.count, searching: false)
            guard let candidate = candidates[id] else { return }
            if let release {
                details[id] = release
                accept(release, for: candidate)
            } else if let cached = details[id] {
                accept(cached, for: candidate)
            }
            if done % 8 == 0 { publish() }
        })
        guard !Task.isCancelled else { return }
        publish()
        MCArtistShelf.saveDetails(details)
        let results = releases[feed.id] ?? []
        MCArtistShelf.saveResults(results, for: feed.id)
        let tokens = recordSeenTokens(feed, tokens: results.map(\.seenToken))
        newKeys[feed.id] = Set(results.filter { tokens.contains($0.seenToken) }.map(\.id))
    }

    /// Extension calls hold a shared worker thread while they wait on the network, so running
    /// many at once starves the pool and every call stalls. Two at a time stays clear of that.
    static let extensionConcurrency = 2

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
        }
    }

    private var subtitle: String {
        if let progress = model.artistProgress[feed.id] {
            return progress.searching
                ? "Searching \(progress.done) of \(progress.total)…"
                : "Checking chapters \(progress.done) of \(progress.total)…"
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
            VStack(alignment: .leading, spacing: 3) {
                Text(release.title).font(.subheadline.weight(.semibold)).lineLimit(2).foregroundStyle(.primary)
                Text(release.matched.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if isNew { MCArtistNewBadge() }
                    if let label = release.chapterLabel {
                        Text(label).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor).lineLimit(1)
                    }
                    if let date = release.date {
                        Text(MCArtistShelf.relativeDate(date)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(sources.source(for: release.sourceKey)?.name ?? "").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: Self.height)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([
            isNew ? "New" : nil, release.title, release.matched.joined(separator: ", "),
            release.chapterLabel, release.date.map(MCArtistShelf.relativeDate)
        ].compactMap { $0 }.joined(separator: ", "))
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

/// Every release the artist shelf found (up to 200), newest first and grouped by age.
struct MCArtistReleasesView: View {
    let feedID: UUID
    @ObservedObject var model: MCDiscoverModel
    var openManga: (AidokuRunner.Manga) -> Void = { _ in }
    @State private var artist: String?

    private var feed: MCDiscoverFeed? { model.feeds.first { $0.id == feedID } }

    private struct ReleaseSection: Identifiable {
        let title: String
        var items: [MCArtistRelease]
        var id: String { title }
    }

    private var sections: [ReleaseSection] {
        let all = model.releases[feedID] ?? []
        let filtered = artist.map { name in all.filter { $0.matched.contains(name) } } ?? all
        let calendar = Calendar.current
        let now = Date()
        func bucket(_ date: Date?) -> String {
            guard let date else { return "Date unknown" }
            if calendar.isDateInToday(date) { return "Today" }
            if calendar.isDateInYesterday(date) { return "Yesterday" }
            let days = calendar.dateComponents([.day], from: date, to: now).day ?? 0
            if days < 7 { return "This week" }
            if days < 31 { return "This month" }
            return "Earlier"
        }
        var result: [ReleaseSection] = []
        for release in filtered {
            let title = bucket(release.date)
            if result.last?.title == title { result[result.count - 1].items.append(release) }
            else { result.append(ReleaseSection(title: title, items: [release])) }
        }
        return result
    }

    var body: some View {
        let fresh = model.newKeys[feedID] ?? []
        List {
            if let artists = feed?.artists, artists.count > 1 {
                MCArtistChips(artists: artists, selection: $artist)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if let progress = model.artistProgress[feedID] {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progress.searching ? "Searching \(progress.done) of \(progress.total)…" : "Checking chapters \(progress.done) of \(progress.total)…")
                        .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
                .listRowSeparator(.hidden)
            }
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.items) { release in
                        Button { openManga(release.manga) } label: {
                            MCArtistReleaseRow(release: release, isNew: fresh.contains(release.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if (model.releases[feedID] ?? []).isEmpty, model.artistProgress[feedID] == nil {
                ContentUnavailableView("No releases yet", systemImage: "paintbrush.pointed",
                                       description: Text(model.errors[feedID] ?? "Pull to refresh to search your artists again."))
            }
        }
        .refreshable { if let feed { await model.load(feed, force: true) } }
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

/// Picks the extensions an artist shelf searches.
struct MCSourceMultiPicker: View {
    @Binding var selected: [String]
    @ObservedObject private var sources = SourceStore.shared

    private var installed: [AidokuRunner.Source] {
        sources.sourcesByKey.values.filter { !sources.isDisabled(sourceKey: $0.key) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                ForEach(installed, id: \.key) { source in
                    let isOn = selected.contains(source.key)
                    Button {
                        if isOn { selected.removeAll { $0 == source.key } } else { selected.append(source.key) }
                    } label: {
                        HStack(spacing: 12) {
                            SourceIconView(sourceId: source.key, imageUrl: source.imageUrl, iconSize: 32)
                            Text(source.name).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                                .font(.title3)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: { Text("Each artist is searched in every selected extension. More extensions find more, but take longer to refresh.") }
        }
        .navigationTitle("Extensions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button(selected.count == installed.count ? "Clear" : "Select all") {
                selected = selected.count == installed.count ? [] : installed.map(\.key)
            }
        }
    }
}

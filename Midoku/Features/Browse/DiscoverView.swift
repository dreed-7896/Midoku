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
    /// Artist shelves search these names in these extensions and list the newest releases.
    var artists: [String]?
    var sourceKeys: [String]?

    var isArtists: Bool { artists != nil }
    var isSearch: Bool { query != nil || filters != nil }
    var subtitle: String {
        if isArtists {
            let artistCount = artists?.count ?? 0, sourceCount = sourceKeys?.count ?? 0
            return "\(artistCount) artist\(artistCount == 1 ? "" : "s") · \(sourceCount) extension\(sourceCount == 1 ? "" : "s")"
        }
        guard isSearch else { return sourceName }
        let count = filters?.count ?? 0
        return count > 0 ? "\(sourceName) · Search · \(count) filter\(count == 1 ? "" : "s")" : "\(sourceName) · Search"
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
    /// Artist shelves: releases newest first, and refresh progress.
    @Published var releases: [UUID: [MCArtistRelease]] = [:]
    @Published var artistProgress: [UUID: MCArtistProgress] = [:]
    var artistRefreshed = Set<UUID>()

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key), let feeds = try? JSONDecoder().decode([MCDiscoverFeed].self, from: data) { self.feeds = feeds }
        seen = UserDefaults.standard.dictionary(forKey: Self.seenKey) as? [String: [String]] ?? [:]
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(feeds), forKey: Self.key) }
    func add(source: AidokuRunner.Source, listing: AidokuRunner.Listing) {
        guard !feeds.contains(where: { $0.sourceKey == source.key && $0.listingID == listing.id }) else { return }
        feeds.append(.init(sourceKey: source.key, sourceName: source.name, listingID: listing.id, listingName: listing.name))
        save()
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
    func load(_ feed: MCDiscoverFeed, force: Bool = false) async {
        if feed.isArtists { await loadArtists(feed, force: force); return }
        guard !loading.contains(feed.id), force || entries[feed.id] == nil else { return }
        // Sources load after launch; the shelf retries when its source appears.
        guard SourceStore.shared.hasLoaded else { return }
        guard let source = SourceStore.shared.source(for: feed.sourceKey), !SourceStore.shared.isDisabled(sourceKey: feed.sourceKey) else {
            errors[feed.id] = "This extension is unavailable. Open Extensions to enable or install it."
            return
        }
        loading.insert(feed.id); errors[feed.id] = nil
        defer { loading.remove(feed.id) }
        do {
            let result: AidokuRunner.MangaPageResult
            if feed.isSearch {
                let query = feed.query ?? ""
                result = try await source.getSearchMangaList(query: query.isEmpty ? nil : query, page: 1, filters: feed.filters ?? [])
            } else {
                let listing = try await source.getListings().first { $0.id == feed.listingID }
                guard let listing else { errors[feed.id] = "This tab is no longer available. Remove this shelf and add another tab."; return }
                result = try await source.getMangaList(listing: listing, page: 1)
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
        releases[feed.id] = nil; artistRefreshed.remove(feed.id)
        if feed.isArtists { MCArtistShelf.removeResults(feed.id) }
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
            if feed.isArtists {
                var view = MCArtistReleasesView(feedID: feed.id, model: self.model)
                view.openManga = { [weak self] manga in self?.rootView.openManga(manga) }
                let controller = UIHostingController(rootView: view)
                controller.navigationItem.largeTitleDisplayMode = .always
                navigationController?.pushViewController(controller, animated: true)
                return
            }
            guard let source = SourceStore.shared.source(for: feed.sourceKey) else { return }
            if feed.isSearch {
                let controller = NewSourceViewController(source: source, onlySearch: true, searchQuery: feed.query, initialFilters: feed.filters ?? [])
                navigationController?.pushViewController(controller, animated: true)
                return
            }
            Task { @MainActor in
                guard let listing = try? await source.getListings().first(where: { $0.id == feed.listingID }) else { return }
                self.navigationController?.pushViewController(SourceListingViewController(source: source, listing: listing), animated: true)
            }
        }
        rootView.openShelves = { [weak self] in self?.showShelves() }
        rootView.editArtists = { [weak self] in self?.showShelves(kind: .artists) }
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
        title = "Discover"
        navigationItem.largeTitleDisplayMode = .always
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
    var openManga: (AidokuRunner.Manga) -> Void = { _ in }
    var openListing: (MCDiscoverFeed) -> Void = { _ in }
    var openShelves: () -> Void = {}
    var editArtists: () -> Void = {}
    var openExtensions: () -> Void = {}
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
        let installed = installedSources
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                if !installed.isEmpty {
                    extensionStrip(installed)
                } else if sources.hasLoaded {
                    welcomeCard
                }
                // Shelves stay visible while sources load at launch; they fill in once sources arrive.
                if !installed.isEmpty || !sources.hasLoaded {
                    if !model.feeds.isEmpty {
                        ForEach(Array(model.feeds.enumerated()), id: \.element.id) { index, feed in
                            Group {
                                if feed.isArtists {
                                    MCArtistShelfView(feed: feed, index: index, model: model, openManga: openManga,
                                                      openAll: { openListing(feed) }, edit: editArtists)
                                } else {
                                    shelf(feed, featured: index == 0, index: index)
                                }
                            }
                                .task(id: "\(feed.id)-\(sources.hasLoaded)-\(sources.source(for: feed.sourceKey) != nil)") { await model.load(feed) }
                        }
                        addShelfTile
                    } else if !installed.isEmpty {
                        firstShelfCard
                    }
                    if !installed.isEmpty, !model.feeds.contains(where: \.isArtists) {
                        artistPromptTile
                    }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemBackground))
        .refreshable { await model.reload() }
        .onAppear { extensionUpdates = AppSettings.browse.updateCount.get() }
        .midokuAccent()
    }

    // MARK: Extensions

    private func extensionStrip(_ installed: [AidokuRunner.Source]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Extensions").font(.title3.bold())
                Spacer()
                Button(action: openExtensions) {
                    HStack(spacing: 6) {
                        if extensionUpdates > 0 {
                            Text("\(extensionUpdates)")
                                .font(.caption2.bold()).monospacedDigit().foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(.red, in: Capsule())
                        }
                        Text("Manage")
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
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
                                Text(source.name).font(.caption).lineLimit(1).foregroundStyle(.primary)
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
            message: "Extensions are where stories come from. Install one to browse its catalogue and build your Discover feed.",
            button: "Browse extensions",
            action: openExtensions
        )
    }

    // MARK: Shelves

    private var firstShelfCard: some View {
        promptCard(
            symbol: "rectangle.stack.badge.plus",
            title: "Build your feed",
            message: "Shelves show a tab from an extension, like Popular or Latest, or rerun a search with filters to catch new results. Add a few to see everything new in one place.",
            button: "Add a shelf",
            action: openShelves
        )
    }

    private var artistPromptTile: some View {
        Button(action: editArtists) {
            HStack(spacing: 14) {
                Image(systemName: "paintbrush.pointed.fill").font(.title2).foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44).background(Color.accentColor.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Follow artists").font(.headline).foregroundStyle(.primary)
                    Text("See the newest releases from artists you pick, across your extensions.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private var addShelfTile: some View {
        Button(action: openShelves) {
            Label("Add or reorder shelves", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.accentColor.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                )
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal)
    }

    private func shelf(_ feed: MCDiscoverFeed, featured: Bool, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Button { openListing(feed) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                if feed.isSearch {
                                    Image(systemName: "magnifyingglass").font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                                }
                                Text(feed.listingName).font(.title3.bold()).foregroundStyle(.primary).lineLimit(1)
                                if let count = model.newKeys[feed.id]?.count, count > 0 {
                                    Text("\(count) new").font(.caption.bold()).foregroundStyle(.white)
                                        .padding(.horizontal, 7).padding(.vertical, 2).background(Color.accentColor, in: Capsule())
                                }
                            }
                            Text(feed.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(feed.listingName) from \(feed.sourceName), see all")
                Spacer()
                Menu {
                    Button("See all", systemImage: "square.grid.2x2") { openListing(feed) }
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.load(feed, force: true) } }
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
            .padding(.horizontal)

            if let items = model.entries[feed.id], !items.isEmpty {
                let fresh = model.newKeys[feed.id] ?? []
                if featured {
                    MCDiscoverHero(items: Array(items.prefix(10)), label: feed.listingName, newKeys: fresh,
                                   source: sources.source(for: feed.sourceKey), open: openManga)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(items.prefix(30), id: \.key) { manga in
                                Button { openManga(manga) } label: { coverCard(manga, isNew: fresh.contains(manga.key)) }
                                    .buttonStyle(.plain)
                            }
                        }.scrollTargetLayout().padding(.horizontal)
                    }.scrollTargetBehavior(.viewAligned)
                }
            } else if let error = model.errors[feed.id] {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.subheadline).foregroundStyle(.secondary)
                        Button("Try again") { Task { await model.load(feed, force: true) } }.font(.subheadline.weight(.semibold))
                    }
                    Spacer(minLength: 0)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
            } else if model.loading.contains(feed.id) || model.entries[feed.id] == nil {
                loadingRow(featured: featured)
            } else {
                Text("Nothing in this tab yet.").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal)
            }
        }
    }

    private func loadingRow(featured: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: featured ? 14 : 12) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: featured ? 18 : 12)
                            .fill(Color(uiColor: .secondarySystemBackground))
                            .frame(width: featured ? 320 : 118, height: featured ? 250 : 177)
                        if !featured {
                            RoundedRectangle(cornerRadius: 4).fill(Color(uiColor: .secondarySystemBackground)).frame(width: 90, height: 12)
                        }
                    }
                }
            }.padding(.horizontal)
        }
        .disabled(true)
        .accessibilityLabel("Loading")
    }

    private func coverCard(_ manga: AidokuRunner.Manga, isNew: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            cover(manga, width: 118, height: 177).clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) { if isNew { MCDiscoverNewBadge().padding(6) } }
            Text(manga.title).font(.footnote.weight(.semibold)).lineLimit(3).frame(width: 118, alignment: .leading)
        }.frame(width: 118).accessibilityElement(children: .ignore).accessibilityLabel(isNew ? "New: \(manga.title)" : manga.title)
    }

    private func cover(_ manga: AidokuRunner.Manga, width: CGFloat, height: CGFloat) -> some View {
        SourceImageView(source: sources.source(for: manga.sourceKey), imageUrl: manga.cover ?? "", width: width, height: height,
                        placeholder: "MidokuCoverPlaceholder").frame(width: width, height: height).clipped()
    }

    private func promptCard(symbol: String, title: String, message: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(Color.accentColor)
            Text(title).font(.title2.bold())
            Text(message).font(.subheadline).foregroundStyle(.secondary)
            Button(action: action) {
                Text(button).font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal)
    }
}

private struct MCDiscoverNewBadge: View {
    var body: some View {
        Text("NEW").font(.caption2.weight(.heavy)).foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.accentColor, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

/// The first shelf: large paged cards with the cover, ranking, author and tags.
private struct MCDiscoverHero: View {
    let items: [AidokuRunner.Manga]
    let label: String
    let newKeys: Set<String>
    let source: AidokuRunner.Source?
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
                Capsule()
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
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.15), lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("#\(rank)").font(.caption.weight(.heavy)).monospacedDigit()
                        Text(label).font(.caption.weight(.semibold)).lineLimit(1).opacity(0.8)
                        if newKeys.contains(manga.key) { MCDiscoverNewBadge() }
                    }
                    Text(manga.title).font(.title3.bold()).lineLimit(4).minimumScaleFactor(0.85)
                    if let author { Text(author).font(.subheadline).lineLimit(1).opacity(0.8) }
                    if !tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag).font(.caption2.weight(.semibold)).lineLimit(1)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(.white.opacity(0.18), in: Capsule())
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
            SourceImageView(source: source, imageUrl: manga.cover ?? "", downsampleWidth: 200)
                .scaleEffect(1.4)
                .blur(radius: 30)
                .saturation(1.3)
                .overlay(LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Number \(rank), \(manga.title)\(author.map { ", by \($0)" } ?? "")")
    }

    private func image(_ manga: AidokuRunner.Manga, width: CGFloat, height: CGFloat) -> some View {
        SourceImageView(source: source, imageUrl: manga.cover ?? "", width: width, height: height,
                        placeholder: "MidokuCoverPlaceholder").frame(width: width, height: height).clipped()
    }
}

struct MCDiscoverConfiguration: View {
    enum Kind: String, CaseIterable { case tab = "Tab", search = "Search", artists = "Artists" }

    @ObservedObject var model: MCDiscoverModel
    @ObservedObject private var sources = SourceStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var sourceKey = ""
    @State private var kind: Kind = .tab
    @State private var listingID = ""
    @State private var listings: [AidokuRunner.Listing] = []
    @State private var searchFilters: [AidokuRunner.Filter] = []
    @State private var query = ""
    @State private var enabledFilters: [FilterValue] = []
    @State private var shelfName = ""
    @State private var showFilters = false
    @State private var loading = false
    @State private var error: String?
    @State private var artistNames: [String] = []
    @State private var artistSources: [String] = []
    @State private var artistShelfName = ""

    init(model: MCDiscoverModel, kind: Kind = .tab) {
        self.model = model
        _kind = State(initialValue: kind)
        if let feed = model.feeds.first(where: \.isArtists) {
            _artistNames = State(initialValue: feed.artists ?? [])
            _artistSources = State(initialValue: feed.sourceKeys ?? [])
            _artistShelfName = State(initialValue: feed.listingName == "New from your artists" ? "" : feed.listingName)
        }
    }
    private var installed: [AidokuRunner.Source] {
        sources.sourcesByKey.values.filter { !sources.isDisabled(sourceKey: $0.key) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var canAddSearch: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !enabledFilters.isEmpty
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.feeds) { feed in
                        HStack(spacing: 10) {
                            Image(systemName: feed.isArtists ? "paintbrush.pointed" : feed.isSearch ? "magnifyingglass" : "rectangle.stack")
                                .foregroundStyle(.secondary).frame(width: 22)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(feed.listingName).font(.headline)
                                Text(feed.subtitle).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in offsets.map { model.feeds[$0] }.forEach(model.remove) }
                    .onMove { model.feeds.move(fromOffsets: $0, toOffset: $1); model.save() }
                } header: { Text("Your shelves") } footer: { Text(model.feeds.isEmpty ? "Shelves you add appear on Discover." : "Reorder shelves with Edit. Swipe a shelf to remove it.") }
                Section {
                    if installed.isEmpty { Text("Install an extension from Extensions first.").foregroundStyle(.secondary) }
                    else {
                        Picker("Shelf type", selection: $kind) {
                            ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if kind == .artists {
                            artistFields
                        } else {
                            Picker("Extension", selection: $sourceKey) {
                                Text("Choose extension").tag("")
                                ForEach(installed, id: \.key) { Text($0.name).tag($0.key) }
                            }
                        }
                        if kind == .artists { EmptyView() }
                        else if loading { ProgressView("Loading…") }
                        else if !sourceKey.isEmpty {
                            switch kind {
                                case .tab: tabFields
                                case .search: searchFields
                                case .artists: EmptyView()
                            }
                        }
                        if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                    }
                } header: { Text("Add a shelf") } footer: {
                    if kind == .search {
                        Text("Search shelves rerun your term and filters each time Discover refreshes. Results you haven't seen before are marked New.")
                    } else if kind == .artists {
                        Text("The artist shelf leads Discover. It searches each artist in every chosen extension and lists the newest releases first, 15 on the shelf and up to 200 in See all.")
                    }
                }
            }.navigationTitle("Shelves").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .sheet(isPresented: $showFilters) {
                    FilterListSheetView(filters: searchFilters, search: $query, enabledFilters: $enabledFilters)
                }
                .task(id: "\(sourceKey)-\(kind.rawValue)") { await loadOptions() }
        }.midokuAccent()
    }

    @ViewBuilder private var tabFields: some View {
        if listings.isEmpty {
            Text("This extension does not provide discovery tabs. Try a search shelf.").font(.footnote).foregroundStyle(.secondary)
        } else {
            Picker("Tab", selection: $listingID) { ForEach(listings, id: \.id) { Text($0.name).tag($0.id) } }
            Button("Add shelf", systemImage: "plus.circle.fill") {
                if let source = sources.source(for: sourceKey), let listing = listings.first(where: { $0.id == listingID }) { model.add(source: source, listing: listing) }
            }.disabled(model.feeds.contains { $0.sourceKey == sourceKey && $0.listingID == listingID && !$0.isSearch })
        }
    }

    @ViewBuilder private var searchFields: some View {
        TextField("Search term", text: $query)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
        if !searchFilters.isEmpty {
            Button {
                showFilters = true
            } label: {
                HStack {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    Spacer()
                    Text(enabledFilters.isEmpty ? "None" : "\(enabledFilters.count) applied").foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
            if !enabledFilters.isEmpty {
                Button("Clear filters", role: .destructive) { enabledFilters = [] }
            }
        }
        TextField("Shelf name (optional)", text: $shelfName)
        Button("Add search shelf", systemImage: "plus.circle.fill") {
            guard let source = sources.source(for: sourceKey) else { return }
            model.addSearch(source: source, query: query, filters: enabledFilters, name: shelfName)
            query = ""; enabledFilters = []; shelfName = ""
        }
        .disabled(!canAddSearch)
    }

    @ViewBuilder private var artistFields: some View {
        let existing = model.feeds.contains(where: \.isArtists)
        NavigationLink {
            MCArtistPicker(selected: $artistNames)
        } label: {
            LabeledContent("Artists", value: artistNames.isEmpty ? "None" : artistNames.count <= 2 ? artistNames.joined(separator: ", ") : "\(artistNames.count) selected")
        }
        NavigationLink {
            MCSourceMultiPicker(selected: $artistSources)
        } label: {
            LabeledContent("Extensions", value: artistSources.isEmpty ? "None" : "\(artistSources.count) selected")
        }
        TextField("Shelf name (optional)", text: $artistShelfName)
        Button(existing ? "Save artist shelf" : "Add artist shelf", systemImage: existing ? "checkmark.circle.fill" : "plus.circle.fill") {
            model.saveArtistShelf(artists: artistNames, sourceKeys: artistSources, name: artistShelfName)
            if let feed = model.feeds.first(where: \.isArtists) { Task { await model.load(feed, force: true) } }
            dismiss()
        }
        .disabled(artistNames.isEmpty || artistSources.isEmpty)
    }

    private func loadOptions() async {
        listings = []; listingID = ""; searchFilters = []; error = nil
        guard kind != .artists else { return }
        guard let source = sources.source(for: sourceKey) else { return }
        loading = true
        defer { loading = false }
        do {
            switch kind {
                case .tab:
                    let loaded = try await source.getListings()
                    try Task.checkCancellation()
                    listings = loaded; listingID = loaded.first?.id ?? ""
                case .search:
                    let loaded = try await source.getSearchFilters()
                    try Task.checkCancellation()
                    searchFilters = loaded
                    // Filters from another extension don't apply here.
                    let ids = Set(loaded.map(\.id))
                    enabledFilters.removeAll { !ids.contains($0.id) }
            }
        } catch is CancellationError { }
        catch { self.error = error.midokuDescription() }
    }
}

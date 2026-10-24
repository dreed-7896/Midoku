import AidokuRunner
import SwiftUI

struct MCDiscoverFeed: Codable, Identifiable {
    var id = UUID()
    let sourceKey: String
    let sourceName: String
    let listingID: String
    let listingName: String
}

@MainActor
final class MCDiscoverModel: ObservableObject {
    private static let key = "Midoku.discoverFeeds.v1"
    @Published var feeds: [MCDiscoverFeed] = []
    @Published var entries: [UUID: [AidokuRunner.Manga]] = [:]
    @Published var errors: [UUID: String] = [:]
    @Published var loading = Set<UUID>()

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key), let feeds = try? JSONDecoder().decode([MCDiscoverFeed].self, from: data) { self.feeds = feeds }
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(feeds), forKey: Self.key) }
    func add(source: AidokuRunner.Source, listing: AidokuRunner.Listing) {
        guard !feeds.contains(where: { $0.sourceKey == source.key && $0.listingID == listing.id }) else { return }
        feeds.append(.init(sourceKey: source.key, sourceName: source.name, listingID: listing.id, listingName: listing.name))
        save()
    }
    func load(_ feed: MCDiscoverFeed, force: Bool = false) async {
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
            let listing = try await source.getListings().first { $0.id == feed.listingID }
            guard let listing else { errors[feed.id] = "This tab is no longer available. Remove this shelf and add another tab."; return }
            let result = try await source.getMangaList(listing: listing, page: 1)
            try Task.checkCancellation()
            var seen = Set<String>()
            entries[feed.id] = result.entries.filter { seen.insert($0.key).inserted }
        } catch is CancellationError { }
        catch { errors[feed.id] = error.midokuDescription() }
    }
    func remove(_ feed: MCDiscoverFeed) {
        feeds.removeAll { $0.id == feed.id }
        entries[feed.id] = nil; errors[feed.id] = nil
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
            guard let self, let source = SourceStore.shared.source(for: feed.sourceKey) else { return }
            Task { @MainActor in
                guard let listing = try? await source.getListings().first(where: { $0.id == feed.listingID }) else { return }
                self.navigationController?.pushViewController(SourceListingViewController(source: source, listing: listing), animated: true)
            }
        }
        rootView.openShelves = { [weak self] in self?.showShelves() }
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

    private func showShelves() {
        guard presentedViewController == nil else { return }
        present(UIHostingController(rootView: MCDiscoverConfiguration(model: model).midokuAccent()), animated: true)
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
                            shelf(feed, featured: index == 0, index: index)
                                .task(id: "\(feed.id)-\(sources.hasLoaded)-\(sources.source(for: feed.sourceKey) != nil)") { await model.load(feed) }
                        }
                        addShelfTile
                    } else if !installed.isEmpty {
                        firstShelfCard
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
            message: "Shelves show a tab from an extension, like Popular or Latest. Add a few to see everything new in one place.",
            button: "Add a shelf",
            action: openShelves
        )
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
                            Text(feed.listingName).font(.title3.bold()).foregroundStyle(.primary)
                            Text(feed.sourceName).font(.subheadline).foregroundStyle(.secondary)
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
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: featured ? 14 : 12) {
                        ForEach(items.prefix(30), id: \.key) { manga in
                            Button { openManga(manga) } label: {
                                if featured { featureCard(manga) } else { coverCard(manga) }
                            }.buttonStyle(.plain)
                        }
                    }.scrollTargetLayout().padding(.horizontal)
                }.scrollTargetBehavior(.viewAligned)
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
                            .frame(width: featured ? 300 : 118, height: featured ? 200 : 177)
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

    private func featureCard(_ manga: AidokuRunner.Manga) -> some View {
        ZStack(alignment: .bottomLeading) {
            cover(manga, width: 300, height: 200).blur(radius: 24).overlay(.black.opacity(0.4))
            HStack(alignment: .bottom, spacing: 14) {
                cover(manga, width: 104, height: 156).clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 6) {
                    Text(manga.title).font(.headline).lineLimit(3).foregroundStyle(.white)
                    if let author = manga.artists?.first ?? manga.authors?.first {
                        Text(author).font(.caption).lineLimit(1).foregroundStyle(.white.opacity(0.75))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(16)
        }.frame(width: 300, height: 200).clipShape(RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .ignore).accessibilityLabel(manga.title)
    }

    private func coverCard(_ manga: AidokuRunner.Manga) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            cover(manga, width: 118, height: 177).clipShape(RoundedRectangle(cornerRadius: 12))
            Text(manga.title).font(.footnote.weight(.semibold)).lineLimit(2).frame(width: 118, alignment: .leading)
        }.frame(width: 118).accessibilityElement(children: .ignore).accessibilityLabel(manga.title)
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

private struct MCDiscoverConfiguration: View {
    @ObservedObject var model: MCDiscoverModel
    @ObservedObject private var sources = SourceStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var sourceKey = ""
    @State private var listingID = ""
    @State private var listings: [AidokuRunner.Listing] = []
    @State private var loading = false
    @State private var error: String?
    private var installed: [AidokuRunner.Source] {
        sources.sourcesByKey.values.filter { !sources.isDisabled(sourceKey: $0.key) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.feeds) { feed in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(feed.listingName).font(.headline)
                            Text(feed.sourceName).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { model.feeds.remove(atOffsets: $0); model.save() }
                    .onMove { model.feeds.move(fromOffsets: $0, toOffset: $1); model.save() }
                } header: { Text("Your shelves") } footer: { Text(model.feeds.isEmpty ? "Shelves you add appear on Discover." : "Reorder shelves with Edit. Swipe a shelf to remove it.") }
                Section("Add a shelf") {
                    if installed.isEmpty { Text("Install an extension from Extensions first.").foregroundStyle(.secondary) }
                    else {
                        Picker("Extension", selection: $sourceKey) {
                            Text("Choose extension").tag("")
                            ForEach(installed, id: \.key) { Text($0.name).tag($0.key) }
                        }
                        if loading { ProgressView("Loading tabs…") }
                        else if !listings.isEmpty {
                            Picker("Tab", selection: $listingID) { ForEach(listings, id: \.id) { Text($0.name).tag($0.id) } }
                            Button("Add shelf", systemImage: "plus.circle.fill") {
                                if let source = sources.source(for: sourceKey), let listing = listings.first(where: { $0.id == listingID }) { model.add(source: source, listing: listing) }
                            }.disabled(model.feeds.contains { $0.sourceKey == sourceKey && $0.listingID == listingID })
                        }
                        if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
            }.navigationTitle("Shelves").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .task(id: sourceKey) {
                    listings = []; listingID = ""; error = nil
                    guard let source = sources.source(for: sourceKey) else { return }
                    loading = true
                    defer { loading = false }
                    do {
                        let loaded = try await source.getListings()
                        try Task.checkCancellation()
                        listings = loaded; listingID = loaded.first?.id ?? ""
                        if loaded.isEmpty { error = "This extension does not provide discovery tabs." }
                    } catch is CancellationError { }
                    catch { self.error = error.midokuDescription() }
                }
        }.midokuAccent()
    }
}

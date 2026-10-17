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
        guard let source = SourceStore.shared.source(for: feed.sourceKey), !SourceStore.shared.isDisabled(sourceKey: feed.sourceKey) else {
            errors[feed.id] = "This extension is unavailable. Open Extensions to enable or install it."
            return
        }
        loading.insert(feed.id); errors[feed.id] = nil
        defer { loading.remove(feed.id) }
        do {
            let listing = try await source.getListings().first { $0.id == feed.listingID }
            guard let listing else { errors[feed.id] = "This tab is no longer available. Choose another tab in Customize."; return }
            let result = try await source.getMangaList(listing: listing, page: 1)
            try Task.checkCancellation()
            var seen = Set<String>()
            entries[feed.id] = result.entries.filter { seen.insert($0.key).inserted }
        } catch is CancellationError { }
        catch { errors[feed.id] = error.midokuDescription() }
    }
    func reload() async {
        // Each shelf keeps its covers and previous results while refreshing.
        for feed in feeds { await load(feed, force: true) }
    }
}

final class DiscoverViewController: UIHostingController<MCDiscoverView> {
    init() {
        super.init(rootView: MCDiscoverView())
        rootView.openManga = { [weak self] manga in
            guard let self else { return }
            navigationController?.pushViewController(MangaViewController(source: SourceStore.shared.source(for: manga.sourceKey), manga: manga, parent: self), animated: true)
        }
        rootView.openListing = { [weak self] feed in
            guard let self, let source = SourceStore.shared.source(for: feed.sourceKey) else { return }
            Task { @MainActor in
                guard let listing = try? await source.getListings().first(where: { $0.id == feed.listingID }) else { return }
                navigationController?.pushViewController(SourceListingViewController(source: source, listing: listing), animated: true)
            }
        }
        rootView.openExtensions = { [weak self] in self?.navigationController?.pushViewController(BrowseViewController(), animated: true) }
        title = "Discover"
        navigationItem.largeTitleDisplayMode = .always
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

struct MCDiscoverView: View {
    @StateObject private var model = MCDiscoverModel()
    @ObservedObject private var sources = SourceStore.shared
    @State private var customize = false
    var openManga: (AidokuRunner.Manga) -> Void = { _ in }
    var openListing: (MCDiscoverFeed) -> Void = { _ in }
    var openExtensions: () -> Void = {}

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("YOUR NEXT READ").font(.caption.weight(.bold)).tracking(2).foregroundStyle(Color.accentColor)
                        Text("A world of stories.").font(.largeTitle.bold())
                        Text("Your favorite extensions, together.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }.padding(.horizontal).padding(.top, 12)

                HStack(spacing: 12) {
                    Button { customize = true } label: { Label("Customize", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                    Button(action: openExtensions) { Label("Extensions", systemImage: "puzzlepiece.extension").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                }.controlSize(.large).padding(.horizontal)

                if model.feeds.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 38)).foregroundStyle(Color.accentColor)
                        Text("Build your discovery shelves").font(.title2.bold())
                        Text("Pick an extension and a tab, like Latest or Popular. Add more to explore them all here.").foregroundStyle(.secondary)
                        Button("Choose extensions and tabs") { customize = true }.buttonStyle(.borderedProminent)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 24)).padding(.horizontal)
                }
                ForEach(Array(model.feeds.enumerated()), id: \.element.id) { index, feed in
                    shelf(feed, featured: index == 0, ranked: index % 2 == 1)
                        .task(id: "\(feed.id)-\(sources.source(for: feed.sourceKey) != nil)") { await model.load(feed) }
                }
            }.padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemBackground))
        .refreshable { await model.reload() }
        .sheet(isPresented: $customize) { MCDiscoverConfiguration(model: model) }
        .midokuAccent()
    }

    private func shelf(_ feed: MCDiscoverFeed, featured: Bool, ranked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(feed.sourceName.uppercased()).font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(.secondary)
                    Text(feed.listingName).font(.title2.bold())
                }
                Spacer()
                Button { openListing(feed) } label: { Image(systemName: "arrow.up.right").font(.headline).padding(12).background(.quaternary, in: Circle()) }
                    .accessibilityLabel("See all \(feed.sourceName) \(feed.listingName)")
            }.padding(.horizontal)
            if let items = model.entries[feed.id], !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: featured ? 16 : 14) {
                        ForEach(Array(items.prefix(30).enumerated()), id: \.element.key) { index, manga in
                            Button { openManga(manga) } label: {
                                if featured { featureCard(manga, feed: feed) }
                                else { coverCard(manga, rank: ranked ? index + 1 : nil) }
                            }.buttonStyle(.plain)
                        }
                    }.scrollTargetLayout().padding(.horizontal)
                }.scrollTargetBehavior(.viewAligned)
            } else if model.loading.contains(feed.id) {
                HStack { ProgressView(); Text("Loading stories…").foregroundStyle(.secondary) }.padding(24)
            } else if model.errors[feed.id] == nil {
                Text("No stories in this tab yet.").foregroundStyle(.secondary).padding(.horizontal)
            }
            if let error = model.errors[feed.id] {
                VStack(alignment: .leading, spacing: 10) {
                    Text(error).font(.subheadline).foregroundStyle(.secondary)
                    Button("Try again") { Task { await model.load(feed, force: true) } }
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal)
            }
        }
    }

    private func featureCard(_ manga: AidokuRunner.Manga, feed: MCDiscoverFeed) -> some View {
        ZStack(alignment: .bottomLeading) {
            cover(manga, width: 310, height: 240).blur(radius: 22).overlay(.black.opacity(0.45))
            HStack(alignment: .bottom, spacing: 16) {
                cover(manga, width: 110, height: 165).clipShape(RoundedRectangle(cornerRadius: 10)).shadow(radius: 10)
                VStack(alignment: .leading, spacing: 10) {
                    Text("EXPLORE").font(.caption2.bold()).tracking(2).foregroundStyle(.white.opacity(0.7))
                    Text(manga.title).font(.headline).lineLimit(4).foregroundStyle(.white)
                    Label("Read more", systemImage: "arrow.right").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(20)
        }.frame(width: 310, height: 240).clipShape(RoundedRectangle(cornerRadius: 22))
            .accessibilityElement(children: .ignore).accessibilityLabel(manga.title)
    }
    private func coverCard(_ manga: AidokuRunner.Manga, rank: Int?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cover(manga, width: 132, height: 198).clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottomLeading) {
                    if let rank {
                        Text(String(format: "%02d", rank)).font(.title2.weight(.black).monospacedDigit()).foregroundStyle(.white)
                            .padding(.horizontal, 9).padding(.vertical, 4).background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8)).padding(7)
                    }
                }
            Text(manga.title).font(.subheadline.weight(.semibold)).lineLimit(2).frame(width: 132, alignment: .leading)
        }.frame(width: 132).accessibilityElement(children: .ignore).accessibilityLabel(manga.title)
    }
    private func cover(_ manga: AidokuRunner.Manga, width: CGFloat, height: CGFloat) -> some View {
        SourceImageView(source: sources.source(for: manga.sourceKey), imageUrl: manga.cover ?? "", width: width, height: height,
                        placeholder: "MidokuCoverPlaceholder").frame(width: width, height: height).clipped()
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
                } header: { Text("Your shelves") } footer: { Text("Reorder shelves with Edit. Swipe a shelf to remove it.") }
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
            }.navigationTitle("Customize Discover").navigationBarTitleDisplayMode(.inline)
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

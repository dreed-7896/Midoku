import AidokuRunner
import Observation
import SwiftUI
import UniformTypeIdentifiers
import SwiftUIIntrospect

struct MCID: Identifiable { let id: UUID }

private enum MCLibraryGrouping: String, CaseIterable, Identifiable {
    case none, category, artist, author, status, tag, source

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "None"
        case .category: "Category"
        case .artist: "Artist"
        case .author: "Author"
        case .status: "Status"
        case .tag: "Tag"
        case .source: "Source"
        }
    }
}

private enum MCLibraryProgressFilter: String, CaseIterable, Identifiable {
    case all, notStarted, inProgress, completed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Any progress"
        case .notStarted: "Not started"
        case .inProgress: "In progress"
        case .completed: "Fully read"
        }
    }
}

private struct MCLibraryGroupPage: Identifiable {
    let id: String
    let title: String
    let entryIDs: Set<UUID>
}

@Observable private final class MCLibrarySwipePosition {
    var page: CGFloat = 0
    var requestedID: String?
}

private struct MCLibraryTabAnchors: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newer in newer })
    }
}

private struct MCLibrarySourceOption: Identifiable, Equatable {
    let id: UUID
    let name: String
}

private enum MCBatchCategoryMode: String, CaseIterable, Identifiable {
    case add, replace, remove
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct MCCollectionRootView: View {
    @State private var store = MCCollectionStore.shared
    @State private var path: [UUID] = []
    @State private var query = ""
    @State private var searchVisible = false
    @State private var searchFocused: Bool?
    @State private var groupPage: String?
    @State private var swipePosition = MCLibrarySwipePosition()
    @State private var statuses = Set<MCPersonalStatus>()
    @State private var artists = Set<String>()
    @State private var tags = Set<String>()
    @State private var sources = Set<UUID>()
    @State private var progressFilter = MCLibraryProgressFilter.all
    @AppStorage("Midoku.libraryGrouping") private var grouping = MCLibraryGrouping.category
    @State private var sort = MCLibrarySort.recentlyAdded
    @State private var showCategories = false
    @State private var showBatchCategories = false
    @State private var showBatchArtist = false
    @State private var showGroupTitles = false
    @State private var groupingEntryIDs: [UUID] = []
    @State private var selected = Set<UUID>()
    @State private var selecting = false
    @State private var confirmDelete = false
    @State private var editingEntry: MCID?
    @State private var movingEntry: MCID?
    @State private var showAddPreview = false
    @State private var readingMode = false
    @State private var showReadingAdd = false
    @State private var reader: MCReaderSheet?
    @State private var showBookmarks = false
    @State private var selectedBookmark: MCPanelBookmark?
    @State private var confirmResetReading = false
    @AppStorage("Midoku.collectionGrid") private var grid = true
    @AppStorage("Midoku.chapterGrid") private var chapterGrid = false
    @AppStorage("Appearance.libraryGridStyle") private var gridStyle = ChapterGridStyle.standard
    @AppStorage("Appearance.libraryPortraitColumns") private var portraitColumns = 3
    @AppStorage("Appearance.libraryLandscapeColumns") private var landscapeColumns = 5

    private func entries(in groupPage: String?) -> [MCPersonalEntry] {
        let groupEntryIDs = groupPage.flatMap { selected in
            groupPages.first(where: { $0.id == selected })?.entryIDs
        }
        return store.library.entries.filter { entry in
            let details = store.library.listing(entry.primaryListingID)?.details
            let searchable = [
                store.library.title(entry),
                entry.authorOverride,
                entry.artistOverride,
                details?.authors?.joined(separator: " "),
                details?.artists?.joined(separator: " "),
                entryTags(entry).joined(separator: " ")
            ].compactMap { $0 }.joined(separator: " ")
            let sourceIDs = entry.links.compactMap { store.library.listing($0.listingID)?.identity.connectionID }
            return (entry.parentEntryID == nil || showsFlatResults) &&
                (query.isEmpty || searchable.localizedCaseInsensitiveContains(query)) &&
                (groupPage == nil || groupEntryIDs?.contains(entry.id) == true) &&
                (statuses.isEmpty || statuses.contains(entry.status)) &&
                (artists.isEmpty || !artists.isDisjoint(with: Set(artistNames(entry)))) &&
                (tags.isEmpty || !tags.isDisjoint(with: Set(entryTags(entry)))) &&
                (sources.isEmpty || !sources.isDisjoint(with: Set(sourceIDs))) &&
                matchesProgress(entry)
        }.sorted { lhs, rhs in
            switch sort {
            case .title: store.library.title(lhs).localizedStandardCompare(store.library.title(rhs)) == .orderedAscending
            case .recentlyRead: (lhs.lastReadAt ?? .distantPast) > (rhs.lastReadAt ?? .distantPast)
            case .recentlyAdded: lhs.createdAt > rhs.createdAt
            case .recentlyUpdated: lhs.updatedAt > rhs.updatedAt
            }
        }
    }

    private var showsFlatResults: Bool { hasActiveFilters || !query.isEmpty }

    private var hasActiveFilters: Bool {
        !statuses.isEmpty || !artists.isEmpty || !tags.isEmpty || !sources.isEmpty || progressFilter != .all
    }

    private var activeFilterCount: Int {
        statuses.count + artists.count + tags.count + sources.count + (progressFilter == .all ? 0 : 1)
    }

    private var availableTags: [String] {
        Array(Set(store.library.entries.flatMap { entryTags($0) })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func artistNames(_ entry: MCPersonalEntry) -> [String] {
        let names = entry.artistOverride.map { [$0] }
            ?? store.library.listing(entry.primaryListingID)?.details.artists ?? []
        return names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private var availableArtists: [String] {
        Array(Set(store.library.entries.flatMap(artistNames)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var availableSources: [MCLibrarySourceOption] {
        let ids = Set(store.library.entries.flatMap { entry in
            entry.links.compactMap { store.library.listing($0.listingID)?.identity.connectionID }
        })
        return ids.map { MCLibrarySourceOption(id: $0, name: store.sourceName($0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func entryTags(_ entry: MCPersonalEntry) -> [String] {
        var seen = Set<String>()
        let listingIDs = [entry.primaryListingID].compactMap { $0 } + entry.links.map(\.listingID)
        return listingIDs.compactMap { store.library.listing($0)?.details.tags }.flatMap { $0 }.filter { tag in
            let key = tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return seen.insert(key).inserted
        }
    }

    private func matchesProgress(_ entry: MCPersonalEntry) -> Bool {
        guard progressFilter != .all else { return true }
        let total = store.chapterCount(entryID: entry.id)
        let read = total - store.unreadCount(entryID: entry.id)
        return switch progressFilter {
        case .all: true
        case .notStarted: read == 0
        case .inProgress: read > 0 && read < total
        case .completed: total > 0 && read == total
        }
    }

    private var groupPages: [MCLibraryGroupPage] {
        switch grouping {
        case .none:
            return []
        case .category:
            var pages = store.snapshot.categories.map { category in
                MCLibraryGroupPage(
                    id: "category:\(category.id.uuidString)",
                    title: category.name,
                    entryIDs: Set(store.library.rootEntries.filter { $0.categoryIDs.contains(category.id) }.map(\.id))
                )
            }
            let uncategorized = Set(store.library.rootEntries.filter { $0.categoryIDs.isEmpty }.map(\.id))
            if !uncategorized.isEmpty {
                pages.append(.init(id: "category:uncategorized", title: "Uncategorized", entryIDs: uncategorized))
            }
            return pages
        case .artist:
            return namedGroupPages(prefix: "artist", emptyTitle: "Unknown artist", values: artistNames)
        case .author:
            return namedGroupPages(prefix: "author", emptyTitle: "Unknown author") { entry in
                if let override = entry.authorOverride, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    [override]
                } else {
                    store.library.listing(entry.primaryListingID)?.details.authors ?? []
                }
            }
        case .status:
            return MCPersonalStatus.allCases.compactMap { status in
                let ids = Set(store.library.rootEntries.filter { $0.status == status }.map(\.id))
                return ids.isEmpty ? nil : .init(id: "status:\(status.rawValue)", title: status.title, entryIDs: ids)
            }
        case .tag:
            return namedGroupPages(prefix: "tag", emptyTitle: "Untagged", values: entryTags)
        case .source:
            var buckets: [UUID: Set<UUID>] = [:]
            var unavailable = Set<UUID>()
            for entry in store.library.rootEntries {
                let connectionIDs = Set(entry.links.compactMap { store.library.listing($0.listingID)?.identity.connectionID })
                if connectionIDs.isEmpty { unavailable.insert(entry.id) }
                for connectionID in connectionIDs { buckets[connectionID, default: []].insert(entry.id) }
            }
            var pages: [MCLibraryGroupPage] = buckets.map { connectionID, entryIDs in
                MCLibraryGroupPage(id: "source:\(connectionID.uuidString)", title: store.sourceName(connectionID), entryIDs: entryIDs)
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            if !unavailable.isEmpty {
                pages.append(.init(id: "source:unavailable", title: "Unavailable source", entryIDs: unavailable))
            }
            return pages
        }
    }

    private var activeGroupPage: String? {
        grouping == .none || showsFlatResults ? nil : (groupPage ?? groupPages.first?.id)
    }

    private func namedGroupPages(
        prefix: String,
        emptyTitle: String,
        values: (MCPersonalEntry) -> [String]
    ) -> [MCLibraryGroupPage] {
        var buckets: [String: (title: String, entryIDs: Set<UUID>)] = [:]
        for entry in store.library.rootEntries {
            let names = values(entry).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            for name in names.isEmpty ? [emptyTitle] : names {
                let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                var bucket = buckets[key] ?? (name, [])
                bucket.entryIDs.insert(entry.id)
                buckets[key] = bucket
            }
        }
        return buckets.map { key, bucket in
            .init(id: "\(prefix):\(key)", title: bucket.title, entryIDs: bucket.entryIDs)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if readingMode { readingPage }
                else { regularLibraryPage }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(readingMode ? "Reading" : "Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if readingMode {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button { readingMode = false } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Exit Reading Mode")
                        Button { confirmResetReading = true } label: { Image(systemName: "arrow.counterclockwise") }
                            .accessibilityLabel("Reset Reading")
                            .disabled(store.library.readingIDs.isEmpty)
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { showReadingAdd = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Add to Reading")
                    }
                } else if selecting {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { selecting = false; selected.removeAll() } label: {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        .accessibilityLabel("Done selecting")
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) { groupMenu }
                    ToolbarItem(placement: .topBarLeading) { filterMenu }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            query = ""; searchVisible = false; searchFocused = false
                            selected.removeAll(); selecting = false
                            readingMode = true
                        } label: { Image(systemName: "book") }
                            .accessibilityLabel("Reading mode")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Search library", systemImage: "magnifyingglass") {
                                searchVisible = true
                                searchFocused = true
                            }
                            Divider()
                            Button("Select entries", systemImage: "checkmark.circle") {
                                searchFocused = false; searchVisible = false
                                query = ""
                                selecting = true; selected.removeAll()
                            }
                            Picker("Sort", selection: $sort) { ForEach(MCLibrarySort.allCases) { Text($0.title).tag($0) } }
                            Toggle("Cover grid", isOn: $grid)
                            Toggle("Chapter grid", isOn: $chapterGrid)
                            Button("Categories", systemImage: "folder") { showCategories = true }
                            Button("Bookmarks", systemImage: "bookmark") { showBookmarks = true }
                            Button("Refresh library", systemImage: "arrow.clockwise") { Task { await store.refresh() } }.disabled(store.isRefreshing)
                        } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Library options")
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if selecting && !readingMode { selectionActions }
            }
            .confirmationDialog("Remove \(selected.count) entries from library?", isPresented: $confirmDelete) {
                let containsNested = selected.contains { !store.library.descendantIDs(of: $0).isEmpty }
                Button(containsNested ? "Remove titles, keep nested titles in library" : "Remove entries", role: .destructive) {
                    if store.removeEntries(selected) { selected.removeAll(); selecting = false }
                }
                if containsNested {
                    Button("Remove titles and all nested titles", role: .destructive) {
                        if store.removeEntries(selected, includingDescendants: true) { selected.removeAll(); selecting = false }
                    }
                }
            } message: { Text("Reading history and downloaded chapters are kept.") }
            .confirmationDialog("Clear Reading?", isPresented: $confirmResetReading) {
                Button("Clear Reading", role: .destructive) {
                    store.removeFromReading(Set(store.library.readingIDs))
                }
            } message: { Text("Your library entries and reading progress will stay unchanged.") }
            .sheet(item: $movingEntry) { MCEntryPlacementView(mode: .move($0.id)) }
            .sheet(item: $editingEntry) { MCEntryEditor(entryID: $0.id) }
            .sheet(isPresented: $showReadingAdd) { MCReadingAddSheet() }
            .sheet(isPresented: $showBookmarks, onDismiss: {
                guard let bookmark = selectedBookmark else { return }
                selectedBookmark = nil
                do { reader = try MCPanelBookmarks.reader(for: bookmark) }
                catch { store.error = "This bookmarked chapter is no longer available in your library." }
            }) {
                MCPanelBookmarksView { selectedBookmark = $0 }
            }
            .modifier(MCReaderPresentation(sheet: $reader))
            .sheet(isPresented: $showCategories) { MCCategoriesView() }
            .sheet(isPresented: $showBatchCategories) { MCBatchCategoryEditor(entryIDs: selected) }
            .sheet(isPresented: $showBatchArtist) { MCBatchArtistEditor(entryIDs: selected) }
            .sheet(isPresented: $showGroupTitles) {
                MCEntryEditor(grouping: groupingEntryIDs) { id in
                    selected.removeAll(); selecting = false
                    path.append(id)
                }
            }
            .sheet(isPresented: $showAddPreview) {
                if let manga = store.snapshot.manga.first?.manga { MCAddSourceView(manga: manga, chapters: []) }
            }
            .mcErrors(store)
            .navigationDestination(for: UUID.self) { MCEntryView(entryID: $0) }
            .onReceive(NotificationCenter.default.publisher(for: .libraryTabReselected)) { _ in
                if !path.isEmpty {
                    path.removeAll()
                    return
                }
                guard !readingMode, !showsFlatResults, grouping != .none else { return }
                groupPage = groupPages.first?.id
                swipePosition.requestedID = groupPages.first?.id
            }
            .onChange(of: grouping) { _, value in
                groupPage = value == .none ? nil : groupPages.first?.id
            }
            .onChange(of: groupPages.map(\.id)) { _, values in
                guard grouping != .none else { groupPage = nil; return }
                if groupPage.map(values.contains) != true { groupPage = values.first }
            }
            .onChange(of: availableTags) { _, values in tags.formIntersection(values) }
            .onChange(of: availableArtists) { _, values in artists.formIntersection(values) }
            .onChange(of: availableSources.map(\.id)) { _, values in sources.formIntersection(values) }
            .onChange(of: store.library.entries.map(\.id)) { _, ids in selected.formIntersection(ids) }
            .onAppear {
                if grouping != .none, groupPage == nil { groupPage = groupPages.first?.id }
            }
            .task {
                #if DEBUG
                let args = ProcessInfo.processInfo.arguments
                if args.contains("--collection-preview") {
                    try? await Task.sleep(for: .milliseconds(750))
                    if args.contains("--reading-preview") {
                        if let id = MCCollectionPreview.entryID { store.addToReading([id]) }
                        readingMode = true
                    }
                    if args.contains("--add-preview") { showAddPreview = true }
                    if args.contains("--categories-preview") { showCategories = true }
                    if args.contains("--selection-preview") { selecting = true; selected = Set(store.library.entries.map(\.id)) }
                    if !args.contains("--collection-preview-only"), args.contains("--entry-preview") || args.contains("--edit-preview") || args.contains(where: { $0.hasPrefix("--chapter-") }) || args.contains("--reader-preview") || args.contains("--reader-hidden-preview"), let id = MCCollectionPreview.entryID { path = [id] }
                    return
                }
                #endif
                await store.adoptExistingLibrary()
            }
        }
        .introspect(.navigationStack, on: .iOS(.v26, .v27)) { navigation in
            navigation.interactivePopGestureRecognizer?.isEnabled = true
            navigation.interactiveContentPopGestureRecognizer?.isEnabled = true
        }
        .midokuAccent()
    }

    private var regularLibraryPage: some View {
        Group {
            let pages = groupPages
            VStack(spacing: 0) {
                if grouping != .none && !showsFlatResults {
                    MCLibraryGroupTabs(pages: pages, selected: groupPage, swipePosition: swipePosition)
                }
                GeometryReader { geometry in
                    let visibleEntries = entries(in: nil)
                    if grouping == .none || pages.isEmpty || showsFlatResults {
                        collectionPage(values: visibleEntries, size: geometry.size)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 0) {
                                    ForEach(pages) { page in
                                        collectionPage(values: visibleEntries.filter { page.entryIDs.contains($0.id) }, size: geometry.size)
                                            .frame(width: geometry.size.width, height: geometry.size.height)
                                            .id(page.id)
                                    }
                                }
                                .scrollTargetLayout()
                            }
                            .scrollIndicators(.hidden)
                            .scrollTargetBehavior(.paging)
                            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                                guard geometry.containerSize.width > 0 else { return 0 }
                                return min(CGFloat(pages.count - 1), max(0, geometry.contentOffset.x / geometry.containerSize.width))
                            } action: { _, page in
                                swipePosition.page = page
                            }
                            .onScrollPhaseChange { _, phase in
                                guard phase == .idle else { return }
                                let index = Int(swipePosition.page.rounded())
                                if pages.indices.contains(index) { groupPage = pages[index].id }
                                swipePosition.requestedID = nil
                            }
                            .onChange(of: swipePosition.requestedID) { _, id in
                                guard let id, pages.contains(where: { $0.id == id }) else { return }
                                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .leading) }
                            }
                            .onChange(of: groupPage) { _, id in
                                guard let id, pages.contains(where: { $0.id == id }) else { return }
                                let index = Int(swipePosition.page.rounded())
                                if pages.indices.contains(index), pages[index].id == id { return }
                                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .leading) }
                            }
                            .onAppear {
                                if let id = groupPage, let index = pages.firstIndex(where: { $0.id == id }) {
                                    swipePosition.page = CGFloat(index)
                                    proxy.scrollTo(id, anchor: .leading)
                                }
                            }
                        }
                    }
                }
            }
            .customSearchable(
                text: $query,
                enabled: $searchVisible,
                focused: $searchFocused,
                hidesSearchBarWhenScrolling: false,
                stacked: false,
                onCancel: { searchVisible = false; searchFocused = false }
            )
            .environment(\.autocorrectionDisabled, true)
        }
    }

    private var readingPage: some View {
        GeometryReader { geometry in
            if store.readingEntries.isEmpty {
                UnavailableView("Nothing in Reading", systemImage: "books.vertical",
                    description: Text("Tap + to add entries from your library."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns(for: geometry.size), alignment: .leading, spacing: grid ? 20 : 14) {
                        ForEach(store.readingEntries) { entry in entryButton(entry) }
                    }
                    .padding(.horizontal).padding(.vertical)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button { openRandomEntry(from: store.readingEntries) } label: {
                Image(systemName: "shuffle").font(.title3.weight(.semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Open random Reading entry; hold for entire library")
            .disabled(store.library.entries.isEmpty)
            .highPriorityGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                openRandomEntry(from: store.library.entries)
            })
            .padding(.trailing, 18).padding(.bottom, 16)
        }
    }

    private func openRandomEntry(from entries: [MCPersonalEntry]) {
        let candidates = store.library.entriesIncludingDescendants(of: Set(entries.map(\.id)))
        guard let entry = candidates.filter({ store.chapterCount(entryID: $0.id) > 0 }).randomElement(),
              let first = store.library.flattenedChapters(entryID: entry.id).first?.slot else {
            store.error = "No chapters are available to read."
            return
        }
        do { reader = MCReaderSheet(sequence: try MCReaderSequence(entryID: entry.id, slotID: first.id)) }
        catch { store.error = error.localizedDescription }
    }

    private var selectionActions: some View {
        HStack {
            let visibleIDs = Set(entries(in: activeGroupPage).map(\.id))
            Button(selected.isSuperset(of: visibleIDs) && !visibleIDs.isEmpty ? "Deselect all" : "Select all") {
                if selected.isSuperset(of: visibleIDs) { selected.subtract(visibleIDs) }
                else { selected.formUnion(visibleIDs) }
            }
            .font(.headline)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            Spacer()
            Menu {
                Button("Add to Reading", systemImage: "book") {
                    if store.addToReading(selected) { selected.removeAll(); selecting = false }
                }
                Button("Group into new title", systemImage: "rectangle.stack.badge.plus") {
                    let visible = entries(in: nil).map(\.id).filter { selected.contains($0) }
                    let visibleIDs = Set(visible)
                    groupingEntryIDs = visible + store.library.entries.map(\.id).filter { selected.contains($0) && !visibleIDs.contains($0) }
                    showGroupTitles = true
                }.disabled(selected.count < 2)
                Divider()
                Button("Remove from Library", systemImage: "trash", role: .destructive) { confirmDelete = true }
                Divider()
                Button("Mark read", systemImage: "checkmark.circle") { store.setRead(entryIDs: selected, read: true) }
                Button("Mark unread", systemImage: "circle") { store.setRead(entryIDs: selected, read: false) }
                Divider()
                Button("Edit Categories", systemImage: "folder") { showBatchCategories = true }
                Button("Edit Artist", systemImage: "person.2") { showBatchArtist = true }
                Menu("Change Status", systemImage: "bookmark") {
                    ForEach(MCPersonalStatus.allCases) { status in
                        Button(status.title) { updateStatus(status) }
                    }
                }
            } label: {
                Label("Actions (\(selected.count))", systemImage: "ellipsis.circle")
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
            }
            .disabled(selected.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func updateStatus(_ status: MCPersonalStatus) {
        store.perform { state in
            for id in selected {
                try state.library.editEntry(id) { $0.status = status }
            }
        }
    }

    private func columns(for size: CGSize) -> [GridItem] {
        let count = grid ? (size.width > size.height ? min(10, max(2, landscapeColumns)) : min(6, max(2, portraitColumns))) : 1
        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
    }

    @ViewBuilder private func collectionPage(values: [MCPersonalEntry], size: CGSize) -> some View {
        if values.isEmpty {
            let libraryIsEmpty = store.library.entries.isEmpty
            UnavailableView(libraryIsEmpty ? "Library Empty" : "No matches", systemImage: "books.vertical.fill",
                description: Text(libraryIsEmpty ? "Add a title from Browse." : "Try another search, group, or filter."))
        } else {
            ScrollView {
                LazyVGrid(columns: columns(for: size), alignment: .leading, spacing: grid ? 20 : 14) {
                    ForEach(values) { entry in
                        entryButton(entry)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical)
            }.mcRefreshable { await store.refresh() }
        }
    }

    private func entryButton(_ entry: MCPersonalEntry) -> some View {
        Button {
            if selecting { if !selected.insert(entry.id).inserted { selected.remove(entry.id) } }
            else { path.append(entry.id) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                entryLabel(entry)
                if showsFlatResults || readingMode, let parentPath = store.library.parentPath(of: entry) {
                    Text(parentPath).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).clipped()
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                if selecting {
                    Image(systemName: selected.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title2).symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .background(Circle().fill(Color.accentColor)).padding(8)
                }
            }
        }.buttonStyle(.plain)
        .accessibilityLabel("\(store.library.title(entry)), \(store.chapterCount(entryID: entry.id)) chapters, \(store.unreadCount(entryID: entry.id)) unread, \(entry.status.title)")
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            if readingMode {
                Button("Remove from Reading", systemImage: "minus.circle") { store.removeFromReading([entry.id]) }
            } else if !store.library.readingIDs.contains(entry.id) {
                Button("Add to Reading", systemImage: "book") { store.addToReading([entry.id]) }
            }
            Divider()
            Button("Mark read", systemImage: "checkmark.circle") { store.setRead(entryIDs: [entry.id], read: true) }
            Button("Mark unread", systemImage: "circle") { store.setRead(entryIDs: [entry.id], read: false) }
            if !readingMode {
                Divider()
                Button("Move into title", systemImage: "folder") { movingEntry = MCID(id: entry.id) }
                if entry.parentEntryID != nil {
                    Button("Move to library", systemImage: "arrow.up.left") {
                        store.perform { try $0.library.moveEntry(entry.id, into: nil) }
                    }
                }
                Button("Edit entry", systemImage: "pencil") { editingEntry = MCID(id: entry.id) }
                Button("Select entry", systemImage: "checkmark.circle") { selected.insert(entry.id); selecting = true }
                Button("Remove from library", systemImage: "trash", role: .destructive) {
                    selected = [entry.id]; confirmDelete = true
                }
            }
        }
    }

    private var groupMenu: some View {
        Menu {
            Picker("Group by", selection: $grouping) {
                ForEach(MCLibraryGrouping.allCases) { Text($0.title).tag($0) }
            }
        } label: {
            Image(systemName: grouping == .none ? "square.stack.3d.up" : "square.stack.3d.up.fill")
        }
        .accessibilityLabel(grouping == .none ? "Group library" : "Grouped by \(grouping.title)")
    }

    private var filterMenu: some View {
        Menu {
            Menu("Status", systemImage: "bookmark") {
                ForEach(MCPersonalStatus.allCases) { item in
                    Toggle(item.title, isOn: Binding(
                        get: { statuses.contains(item) },
                        set: { if $0 { statuses.insert(item) } else { statuses.remove(item) } }
                    ))
                }
            }
            Picker("Reading progress", selection: $progressFilter) {
                ForEach(MCLibraryProgressFilter.allCases) { Text($0.title).tag($0) }
            }
            if !availableArtists.isEmpty {
                Menu("Artist", systemImage: "person.crop.square") {
                    ForEach(availableArtists, id: \.self) { artist in
                        Toggle(artist, isOn: Binding(
                            get: { artists.contains(artist) },
                            set: { if $0 { artists.insert(artist) } else { artists.remove(artist) } }
                        ))
                    }
                }
            }
            if !availableTags.isEmpty {
                Menu("Tags", systemImage: "tag") {
                    ForEach(availableTags, id: \.self) { tag in
                        Toggle(tag, isOn: Binding(
                            get: { tags.contains(tag) },
                            set: { if $0 { tags.insert(tag) } else { tags.remove(tag) } }
                        ))
                    }
                }
            }
            if !availableSources.isEmpty {
                Menu("Source", systemImage: "globe") {
                    ForEach(availableSources, id: \.id) { source in
                        Toggle(source.name, isOn: Binding(
                            get: { sources.contains(source.id) },
                            set: { if $0 { sources.insert(source.id) } else { sources.remove(source.id) } }
                        ))
                    }
                }
            }
            if hasActiveFilters {
                Divider()
                Button("Clear filters", systemImage: "xmark.circle", role: .destructive) {
                    statuses.removeAll(); artists.removeAll(); tags.removeAll(); sources.removeAll(); progressFilter = .all
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                if hasActiveFilters {
                    Text("\(activeFilterCount)").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .frame(minWidth: 13, minHeight: 13).background(Color.accentColor, in: Circle()).offset(x: 5, y: -5)
                }
            }
        }
        .accessibilityLabel(hasActiveFilters ? "Library filters, \(activeFilterCount) active" : "Filter library")
    }

    @ViewBuilder private func entryLabel(_ entry: MCPersonalEntry) -> some View {
        if grid {
            VStack(alignment: .leading, spacing: 7) {
                MCEntryCover(entry: entry)
                    .aspectRatio(2/3, contentMode: .fit)
                    .overlay(alignment: .topTrailing) { unreadBadge(entry).padding(6) }
                    .overlay(alignment: .bottomLeading) {
                        if gridStyle == .compact {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.library.title(entry)).font(.caption.weight(.semibold)).lineLimit(2)
                                Text("\(store.chapterCount(entryID: entry.id)) chapters").font(.caption2).opacity(0.85).lineLimit(1)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.top, 28)
                            .padding(.bottom, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(LinearGradient(colors: [.clear, .black.opacity(0.88)], startPoint: .top, endPoint: .bottom))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: gridStyle == .clean ? 6 : 10))
                if gridStyle == .standard {
                    Text(store.library.title(entry)).font(.subheadline.weight(.semibold)).lineLimit(2, reservesSpace: true).frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(store.chapterCount(entryID: entry.id)) chapters · \(entry.status.title)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        } else {
            HStack(spacing: 14) {
                MCEntryCover(entry: entry).frame(width: 66, height: 99).clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) { unreadBadge(entry).padding(4) }
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.library.title(entry)).font(.headline).lineLimit(2)
                    Text(entry.status.title).font(.subheadline).foregroundStyle(.secondary)
                    Text("\(store.chapterCount(entryID: entry.id)) chapters · \(entry.links.count) sources").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder private func unreadBadge(_ entry: MCPersonalEntry) -> some View {
        let unread = store.unreadCount(entryID: entry.id)
        if unread > 0 && !selecting {
            Text("\(unread)").font(.caption2.bold()).foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.accentColor, in: Capsule())
                .accessibilityLabel("\(unread) unread chapters")
        }
    }
}

private struct MCLibraryGroupTabs: View {
    let pages: [MCLibraryGroupPage]
    let selected: String?
    let swipePosition: MCLibrarySwipePosition

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(pages) { page in
                        let active = (selected ?? pages.first?.id) == page.id
                        Button { swipePosition.requestedID = page.id } label: {
                            HStack(spacing: 6) {
                                Text(page.title).font(.subheadline.weight(.medium))
                                Text("\(page.entryIDs.count)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(active ? Color.accentColor : .secondary)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Color(uiColor: active ? .tertiarySystemFill : .secondarySystemFill), in: Capsule())
                            }
                            .foregroundStyle(active ? Color.accentColor : .secondary)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .id(page.id)
                        .accessibilityAddTraits(active ? .isSelected : [])
                        .anchorPreference(key: MCLibraryTabAnchors.self, value: .bounds) { [page.id: $0] }
                    }
                }
                .padding(.horizontal)
                .overlayPreferenceValue(MCLibraryTabAnchors.self) { anchors in
                    GeometryReader { geometry in
                        if !pages.isEmpty {
                            let progress = min(CGFloat(pages.count - 1), max(0, swipePosition.page))
                            let index = Int(progress)
                            let nextIndex = min(index + 1, pages.count - 1)
                            if let first = anchors[pages[index].id], let second = anchors[pages[nextIndex].id] {
                                let start = geometry[first]
                                let end = geometry[second]
                                let fraction = progress - CGFloat(index)
                                let width = start.width + (end.width - start.width) * fraction
                                let x = start.minX + (end.minX - start.minX) * fraction
                                Capsule().fill(Color.accentColor)
                                    .frame(width: width, height: 3)
                                    .position(x: x + width / 2, y: geometry.size.height - 1.5)
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .onChange(of: Int(swipePosition.page.rounded())) { _, index in
                guard pages.indices.contains(index) else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(pages[index].id, anchor: .center) }
            }
            .onChange(of: selected) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) } }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(alignment: .bottom) { Divider() }
    }
}

private struct MCReadingAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var search = ""
    @State private var selected = Set<UUID>()
    @State private var randomCount = 1

    private var available: [MCPersonalEntry] {
        let added = Set(store.library.readingIDs)
        return store.library.entries.filter { !added.contains($0.id) }
            .sorted { store.library.title($0).localizedStandardCompare(store.library.title($1)) == .orderedAscending }
    }

    private var matching: [MCPersonalEntry] {
        search.isEmpty ? available : available.filter { store.library.title($0).localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search your library", text: $search)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                Section {
                    Stepper(value: $randomCount, in: 1...max(1, available.count)) {
                        Label("Random entries", systemImage: "shuffle")
                        Text("\(min(randomCount, available.count)) of \(available.count) available")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .disabled(available.isEmpty)
                    Button("Add Random Entries") {
                        if store.addRandomToReading(count: min(randomCount, available.count)) { dismiss() }
                    }
                    .disabled(available.isEmpty)
                } header: {
                    Text("Surprise me")
                } footer: {
                    Text("Random picks include nested titles at every level that are not already in Reading.")
                }
                Section {
                    ForEach(matching) { entry in
                        Button {
                            if !selected.insert(entry.id).inserted { selected.remove(entry.id) }
                        } label: {
                            HStack(spacing: 12) {
                                MCEntryCover(entry: entry)
                                    .frame(width: 40, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(store.library.title(entry)).font(.body.weight(.medium))
                                        .foregroundStyle(.primary).lineLimit(2)
                                    if let path = store.library.parentPath(of: entry) {
                                        Text(path).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Text("\(store.chapterCount(entryID: entry.id)) chapters")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: selected.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(Color.accentColor)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(store.library.title(entry)), \(selected.contains(entry.id) ? "selected" : "not selected")")
                    }
                    if matching.isEmpty {
                        Text(available.isEmpty ? "All library entries are in Reading." : "No matching entries.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Choose from Library")
                } footer: {
                    Text("Tap one entry or select several, then add them together.")
                }
            }
            .navigationTitle("Add to Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selected.count)") {
                        if store.addToReading(selected) { dismiss() }
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .mcErrors(store)
        }
        .midokuAccent()
    }
}

private struct MCBatchCategoryEditor: View {
    let entryIDs: Set<UUID>
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var mode = MCBatchCategoryMode.add
    @State private var categories = Set<UUID>()
    @State private var showCategories = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Change", selection: $mode) {
                        ForEach(MCBatchCategoryMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Change")
                } footer: {
                    Text(mode == .add ? "Adds the selected categories without removing existing ones."
                        : mode == .replace ? "Replaces the categories on every selected entry."
                        : "Removes only the selected categories.")
                }

                Section("Categories") {
                    ForEach(store.snapshot.categories) { category in
                        Toggle(category.name, isOn: Binding(
                            get: { categories.contains(category.id) },
                            set: { if $0 { categories.insert(category.id) } else { categories.remove(category.id) } }
                        ))
                    }
                    Button("Manage Categories") { showCategories = true }
                }
            }
            .navigationTitle("Edit Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply() }
                        .disabled(mode != .replace && categories.isEmpty)
                }
            }
            .sheet(isPresented: $showCategories) { MCCategoriesView() }
            .mcErrors(store)
        }
        .midokuAccent()
    }

    private func apply() {
        let valid = categories.intersection(Set(store.snapshot.categories.map(\.id)))
        if store.perform({ state in
            for id in entryIDs {
                try state.library.editEntry(id) { entry in
                    switch mode {
                    case .add: entry.categoryIDs.formUnion(valid)
                    case .replace: entry.categoryIDs = valid
                    case .remove: entry.categoryIDs.subtract(valid)
                    }
                }
            }
        }) { dismiss() }
    }
}

private struct MCBatchArtistEditor: View {
    let entryIDs: Set<UUID>
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var artist = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Artist name", text: $artist)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Artist")
                } footer: {
                    Text("Leave blank to restore each entry’s artist from its source.")
                }
            }
            .navigationTitle("Edit Artist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply") { apply() } }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                let values = entryIDs.compactMap { id -> String? in
                    guard let entry = store.library.entry(id) else { return nil }
                    return entry.artistOverride
                        ?? store.library.listing(entry.primaryListingID)?.details.artists?.joined(separator: ", ")
                }
                if let value = values.first, values.allSatisfy({ $0 == value }) { artist = value }
            }
            .mcErrors(store)
        }
        .midokuAccent()
    }

    private func apply() {
        let value = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.perform({ state in
            for id in entryIDs {
                try state.library.editEntry(id) { $0.artistOverride = value.isEmpty ? nil : value }
            }
        }) { dismiss() }
    }
}

struct MCEntryCover: View {
    let entry: MCPersonalEntry
    var contentMode: ContentMode = .fill
    @State private var store = MCCollectionStore.shared
    var body: some View {
        GeometryReader { geometry in
            if let id = entry.coverID, let cover = store.library.covers.first(where: { $0.id == id }) {
                MCCustomCoverImage(cover: cover, size: geometry.size, contentMode: contentMode)
            } else if !entry.hidesCover, let listing = store.library.listing(entry.primaryListingID), let cover = listing.details.coverURL {
                SourceImageView(source: store.source(listing.identity.connectionID), imageUrl: cover.absoluteString,
                    width: geometry.size.width, height: geometry.size.height, contentMode: contentMode, placeholder: "MidokuCoverPlaceholder").clipped()
            } else {
                MCArtworkPlaceholder()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }
        }.clipped().contentShape(Rectangle()).accessibilityHidden(true)
    }
}

struct MCCollectionDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data = Data()
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

extension View {
    func mcErrors(_ store: MCCollectionStore) -> some View {
        alert("Library", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

struct MCImportCollectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var picking = false
    @State private var incoming: Data?
    @State private var count = 0
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Choose library backup") { picking = true }
                    if incoming != nil {
                        Text("\(count) entries ready to restore")
                        Text("This replaces this app’s library, including its categories and edits. Downloads and source installations are kept.").foregroundStyle(.secondary)
                        Button("Restore library", role: .destructive) {
                            guard let incoming else { return }
                            do { try store.restore(incoming); dismiss() } catch { store.error = error.localizedDescription }
                        }
                    }
                }
            }.navigationTitle("Import library").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .fileImporter(isPresented: $picking, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 128 * 1024 * 1024 else { throw MCLibraryFailure.invalid }
                        let data = try Data(contentsOf: url)
                        let snapshot = try JSONDecoder().decode(MCCollectionSnapshot.self, from: data)
                        try snapshot.validate(); count = snapshot.library.entries.count; incoming = data
                    } catch { store.error = error.localizedDescription }
                }.mcErrors(store)
        }
    }
}

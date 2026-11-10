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

/// Sections inside one library tab. Chosen separately for each tab.
private enum MCLibrarySubgrouping: String, CaseIterable, Identifiable {
    case none, progress, status

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "None"
        case .progress: "Read / Unread"
        case .status: "Status"
        }
    }
}

private struct MCLibrarySubgroup: Identifiable {
    let id: String
    let title: String
    let entries: [MCPersonalEntry]
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

/// A search and filter combination. Smart tabs save one; pinned searches are smart tabs too.
private struct MCLibraryFilter: Codable, Equatable {
    var query = ""
    var statuses: Set<String> = []
    var artists: Set<String> = []
    var tags: Set<String> = []
    var sources: Set<UUID> = []
    var progress = MCLibraryProgressFilter.all.rawValue
    var newChaptersOnly = false

    var isEmpty: Bool { self == MCLibraryFilter() }
    var queryOnly: Bool { !query.isEmpty && MCLibraryFilter(query: query) == self }
}

private struct MCSmartTab: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var filter: MCLibraryFilter
}

private enum MCLibraryPageKind: Equatable {
    /// A category, artist, tag, status or source bucket of top-level entries.
    case group
    /// The ordered Reading list, which may include nested titles.
    case reading
    /// A saved search and filters, matched across nested titles like a regular search.
    case smart(MCSmartTab)
    /// Every top-level entry, shown when special tabs exist without a grouping.
    case all
}

private struct MCLibraryGroupPage: Identifiable {
    let id: String
    let title: String
    let entryIDs: Set<UUID>
    var kind = MCLibraryPageKind.group
}

private struct MCLibraryPageKey: Equatable {
    let revision: Int
    let entryCount: Int
    let grouping: MCLibraryGrouping
    let showReading: Bool
    let tabs: Data
}

/// Not observed: a cache hit must not trigger another render.
private final class MCLibraryPageCache {
    var key: MCLibraryPageKey?
    var pages: [MCLibraryGroupPage] = []
}

private struct MCGroupingSelection: Identifiable {
    let id = UUID()
    let entryIDs: [UUID]
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
    @AppStorage("Midoku.librarySortByGroup.v1") private var savedSorts = Data()
    private func sort(in page: String?) -> MCLibrarySort {
        let values = (try? JSONDecoder().decode([String: String].self, from: savedSorts)) ?? [:]
        return values[page ?? "all"].flatMap(MCLibrarySort.init(rawValue:)) ?? .recentlyAdded
    }
    private var sortBinding: Binding<MCLibrarySort> {
        Binding(get: { sort(in: activeGroupPage) }, set: { value in
            var values = (try? JSONDecoder().decode([String: String].self, from: savedSorts)) ?? [:]
            values[activeGroupPage ?? "all"] = value.rawValue
            savedSorts = (try? JSONEncoder().encode(values)) ?? Data()
        })
    }
    @AppStorage("Midoku.librarySubgroupsByPage.v1") private var savedSubgroups = Data()
    @State private var collapsedSubgroups = Set<String>()
    private func subgrouping(in page: String?) -> MCLibrarySubgrouping {
        guard page != Self.readingPageID else { return .none }
        let values = (try? JSONDecoder().decode([String: String].self, from: savedSubgroups)) ?? [:]
        return values[page ?? "all"].flatMap(MCLibrarySubgrouping.init(rawValue:)) ?? .none
    }
    private func subgroupBinding(for page: String?) -> Binding<MCLibrarySubgrouping> {
        Binding(get: { subgrouping(in: page) }, set: { value in
            var values = (try? JSONDecoder().decode([String: String].self, from: savedSubgroups)) ?? [:]
            values[page ?? "all"] = value == .none ? nil : value.rawValue
            savedSubgroups = (try? JSONEncoder().encode(values)) ?? Data()
        })
    }
    /// Splits a tab's entries into sections, keeping the tab's sort order inside each.
    private func subgroups(_ values: [MCPersonalEntry], by grouping: MCLibrarySubgrouping) -> [MCLibrarySubgroup] {
        switch grouping {
        case .none:
            return []
        case .progress:
            var unread: [MCPersonalEntry] = [], read: [MCPersonalEntry] = [], empty: [MCPersonalEntry] = []
            for entry in values {
                if store.chapterCount(entryID: entry.id) == 0 { empty.append(entry) }
                else if store.unreadCount(entryID: entry.id) > 0 { unread.append(entry) }
                else { read.append(entry) }
            }
            return [
                MCLibrarySubgroup(id: "unread", title: "Unread", entries: unread),
                MCLibrarySubgroup(id: "read", title: "Read", entries: read),
                MCLibrarySubgroup(id: "empty", title: "No chapters", entries: empty)
            ].filter { !$0.entries.isEmpty }
        case .status:
            let buckets = Dictionary(grouping: values, by: \.status)
            let order: [MCPersonalStatus] = [.reading, .planned, .onHold, .completed, .dropped]
            return order.compactMap { status in
                guard let entries = buckets[status], !entries.isEmpty else { return nil }
                return MCLibrarySubgroup(id: status.rawValue, title: status.title, entries: entries)
            }
        }
    }
    @State private var categoryEntry: MCID?
    @State private var showCategories = false
    @State private var showBatchCategories = false
    @State private var showBatchArtist = false
    @State private var groupingSelection: MCGroupingSelection?
    @State private var selected = Set<UUID>()
    @State private var selecting = false
    @State private var confirmDelete = false
    @State private var editingEntry: MCID?
    @State private var movingEntry: MCID?
    @State private var showAddPreview = false
    @State private var showReadingAdd = false
    @State private var reader: MCReaderSheet?
    @State private var showBookmarks = false
    @State private var selectedBookmark: MCPanelBookmark?
    @State private var confirmResetReading = false
    @State private var pageCache = MCLibraryPageCache()
    @AppStorage("Midoku.showReadingTab") private var showReadingTab = true
    @AppStorage("Midoku.libraryShuffleButton") private var showShuffle = true
    @AppStorage("Midoku.librarySmartTabs.v1") private var smartTabData = Data()
    @State private var newChaptersOnly = false
    @State private var showDuplicates = false
    @State private var showStats = false
    @State private var pendingMerge: [UUID]?
    @State private var namingTab: MCSmartTab?
    @State private var tabName = ""
    @AppStorage("Midoku.collectionGrid") private var grid = true
    @AppStorage("Midoku.chapterGrid") private var chapterGrid = false
    @AppStorage("Appearance.libraryGridStyle") private var gridStyle = ChapterGridStyle.standard
    @AppStorage("Appearance.libraryPortraitColumns") private var portraitColumns = 3
    @AppStorage("Appearance.libraryLandscapeColumns") private var landscapeColumns = 5

    /// Top-level entries, or every matching entry while a search or filter is active.
    private var visibleEntries: [MCPersonalEntry] {
        sortedEntries(filteredEntries(currentFilter, flat: showsFlatResults), in: nil)
    }

    private var currentFilter: MCLibraryFilter {
        MCLibraryFilter(query: trimmedQuery, statuses: Set(statuses.map(\.rawValue)), artists: artists, tags: tags,
                        sources: sources, progress: progressFilter.rawValue, newChaptersOnly: newChaptersOnly)
    }

    private func apply(_ filter: MCLibraryFilter) {
        statuses = Set(filter.statuses.compactMap(MCPersonalStatus.init(rawValue:)))
        artists = filter.artists; tags = filter.tags; sources = filter.sources
        progressFilter = MCLibraryProgressFilter(rawValue: filter.progress) ?? .all
        newChaptersOnly = filter.newChaptersOnly
        query = filter.query
        searchVisible = !filter.query.isEmpty
    }

    private func filteredEntries(_ filter: MCLibraryFilter, flat: Bool) -> [MCPersonalEntry] {
        let statuses = Set(filter.statuses.compactMap(MCPersonalStatus.init(rawValue:)))
        let progress = MCLibraryProgressFilter(rawValue: filter.progress) ?? .all
        let profiled = !filter.query.isEmpty || !filter.artists.isEmpty || !filter.tags.isEmpty || !filter.sources.isEmpty
        let newChapters = filter.newChaptersOnly ? store.newChapterCounts : [:]
        return store.library.entries.filter { entry in
            guard entry.parentEntryID == nil || flat,
                  statuses.isEmpty || statuses.contains(entry.status),
                  !filter.newChaptersOnly || newChapters[entry.id] != nil else { return false }
            if profiled {
                let profile = store.searchProfile(entry)
                guard filter.query.isEmpty || profile.text.localizedCaseInsensitiveContains(filter.query),
                      filter.artists.isEmpty || !filter.artists.isDisjoint(with: profile.artists),
                      filter.tags.isEmpty || !filter.tags.isDisjoint(with: profile.tags),
                      filter.sources.isEmpty || !filter.sources.isDisjoint(with: profile.sourceIDs) else { return false }
            }
            return matchesProgress(entry, progress)
        }
    }

    /// The entries one library tab shows. Reading keeps its own order.
    private func entries(for page: MCLibraryGroupPage) -> [MCPersonalEntry] {
        switch page.kind {
        case .reading: store.readingEntries
        case .smart(let tab): sortedEntries(filteredEntries(tab.filter, flat: true), in: page.id)
        case .all: sortedEntries(store.library.rootEntries, in: page.id)
        case .group: sortedEntries(store.library.rootEntries.filter { page.entryIDs.contains($0.id) }, in: page.id)
        }
    }

    private var activeEntries: [MCPersonalEntry] {
        guard let id = activeGroupPage, let page = libraryPages.first(where: { $0.id == id }) else { return visibleEntries }
        return entries(for: page)
    }

    private static let readingPageID = "reading"

    private var smartTabs: [MCSmartTab] {
        (try? JSONDecoder().decode([MCSmartTab].self, from: smartTabData)) ?? []
    }

    private func setSmartTabs(_ values: [MCSmartTab]) {
        smartTabData = (try? JSONEncoder().encode(values)) ?? Data()
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var savedCurrentFilter: MCSmartTab? {
        let filter = currentFilter
        return smartTabs.first { $0.filter == filter }
    }

    /// Saves the current search and filters as a tab, then shows that tab.
    private func saveSmartTab(name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !currentFilter.isEmpty else { return }
        let tab = savedCurrentFilter ?? MCSmartTab(name: name, filter: currentFilter)
        if savedCurrentFilter == nil { setSmartTabs(smartTabs + [tab]) }
        apply(MCLibraryFilter())
        searchFocused = false
        groupPage = "smart:\(tab.id)"
        swipePosition.requestedID = "smart:\(tab.id)"
    }

    private func removeSmartTab(_ id: UUID) {
        setSmartTabs(smartTabs.filter { $0.id != id })
    }

    private func renameSmartTab(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        setSmartTabs(smartTabs.map { tab in
            var tab = tab
            if tab.id == id { tab.name = name }
            return tab
        })
    }

    /// Reading and pinned searches lead the grouped tabs, so they are one swipe away.
    /// Rebuilt only when the library, grouping or pinned tabs change, not on every render.
    private var libraryPages: [MCLibraryGroupPage] {
        let key = MCLibraryPageKey(revision: store.revision, entryCount: store.library.entries.count,
                                   grouping: grouping, showReading: showReadingTab, tabs: smartTabData)
        if pageCache.key == key { return pageCache.pages }
        let pages = buildLibraryPages()
        pageCache.key = key
        pageCache.pages = pages
        return pages
    }

    private func buildLibraryPages() -> [MCLibraryGroupPage] {
        var pages: [MCLibraryGroupPage] = []
        if showReadingTab {
            pages.append(.init(id: Self.readingPageID, title: "Reading", entryIDs: Set(store.library.readingIDs), kind: .reading))
        }
        for tab in smartTabs {
            pages.append(.init(id: "smart:\(tab.id)", title: tab.name,
                               entryIDs: Set(filteredEntries(tab.filter, flat: true).map(\.id)), kind: .smart(tab)))
        }
        let groups = grouping == .none ? [] : groupPages
        if groups.isEmpty {
            if !pages.isEmpty {
                pages.append(.init(id: "all", title: "All", entryIDs: Set(store.library.rootEntries.map(\.id)), kind: .all))
            }
        } else {
            pages += groups
        }
        return pages
    }

    private func sortedEntries(_ values: [MCPersonalEntry], in page: String?) -> [MCPersonalEntry] {
        values.sorted { lhs, rhs in
            switch sort(in: page) {
            case .title: store.library.title(lhs).localizedStandardCompare(store.library.title(rhs)) == .orderedAscending
            case .recentlyRead: (lhs.lastReadAt ?? .distantPast) > (rhs.lastReadAt ?? .distantPast)
            case .recentlyAdded: lhs.createdAt > rhs.createdAt
            case .recentlyUpdated: lhs.updatedAt > rhs.updatedAt
            }
        }
    }

    private var showsFlatResults: Bool { hasActiveFilters || !query.isEmpty }

    private var hasActiveFilters: Bool {
        !statuses.isEmpty || !artists.isEmpty || !tags.isEmpty || !sources.isEmpty || progressFilter != .all || newChaptersOnly
    }

    private var activeFilterCount: Int {
        statuses.count + artists.count + tags.count + sources.count + (progressFilter == .all ? 0 : 1) + (newChaptersOnly ? 1 : 0)
    }

    private var availableTags: [String] {
        Array(Set(store.library.entries.flatMap { entryTags($0) })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func artistNames(_ entry: MCPersonalEntry) -> [String] { store.searchProfile(entry).artists }

    private var availableArtists: [String] {
        Array(Set(store.library.entries.flatMap(artistNames)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var availableSources: [MCLibrarySourceOption] {
        let ids = Set(store.library.entries.flatMap { store.searchProfile($0).sourceIDs })
        return ids.map { MCLibrarySourceOption(id: $0, name: store.sourceName($0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func entryTags(_ entry: MCPersonalEntry) -> [String] { store.searchProfile(entry).tags }

    private func matchesProgress(_ entry: MCPersonalEntry, _ progressFilter: MCLibraryProgressFilter) -> Bool {
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
                // An author cleared in the editor stays cleared instead of falling back to the source.
                if let override = entry.authorOverride {
                    override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [override]
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
        guard !showsFlatResults else { return nil }
        let pages = libraryPages
        guard !pages.isEmpty else { return nil }
        return groupPage.flatMap { id in pages.contains { $0.id == id } ? id : nil } ?? pages.first?.id
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
            regularLibraryPage
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selecting {
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
                            Picker("Sort", selection: sortBinding) { ForEach(MCLibrarySort.allCases) { Text($0.title).tag($0) } }
                                .disabled(activeGroupPage == Self.readingPageID)
                            Picker(selection: subgroupBinding(for: activeGroupPage)) {
                                ForEach(MCLibrarySubgrouping.allCases) { Text($0.title).tag($0) }
                            } label: {
                                Label("Group in \(activePageTitle)", systemImage: "rectangle.3.group")
                            }
                            .pickerStyle(.menu)
                            .disabled(activeGroupPage == Self.readingPageID || showsFlatResults)
                            readingMenu
                            Toggle("Cover grid", isOn: $grid)
                            Toggle("Chapter grid", isOn: $chapterGrid)
                            Button("Categories", systemImage: "folder") { showCategories = true }
                            Button("Bookmarks", systemImage: "bookmark") { showBookmarks = true }
                            Button("Reading stats", systemImage: "chart.bar") { showStats = true }
                            Button("Find duplicates", systemImage: "square.on.square") { showDuplicates = true }
                            Toggle("Shuffle button", isOn: $showShuffle)
                            Button("Refresh library", systemImage: "arrow.clockwise") { Task { await store.refresh() } }.disabled(store.isRefreshing)
                        } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Library options")
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if selecting { selectionActions }
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
            .alert(namingTab.map { tab in smartTabs.contains { $0.id == tab.id } } == true ? "Rename tab" : "Save as tab",
                   isPresented: Binding(get: { namingTab != nil }, set: { if !$0 { namingTab = nil } })) {
                TextField("Name", text: $tabName)
                Button("Save") {
                    if let tab = namingTab, smartTabs.contains(where: { $0.id == tab.id }) { renameSmartTab(tab.id, to: tabName) }
                    else { saveSmartTab(name: tabName) }
                    namingTab = nil
                }
                Button("Cancel", role: .cancel) { namingTab = nil }
            } message: {
                Text("The tab keeps this search and these filters, and updates as your library changes.")
            }
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
            .sheet(isPresented: $showStats) { MCReadingStatsView() }
            .sheet(isPresented: $showDuplicates, onDismiss: {
                // Present the grouping editor once the finder has closed.
                if let ids = pendingMerge { pendingMerge = nil; groupingSelection = MCGroupingSelection(entryIDs: ids) }
            }) {
                MCDuplicateFinderView { pendingMerge = $0 }
            }
            .sheet(isPresented: $showBatchCategories) { MCBatchCategoryEditor(entryIDs: selected) }
            .sheet(isPresented: $showBatchArtist) { MCBatchArtistEditor(entryIDs: selected) }
            .sheet(item: $groupingSelection) { selection in
                MCEntryEditor(grouping: selection.entryIDs) { id in
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
                guard !showsFlatResults, let first = libraryPages.first?.id else { return }
                groupPage = first
                swipePosition.requestedID = first
            }
            .onChange(of: grouping) { _, _ in
                groupPage = libraryPages.first?.id
            }
            .onChange(of: libraryPages.map(\.id)) { _, values in
                guard !values.isEmpty else { groupPage = nil; return }
                if groupPage.map(values.contains) != true { groupPage = values.first }
            }
            .onChange(of: availableTags) { _, values in tags.formIntersection(values) }
            .onChange(of: availableArtists) { _, values in artists.formIntersection(values) }
            .onChange(of: availableSources.map(\.id)) { _, values in sources.formIntersection(values) }
            .onChange(of: store.library.entries.map(\.id)) { _, ids in selected.formIntersection(ids) }
            .onAppear {
                if groupPage == nil { groupPage = libraryPages.first?.id }
            }
            .task {
                #if DEBUG
                let args = ProcessInfo.processInfo.arguments
                if args.contains("--collection-preview") {
                    try? await Task.sleep(for: .milliseconds(750))
                    if args.contains("--reading-preview") {
                        if let id = MCCollectionPreview.entryID { store.addToReading([id]) }
                        showReadingTab = true
                        groupPage = Self.readingPageID
                        swipePosition.requestedID = Self.readingPageID
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
        .background { MCEntryCategoryPresenter(entry: $categoryEntry).frame(width: 0, height: 0) }
        .introspect(.navigationStack, on: .iOS(.v26, .v27)) { navigation in
            navigation.interactivePopGestureRecognizer?.isEnabled = true
            navigation.interactiveContentPopGestureRecognizer?.isEnabled = true
        }
        .midokuAccent()
    }

    private var regularLibraryPage: some View {
        Group {
            let pages = libraryPages
            VStack(spacing: 0) {
                if !pages.isEmpty && !showsFlatResults {
                    let newCounts = store.newChapterCounts
                    MCLibraryGroupTabs(pages: pages, selected: activeGroupPage, swipePosition: swipePosition,
                                       newCounts: Dictionary(uniqueKeysWithValues: pages.map { page in
                                           (page.id, page.entryIDs.reduce(0) { $0 + (newCounts[$1] == nil ? 0 : 1) })
                                       })) { page in
                        tabMenu(page)
                    }
                }
                if !trimmedQuery.isEmpty { pinSearchBar }
                GeometryReader { geometry in
                    if pages.isEmpty || showsFlatResults {
                        collectionPage(values: visibleEntries, size: geometry.size,
                                       pageID: showsFlatResults ? nil : "all", subgrouping: showsFlatResults ? .none : subgrouping(in: nil))
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 0) {
                                    ForEach(pages) { page in
                                        Group {
                                            if page.kind == .reading { readingPage(size: geometry.size) }
                                            else {
                                                collectionPage(values: entries(for: page), size: geometry.size, kind: page.kind,
                                                               pageID: page.id, subgrouping: subgrouping(in: page.id))
                                            }
                                        }
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
                                if let id = activeGroupPage, let index = pages.firstIndex(where: { $0.id == id }) {
                                    swipePosition.page = CGFloat(index)
                                    proxy.scrollTo(id, anchor: .leading)
                                }
                            }
                        }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !selecting { floatingActions }
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

    @ViewBuilder private func readingPage(size: CGSize) -> some View {
        if store.readingEntries.isEmpty {
            VStack(spacing: 12) {
                UnavailableView("Nothing in Reading", systemImage: "books.vertical",
                    description: Text("Add titles you want to read next. Hold any title in your library to add it."))
                Button("Add Entries", systemImage: "plus") { showReadingAdd = true }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns(for: size), alignment: .leading, spacing: grid ? 20 : 14) {
                    ForEach(store.readingEntries) { entry in entryButton(entry, kind: .reading) }
                }
                .padding(.horizontal).padding(.vertical)
            }
            .mcRefreshable { await store.refresh() }
        }
    }

    private var readingMenu: some View {
        Menu("Reading", systemImage: "book") {
            Toggle("Show Reading tab", isOn: $showReadingTab)
            Button("Add to Reading…", systemImage: "plus") { showReadingAdd = true }
            Button("Clear Reading", systemImage: "arrow.counterclockwise", role: .destructive) { confirmResetReading = true }
                .disabled(store.library.readingIDs.isEmpty)
        }
    }

    @ViewBuilder private func tabMenu(_ page: MCLibraryGroupPage) -> some View {
        switch page.kind {
        case .reading:
            Button("Add to Reading…", systemImage: "plus") { showReadingAdd = true }
            Button("Clear Reading", systemImage: "arrow.counterclockwise", role: .destructive) { confirmResetReading = true }
                .disabled(store.library.readingIDs.isEmpty)
            Divider()
            Button("Hide Reading tab", systemImage: "eye.slash") { showReadingTab = false }
        case .smart(let tab):
            Button("Rename…", systemImage: "pencil") {
                tabName = tab.name
                namingTab = tab
            }
            Button("Show search and filters", systemImage: "line.3.horizontal.decrease.circle") { apply(tab.filter) }
            Button(tab.filter.queryOnly ? "Unpin" : "Remove tab", systemImage: "pin.slash", role: .destructive) {
                removeSmartTab(tab.id)
            }
        case .group, .all:
            EmptyView()
        }
        if page.kind != .reading {
            Picker(selection: subgroupBinding(for: page.id)) {
                ForEach(MCLibrarySubgrouping.allCases) { Text($0.title).tag($0) }
            } label: {
                Label("Group in tab", systemImage: "rectangle.3.group")
            }
            .pickerStyle(.menu)
        }
    }

    private var pinSearchBar: some View {
        let saved = savedCurrentFilter
        return HStack {
            Button {
                if let saved { removeSmartTab(saved.id) } else { saveSmartTab(name: trimmedQuery) }
            } label: {
                Label(saved != nil ? "Unpin “\(trimmedQuery)”" : hasActiveFilters ? "Pin search and filters as a tab" : "Pin “\(trimmedQuery)” as a tab",
                      systemImage: saved != nil ? "pin.slash" : "pin")
                    .font(.subheadline.weight(.medium)).lineLimit(1)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            Spacer(minLength: 0)
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    @ViewBuilder private var floatingActions: some View {
        if showShuffle {
            shuffleButton.padding(.horizontal, 18).padding(.bottom, 16)
        }
    }

    private func continueReading(_ entry: MCPersonalEntry) {
        Task {
            guard let slotID = await store.resumeSlot(entryID: entry.id) else {
                store.error = "No chapters are available to read."
                return
            }
            do { reader = MCReaderSheet(sequence: try MCReaderSequence(entryID: entry.id, slotID: slotID)) }
            catch { store.error = error.localizedDescription }
        }
    }

    private var shuffleButton: some View {
        let isReading = activeGroupPage == Self.readingPageID
        return Button { openRandomEntry(from: activeEntries) } label: {
            Image(systemName: "shuffle").font(.title3.weight(.semibold))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(isReading ? "Open random Reading entry; hold for entire library" : "Open random entry from this tab; hold for entire library")
        .disabled(store.library.entries.isEmpty)
        .highPriorityGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            openRandomEntry(from: store.library.entries)
        })
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
            let visibleIDs = Set(activeEntries.map(\.id))
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
                    let visible = visibleEntries.map(\.id).filter { selected.contains($0) }
                    let visibleIDs = Set(visible)
                    groupingSelection = MCGroupingSelection(entryIDs: visible + store.library.entries.map(\.id).filter { selected.contains($0) && !visibleIDs.contains($0) })
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

    @ViewBuilder private func collectionPage(values: [MCPersonalEntry], size: CGSize, kind: MCLibraryPageKind? = nil,
                                             pageID: String? = nil, subgrouping: MCLibrarySubgrouping = .none) -> some View {
        if values.isEmpty {
            let libraryIsEmpty = store.library.entries.isEmpty
            UnavailableView(libraryIsEmpty ? "Library Empty" : "No matches", systemImage: "books.vertical.fill",
                description: Text(libraryIsEmpty ? "Add a title from Browse." : "Try another search, group, or filter."))
        } else {
            let sections = subgroups(values, by: subgrouping)
            ScrollView {
                if sections.isEmpty {
                    LazyVGrid(columns: columns(for: size), alignment: .leading, spacing: grid ? 20 : 14) {
                        ForEach(values) { entry in
                            entryButton(entry, kind: kind)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical)
                } else {
                    LazyVGrid(columns: columns(for: size), alignment: .leading, spacing: grid ? 20 : 14, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections) { section in
                            let key = "\(pageID ?? "all")|\(subgrouping.rawValue)|\(section.id)"
                            let collapsed = collapsedSubgroups.contains(key)
                            Section {
                                if !collapsed {
                                    ForEach(section.entries) { entry in
                                        entryButton(entry, kind: kind)
                                    }
                                }
                            } header: {
                                subgroupHeader(section, collapsed: collapsed) {
                                    withAnimation(.snappy) {
                                        if collapsed { collapsedSubgroups.remove(key) } else { collapsedSubgroups.insert(key) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }.mcRefreshable { await store.refresh() }
        }
    }

    private func subgroupHeader(_ section: MCLibrarySubgroup, collapsed: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Text(section.title).font(.headline).foregroundStyle(.primary)
                Text("\(section.entries.count)").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Image(systemName: "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(uiColor: .systemBackground))
        .accessibilityLabel("\(section.title), \(section.entries.count)")
        .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
    }

    private var activePageTitle: String {
        guard let id = activeGroupPage else { return "All" }
        return libraryPages.first { $0.id == id }?.title ?? "All"
    }

    private func entryButton(_ entry: MCPersonalEntry, kind: MCLibraryPageKind? = nil) -> some View {
        let inReading = kind == .reading
        let showsPath: Bool = switch kind {
        case .reading?, .smart?: true
        default: showsFlatResults
        }
        return Button {
            if selecting { if !selected.insert(entry.id).inserted { selected.remove(entry.id) } }
            else { path.append(entry.id) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                entryLabel(entry)
                if showsPath, let parentPath = store.library.parentPath(of: entry) {
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
            if store.chapterCount(entryID: entry.id) > 0 {
                Button(entry.lastReadAt == nil ? "Start reading" : "Continue reading", systemImage: "book.pages") { continueReading(entry) }
                Divider()
            }
            if store.library.readingIDs.contains(entry.id) {
                Button("Remove from Reading", systemImage: "minus.circle") { store.removeFromReading([entry.id]) }
            } else {
                Button("Add to Reading", systemImage: "book") { store.addToReading([entry.id]) }
            }
            Divider()
            Button("Mark read", systemImage: "checkmark.circle") { store.setRead(entryIDs: [entry.id], read: true) }
            Button("Mark unread", systemImage: "circle") { store.setRead(entryIDs: [entry.id], read: false) }
            if !inReading {
                Divider()
                Button("Add to entry", systemImage: "text.badge.plus") { movingEntry = MCID(id: entry.id) }
                if entry.parentEntryID != nil {
                    Button("Move to library", systemImage: "arrow.up.left") {
                        store.perform { try $0.library.moveEntry(entry.id, into: nil) }
                    }
                }
                Button("Edit entry", systemImage: "pencil") { editingEntry = MCID(id: entry.id) }
                Button("Edit category", systemImage: "folder") { categoryEntry = MCID(id: entry.id) }
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
            Toggle("New chapters", systemImage: "sparkles", isOn: $newChaptersOnly)
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
            if hasActiveFilters || !trimmedQuery.isEmpty {
                Divider()
                if let saved = savedCurrentFilter {
                    Label("Saved as “\(saved.name)”", systemImage: "checkmark")
                } else {
                    Button("Save as tab…", systemImage: "plus.rectangle.on.rectangle") {
                        tabName = trimmedQuery.isEmpty ? "Filtered" : trimmedQuery
                        namingTab = MCSmartTab(name: "", filter: currentFilter)
                    }
                }
            }
            if hasActiveFilters {
                Button("Clear filters", systemImage: "xmark.circle", role: .destructive) {
                    statuses.removeAll(); artists.removeAll(); tags.removeAll(); sources.removeAll(); progressFilter = .all
                    newChaptersOnly = false
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
                    .overlay(alignment: .topLeading) { newBadge(entry).padding(6) }
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

    @ViewBuilder private func newBadge(_ entry: MCPersonalEntry) -> some View {
        if !selecting, let count = store.newChapterCounts[entry.id] {
            Image(systemName: "sparkles")
                .font(.caption2.weight(.bold)).foregroundStyle(.white)
                .padding(4)
                .background(Color.orange, in: Circle())
                .accessibilityLabel("\(count) new chapters")
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

private struct MCLibraryGroupTabs<TabMenu: View>: View {
    let pages: [MCLibraryGroupPage]
    let selected: String?
    let swipePosition: MCLibrarySwipePosition
    /// Titles with unread new chapters on each tab.
    let newCounts: [String: Int]
    @ViewBuilder let menu: (MCLibraryGroupPage) -> TabMenu

    private func tabButton(_ page: MCLibraryGroupPage, active: Bool) -> some View {
        Button { swipePosition.requestedID = page.id } label: {
            HStack(spacing: 6) {
                switch page.kind {
                case .reading: Image(systemName: "book").font(.caption.weight(.semibold))
                case .smart(let tab): Image(systemName: tab.filter.queryOnly ? "pin.fill" : "line.3.horizontal.decrease")
                    .font(.caption2.weight(.semibold))
                case .group, .all: EmptyView()
                }
                Text(page.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text("\(page.entryIDs.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(active ? Color.accentColor : .secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color(uiColor: active ? .tertiarySystemFill : .secondarySystemFill), in: Capsule())
                if let new = newCounts[page.id], new > 0 {
                    Text("\(new) new")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.accentColor, in: Capsule())
                        .accessibilityLabel("\(new) titles with new chapters")
                }
            }
            .foregroundStyle(active ? Color.accentColor : .secondary)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(pages) { page in
                        let active = (selected ?? pages.first?.id) == page.id
                        tabButton(page, active: active).contextMenu { menu(page) }
                        .id(page.id)
                        .accessibilityLabel(page.kind == .group || page.kind == .all ? page.title
                            : page.kind == .reading ? "Reading" : "Saved tab, \(page.title)")
                        .accessibilityValue("\(page.entryIDs.count) entries")
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
    var singleEntry = false
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var mode = MCBatchCategoryMode.add
    @State private var categories = Set<UUID>()
    @State private var showCategories = false

    var body: some View {
        NavigationStack {
            Form {
                if !singleEntry { Section {
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
            .onAppear {
                if singleEntry, let id = entryIDs.first, let entry = store.library.entry(id) {
                    mode = .replace; categories = entry.categoryIDs
                }
            }
            .navigationTitle(singleEntry ? "Edit category" : "Edit Categories")
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
                    width: geometry.size.width, height: geometry.size.height, contentMode: contentMode, placeholder: "MidokuCoverPlaceholder",
                    cacheSourceKey: store.snapshot.connections.first { $0.id == listing.identity.connectionID }?.sourceKey,
                    persistent: true).clipped()
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

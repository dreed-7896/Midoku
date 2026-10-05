import AidokuRunner
import SafariServices
import SwiftUI

private struct MCWebPage: Identifiable {
    let id = UUID()
    let url: URL
}

private struct MCInAppWebView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

private struct MCEntryMigrationSheet: UIViewControllerRepresentable {
    let manga: AidokuRunner.Manga

    func makeUIViewController(context: Context) -> UINavigationController {
        SwiftUINavigationViewController(rootView: MigrateSelectDestinationView(
            selectedSeries: [manga],
            selectedSources: SourceManager.shared.store.source(for: manga.sourceKey).map { [$0.toInfo()] } ?? []
        ))
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}

private struct MCEntryMigrationTarget: Identifiable {
    let id = UUID()
    let manga: AidokuRunner.Manga
}

private struct MCEntryStatusEditor: View {
    let entryID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var status = MCPersonalStatus.planned
    @State private var categories = Set<UUID>()

    var body: some View {
        NavigationStack {
            Form {
                Section("Reading status") {
                    Picker("Status", selection: $status) {
                        ForEach(MCPersonalStatus.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("Categories") {
                    ForEach(store.snapshot.categories) { category in
                        Toggle(category.name, isOn: Binding(
                            get: { categories.contains(category.id) },
                            set: { if $0 { categories.insert(category.id) } else { categories.remove(category.id) } }
                        ))
                    }
                }
            }
            .navigationTitle("Status and categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if store.perform({ state in
                            let valid = categories.intersection(Set(state.categories.map(\.id)))
                            try state.library.editEntry(entryID) { entry in
                                entry.status = status
                                entry.categoryIDs = valid
                            }
                        }) { dismiss() }
                    }
                }
            }
            .onAppear {
                if let entry = store.library.entry(entryID) {
                    status = entry.status
                    categories = entry.categoryIDs
                }
            }
            .mcErrors(store)
        }
        .midokuAccent()
    }
}

struct MCEntryView: View {
    let entryID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var showEdit = false
    @State private var showAddNested = false
    @State private var showMove = false
    @State private var showCover = false
    @State private var showSources = false
    @State private var showRemovedChapters = false
    @State private var migrationTarget: MCEntryMigrationTarget?
    @State private var selected = Set<UUID>()
    @State private var selecting = false
    @State private var editingChapter: MCID?
    @State private var resettingChapter: MCID?
    @State private var reader: MCReaderSheet?
    @State private var showBookmarks = false
    @State private var selectedBookmark: MCPanelBookmark?
    @State private var showReorder = false
    @State private var showStatusEditor = false
    @State private var didLongPressSave = false
    @State private var webPage: MCWebPage?
    @State private var confirmRemove = false
    @State private var confirmResetThumbnails = false
    @State private var confirmRemoveChapters = false
    @State private var thumbnailRevision = 0
    @AppStorage("Midoku.chapterGrid") private var defaultChapterGrid = false
    @AppStorage("Appearance.chapterGridStyle") private var gridStyle = ChapterGridStyle.standard
    @AppStorage("Appearance.chapterPortraitColumns") private var portraitColumns = 3
    @AppStorage("Appearance.chapterLandscapeColumns") private var landscapeColumns = 5
    @State private var viewportSize = CGSize.zero
    private var entry: MCPersonalEntry? { store.library.entry(entryID) }
    private var grid: Bool { entry?.chapterGridOverride ?? defaultChapterGrid }
    private var chapterGridOverride: Binding<Bool?> {
        Binding(
            get: { entry?.chapterGridOverride },
            set: { value in
                store.perform { try $0.library.editEntry(entryID) { $0.chapterGridOverride = value } }
            }
        )
    }
    private var slots: [MCChapterSlot] {
        guard let entry else { return [] }
        let original = entry.descendingDisplay ? Array(entry.slots.reversed()) : entry.slots
        let positions = Dictionary(uniqueKeysWithValues: original.enumerated().map { ($1.id, $0) })
        let mode = entry.chapterSort ?? .custom
        guard mode != .custom else { return original }
        return original.sorted { lhs, rhs in
            let a = lhs.preferred, b = rhs.preferred
            let result: ComparisonResult
            switch mode {
            case .custom: result = .orderedSame
            case .numberAscending, .numberDescending:
                let first = a.flatMap { store.library.number($0) } ?? ""
                let second = b.flatMap { store.library.number($0) } ?? ""
                result = first.localizedStandardCompare(second)
            case .titleAscending, .titleDescending:
                result = (a.map { store.library.chapterDisplayTitle($0) } ?? "")
                    .localizedStandardCompare(b.map { store.library.chapterDisplayTitle($0) } ?? "")
            case .unreadFirst:
                if store.library.isRead(lhs) != store.library.isRead(rhs) { return !store.library.isRead(lhs) }
                result = .orderedSame
            }
            if result == .orderedSame { return (positions[lhs.id] ?? 0) < (positions[rhs.id] ?? 0) }
            return mode == .numberDescending || mode == .titleDescending ? result == .orderedDescending : result == .orderedAscending
        }
    }

    private var contents: [MCEntryContent] {
        guard let entry else { return [] }
        let original = store.library.contents(of: entry)
        if entry.chapterSort == nil || entry.chapterSort == .custom {
            return entry.descendingDisplay ? Array(original.reversed()) : original
        }
        // Display sorting changes chapter rows, never the persisted reading sequence.
        var sorted = slots.makeIterator()
        return original.map { item in
            if case .chapter = item, let slot = sorted.next() { return .chapter(slot.id) }
            return item
        }
    }

    var body: some View {
        Group {
            if let entry {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                        header(entry).padding(.horizontal)
                        Section {
                            if contents.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("No chapters yet.").foregroundStyle(.secondary)
                                }
                                .padding(.horizontal)
                            }
                            if grid {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
                                    count: viewportSize.width > viewportSize.height ? min(10, max(2, landscapeColumns)) : min(6, max(2, portraitColumns))), alignment: .leading, spacing: 18) {
                                    ForEach(contents) { contentRow($0, grid: true) }
                                }.padding(.horizontal)
                            } else {
                                ForEach(contents) { item in
                                    contentRow(item, grid: false).padding(.horizontal)
                                    Divider().padding(.leading, 76)
                                }
                            }
                        } header: { chapterActions }
                    }.padding(.vertical, 12)
                }
                .background(Color(uiColor: .systemBackground))
                .refreshable { await store.refresh(entryID: entryID) }
                .navigationTitle(store.library.title(entry)).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Edit entry", systemImage: "square.and.pencil") { showEdit = true }
                            Button("Add title", systemImage: "plus.rectangle.on.rectangle") { showAddNested = true }
                            Button("Move title", systemImage: "folder") { showMove = true }
                            if entry.parentEntryID != nil {
                                Button("Move to library", systemImage: "arrow.up.left") {
                                    store.perform { try $0.library.moveEntry(entryID, into: nil) }
                                }
                            }
                            if !entry.exclusions.isEmpty {
                                Button("Removed chapters", systemImage: "arrow.uturn.backward") { showRemovedChapters = true }
                            }
                            Divider()
                            Button("Sources", systemImage: "square.stack.3d.up") { showSources = true }
                            if store.snapshot.manga.contains(where: { $0.listingID == entry.primaryListingID }) {
                                Button("Migrate", systemImage: "arrow.triangle.branch") {
                                    migrateEntry(entry)
                                }
                            }
                            Button("Reset thumbnails", systemImage: "arrow.counterclockwise") { confirmResetThumbnails = true }
                                .disabled(entry.slots.isEmpty)
                            Button("Reorder", systemImage: "line.3.horizontal") { selecting = false; showReorder = true }
                            if entry.manualOrder && !contents.contains(where: { if case .title = $0 { return true }; return false }) {
                                Button("Sort by number", systemImage: "number") { store.perform { try $0.library.editEntry(entryID) { $0.manualOrder = false; $0.contentOrder = nil } } }
                            }
                            Divider()
                            Button("Remove title", systemImage: "trash", role: .destructive) { confirmRemove = true }
                        } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Entry options")
                    }
                }
            } else { ContentUnavailableView("Entry unavailable", systemImage: "book.closed") }
        }
        .sheet(isPresented: $showAddNested) { MCEntryPlacementView(mode: .addInside(entryID)) }
        .sheet(isPresented: $showMove) { MCEntryPlacementView(mode: .move(entryID)) }
        .sheet(isPresented: $showEdit) { MCEntryEditor(entryID: entryID) }
        .fullScreenCover(isPresented: $showCover) { if let entry { MCFullscreenCoverView(entry: entry) } }
        .sheet(isPresented: $showStatusEditor) { MCEntryStatusEditor(entryID: entryID) }
        .onChange(of: showStatusEditor) { _, value in if !value { didLongPressSave = false } }
        .sheet(item: $webPage) { MCInAppWebView(url: $0.url).ignoresSafeArea() }
        .sheet(isPresented: $showSources) { MCEntrySourcesView(entryID: entryID) }
        .sheet(isPresented: $showRemovedChapters) { MCRemovedChaptersView(entryID: entryID) }
        .sheet(item: $migrationTarget) { MCEntryMigrationSheet(manga: $0.manga) }
        .sheet(isPresented: $showReorder) { MCChapterOrderView(entryID: entryID) }
        .sheet(item: $editingChapter) { MCChapterEditor(entryID: entryID, slotID: $0.id) }
        .sheet(isPresented: $showBookmarks, onDismiss: {
            if let bookmark = selectedBookmark { selectedBookmark = nil; openBookmark(bookmark) }
        }) {
            MCPanelBookmarksView(titleKey: (store.library.ancestorIDs(of: entryID).last ?? entryID).uuidString) {
                selectedBookmark = $0
            }
        }
        .modifier(MCReaderPresentation(sheet: $reader))
        .confirmationDialog("Remove this entry from library?", isPresented: $confirmRemove) {
            if !store.library.descendantIDs(of: entryID).isEmpty {
                Button("Remove title, keep nested titles in library", role: .destructive) {
                    if store.removeEntries([entryID]) { dismiss() }
                }
                Button("Remove title and all nested titles", role: .destructive) {
                    if store.removeEntries([entryID], includingDescendants: true) { dismiss() }
                }
            } else {
                Button("Remove entry", role: .destructive) { if store.removeEntries([entryID]) { dismiss() } }
            }
        } message: { Text("Reading history and downloaded chapters are kept.") }
        .confirmationDialog("Reset all chapter thumbnails?", isPresented: $confirmResetThumbnails) {
            Button("Reset thumbnails", role: .destructive) { resetChapterThumbnails() }
        } message: { Text("Custom and generated thumbnails for this entry will be cleared. Chapter details and reading progress are kept.") }
        .confirmationDialog("Reset chapter edits?", isPresented: Binding(get: { resettingChapter != nil }, set: { if !$0 { resettingChapter = nil } }), presenting: resettingChapter) { item in
            Button("Reset edits", role: .destructive) { store.perform { try $0.library.resetChapterDetails(entryID: entryID, slotID: item.id) } }
        } message: { _ in Text("Restores the source title, number, volume and thumbnail.") }
        .confirmationDialog("Remove selected chapters?", isPresented: $confirmRemoveChapters) {
            Button("Remove chapters", role: .destructive) {
                if store.perform({ try $0.library.removeSlots(entryID: entryID, slotIDs: selected) }) { selected.removeAll(); selecting = false }
            }
        }
        .mcErrors(store)
        .midokuAccent()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewportSize = $0 }
        .onChange(of: slots.map(\.id)) { _, ids in selected.formIntersection(ids) }
        .task {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--collection-preview") { try? await Task.sleep(for: .milliseconds(750)) }
            if args.contains("--edit-preview") { showEdit = true }
            if args.contains("--chapter-selection-preview") { defaultChapterGrid = true; selecting = true; selected = Set(slots.prefix(2).map(\.id)) }
            #endif
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--reader-preview") || ProcessInfo.processInfo.arguments.contains("--reader-hidden-preview") {
                await MCCollectionPreview.installReaderSources()
                if let slot = slots.dropFirst().first { open(slot) }
            }
            #endif
        }
    }

    private func migrateEntry(_ entry: MCPersonalEntry) {
        guard let manga = store.snapshot.manga.first(where: { $0.listingID == entry.primaryListingID })?.manga else { return }
        migrationTarget = MCEntryMigrationTarget(manga: manga)
    }

    private var chapterActions: some View {
        VStack(spacing: 8) {
            if let entry { readingActions(entry) }
            HStack {
                Text(selecting ? "\(selected.count) selected" : "\(store.chapterCount(entryID: entryID)) chapters").font(.headline)
                Spacer()
                if store.isRefreshing { ProgressView() }
            }
            if selecting {
                HStack {
                    Button(selected.count == slots.count ? "Deselect all" : "Select all") {
                        selected = selected.count == slots.count ? [] : Set(slots.map(\.id))
                    }
                    Spacer()
                    Menu {
                        Button("Mark read", systemImage: "checkmark") { store.setRead(entryID: entryID, slotIDs: selected, read: true) }
                        Button("Mark unread", systemImage: "circle") { store.setRead(entryID: entryID, slotIDs: selected, read: false) }
                        Button("Remove chapters", systemImage: "trash", role: .destructive) { confirmRemoveChapters = true }
                    } label: { Label("Actions", systemImage: "ellipsis.circle") }.disabled(selected.isEmpty)
                }.font(.subheadline)
            }
        }.padding(.horizontal).padding(.vertical, 8).background(Color(uiColor: .systemBackground))
    }

    private func header(_ entry: MCPersonalEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                Button { showCover = true } label: {
                    MCEntryCover(entry: entry).frame(width: headerCoverWidth, height: headerCoverWidth * 1.5)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("View cover fullscreen")
                VStack(alignment: .leading, spacing: 8) {
                    let title = store.library.title(entry)
                    Text(title)
                        .font(.title3.bold())
                        .lineLimit(4)
                        .contentShape(Rectangle())
                        .gesture(copyOrSearchGesture(for: title))
                    let details = store.library.listing(entry.primaryListingID)?.details
                    let artist = entry.artistOverride ?? details?.artists?.joined(separator: ", ") ?? ""
                    if !artist.isEmpty {
                        Text(artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                            .gesture(copyOrSearchGesture(for: artist))
                    }
                    Text("\(entry.status.title) · \(entry.links.count) sources").font(.caption).foregroundStyle(.secondary)
                    if let sourceName = mainSourceName(entry) {
                        Label("Main source: \(sourceName)", systemImage: "globe")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    coverActions(entry)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if !store.library.description(entry).isEmpty {
                Text(store.library.description(entry)).font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            let tags = entryTags(entry)
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color(uiColor: .secondarySystemFill), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private func readingActions(_ entry: MCPersonalEntry) -> some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    guard let slotID = await store.resumeSlot(entryID: entryID),
                          let slot = store.library.flattenedChapters(entryID: entryID).first(where: { $0.slot.id == slotID })?.slot else { return }
                    open(slot)
                }
            } label: {
                Label(entry.lastReadAt != nil || store.unreadCount(entryID: entryID) < store.chapterCount(entryID: entryID) ? "Resume" : "Read",
                    systemImage: "book.pages").font(.subheadline.weight(.semibold))
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.white)
                    .frame(height: 44).padding(.horizontal, 12)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .opacity(store.chapterCount(entryID: entryID) == 0 ? 0.5 : 1)
            .disabled(store.chapterCount(entryID: entryID) == 0)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Button { selecting.toggle(); selected.removeAll() } label: {
                    entryActionIcon(selecting ? "checkmark.circle.fill" : "checkmark.circle", selected: selecting)
                }.accessibilityLabel(selecting ? "Done selecting" : "Select chapters")
                Button { showBookmarks = true } label: { entryActionIcon("bookmark") }
                    .accessibilityLabel("View bookmarked panels")
                Button { chapterGridOverride.wrappedValue = !grid } label: {
                    entryActionIcon(grid ? "list.bullet" : "square.grid.2x2")
                }.accessibilityLabel(grid ? "List view" : "Grid view")
                Menu {
                    Picker("Sort chapters", selection: Binding(
                        get: { self.entry?.chapterSort ?? .custom },
                        set: { value in store.perform { try $0.library.editEntry(entryID) { $0.chapterSort = value } } }
                    )) {
                        ForEach(MCChapterDisplaySort.allCases) { Text($0.title).tag($0) }
                    }
                    if self.entry?.chapterSort == nil || self.entry?.chapterSort == .custom {
                        Button("Reverse order", systemImage: "arrow.up.arrow.down") {
                            store.perform { try $0.library.editEntry(entryID) { $0.descendingDisplay.toggle() } }
                        }
                    }
                } label: { entryActionIcon("arrow.up.arrow.down") }
                    .accessibilityLabel("Sort chapters")
            }
            .buttonStyle(.plain)
            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        }
    }

    private func entryActionIcon(_ symbol: String, selected: Bool = false) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .frame(width: 40, height: 44)
            .contentShape(Rectangle())
    }

    private func coverActions(_ entry: MCPersonalEntry) -> some View {
        HStack(spacing: 4) {
            Button {
                if didLongPressSave { didLongPressSave = false } else { confirmRemove = true }
            } label: { coverActionIcon("bookmark.fill") }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                didLongPressSave = true; showStatusEditor = true
            })
            .accessibilityLabel("Remove from library; hold to edit status and categories")
            Button { Task { await store.refresh(entryID: entryID) } } label: { coverActionIcon("arrow.clockwise") }
                .disabled(store.isRefreshing).accessibilityLabel("Refresh entry")
            if let url = entryWebURL(entry) {
                Button { webPage = MCWebPage(url: url) } label: { coverActionIcon("safari") }
                    .accessibilityLabel("View original source")
            }
        }.buttonStyle(.plain)
    }

    private func coverActionIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 36, height: 32)
            .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 9))
            .frame(width: 44, height: 44).contentShape(Rectangle())
    }

    private var headerCoverWidth: CGFloat {
        let count = viewportSize.width > viewportSize.height ? min(10, max(2, landscapeColumns)) : min(6, max(2, portraitColumns))
        return max(88, (viewportSize.width - 32 - CGFloat(count - 1) * 12) / CGFloat(count))
    }

    private func entryWebURL(_ entry: MCPersonalEntry) -> URL? {
        let listingID = entry.primaryListingID ?? entry.links.first?.listingID
        guard let url = store.library.listing(listingID)?.details.webURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func chapterWebURL(_ slot: MCChapterSlot) -> URL? {
        guard let variant = slot.preferred, let chapter = store.library.chapter(variant.chapterID),
              let url = store.physical(chapter.identity)?.chapter.url,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func entryTags(_ entry: MCPersonalEntry) -> [String] {
        var seen = Set<String>()
        let listingIDs = [entry.primaryListingID].compactMap { $0 } + entry.links.map(\.listingID)
        return listingIDs.compactMap { store.library.listing($0)?.details.tags }.flatMap { $0 }.filter { tag in
            let key = tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return seen.insert(key).inserted
        }
    }

    private func mainSourceName(_ entry: MCPersonalEntry) -> String? {
        let listingID = entry.primaryListingID ?? entry.links.first?.listingID
        guard let listing = store.library.listing(listingID) else { return nil }
        return store.sourceName(listing.identity.connectionID)
    }

    @ViewBuilder private func contentRow(_ item: MCEntryContent, grid: Bool) -> some View {
        switch item {
        case .chapter(let id):
            if let slot = entry?.slots.first(where: { $0.id == id }) { chapterRow(slot, grid: grid) }
        case .title(let id):
            if let child = store.library.entry(id) {
                NavigationLink(destination: MCEntryView(entryID: id)) {
                    nestedTitleLabel(child, grid: grid)
                }
                .buttonStyle(.plain)
                .disabled(selecting)
                .contextMenu {
                    Button("Mark read", systemImage: "checkmark.circle") { store.setRead(entryIDs: [id], read: true) }
                    Button("Mark unread", systemImage: "circle") { store.setRead(entryIDs: [id], read: false) }
                    Button("Move to library", systemImage: "arrow.up.left") {
                        store.perform { try $0.library.moveEntry(id, into: nil) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func nestedTitleLabel(_ child: MCPersonalEntry, grid: Bool) -> some View {
        if grid {
            VStack(alignment: .leading, spacing: 6) {
                MCEntryCover(entry: child).aspectRatio(2/3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "books.vertical.fill").font(.caption).foregroundStyle(.white)
                            .padding(7).background(.black.opacity(0.65), in: Circle()).padding(6)
                    }
                Label(store.library.title(child), systemImage: "books.vertical").font(.caption.weight(.semibold)).lineLimit(2)
                Text("\(store.chapterCount(entryID: child.id)) chapters · \(store.unreadCount(entryID: child.id)) unread")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 12) {
                MCEntryCover(entry: child).frame(width: 48, height: 72).clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 4) {
                    Label(store.library.title(child), systemImage: "books.vertical").font(.subheadline.weight(.medium)).lineLimit(2)
                    Text("\(store.chapterCount(entryID: child.id)) chapters · \(store.unreadCount(entryID: child.id)) unread")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func chapterRow(_ slot: MCChapterSlot, grid: Bool) -> some View {
        Button {
            if selecting { if !selected.insert(slot.id).inserted { selected.remove(slot.id) } }
            else { open(slot) }
        } label: {
            chapterLabel(slot, grid: grid).frame(maxWidth: .infinity, alignment: .leading).clipped()
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 8))
        .contextMenu {

                Button("Read chapter", systemImage: "book") { open(slot) }
                Button("View panels", systemImage: "square.grid.3x3") { open(slot, showPanels: true) }
                if let url = chapterWebURL(slot) {
                    Button("View source", systemImage: "globe") { webPage = MCWebPage(url: url) }
                }
                Button("Edit chapter", systemImage: "pencil") { editingChapter = MCID(id: slot.id) }
                Button("Reset edits", systemImage: "arrow.counterclockwise") { resettingChapter = MCID(id: slot.id) }
                Menu("Reading progress", systemImage: "checkmark.circle") {
                    Button("Mark read", systemImage: "checkmark.circle") { store.setRead(entryID: entryID, slotIDs: [slot.id], read: true) }
                    Button("Mark unread", systemImage: "circle") { store.setRead(entryID: entryID, slotIDs: [slot.id], read: false) }
                    Divider()
                    let next = store.library.nextSlotIDs(entryID: entryID, after: slot.id)
                    Button("Read all next", systemImage: "checkmark.circle.fill") { store.setRead(entryID: entryID, slotIDs: next, read: true) }.disabled(next.isEmpty)
                    Button("Unread all next", systemImage: "circle.dashed") { store.setRead(entryID: entryID, slotIDs: next, read: false) }.disabled(next.isEmpty)
                }
                Button("Reset thumbnail", systemImage: "photo.badge.arrow.down") { resetChapterThumbnails(slotIDs: [slot.id]) }
                Button("Download", systemImage: "arrow.down.circle") {
                    guard let variant = slot.preferred, let chapter = store.library.chapter(variant.chapterID), let physical = store.physical(chapter.identity) else { return }
                    Task { await DownloadManager.shared.download(manga: physical.manga, chapters: [physical.chapter]) }
                }
                if slot.variants.count > 1 {
                    Menu("Preferred source") {
                        ForEach(slot.variants) { variant in
                            let origin = store.library.chapter(variant.chapterID)
                            Button(origin.map { store.sourceName($0.identity.listing.connectionID) } ?? "Unavailable") {
                                store.perform { state in try state.library.editEntry(entryID) { entry in
                                    guard let i = entry.slots.firstIndex(where: { $0.id == slot.id }) else { throw MCLibraryFailure.missing }
                                    entry.slots[i].preferredID = variant.id; entry.slots[i].completionOverride = nil
                                } }
                            }
                        }
                    }
                }
                Button("Remove from entry", role: .destructive) { store.perform { try $0.library.removeSlots(entryID: entryID, slotIDs: [slot.id]) } }
        } preview: {
            chapterLabel(slot, grid: grid).padding(12).frame(width: 220).background(Color(uiColor: .systemBackground))
        }
    }

    @ViewBuilder private func chapterLabel(_ slot: MCChapterSlot, grid: Bool) -> some View {
        if grid {
            VStack(alignment: .leading, spacing: 6) {
                MCChapterThumbnail(variant: slot.preferred).aspectRatio(2/3, contentMode: .fit)
                    .id("\(slot.preferredID.uuidString)-\(thumbnailRevision)")
                    .overlay(alignment: .bottomLeading) {
                        if gridStyle == .compact, let variant = slot.preferred {
                            Text(store.library.chapterDisplayTitle(variant)).font(.caption.weight(.semibold)).lineLimit(1)
                                .foregroundStyle(.white).padding(.horizontal, 8).padding(.top, 24).padding(.bottom, 8)
                                .padding(.leading, store.library.isRead(slot) && !selecting ? 20 : 0)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(alignment: .bottomLeading) {
                        if store.library.isRead(slot) && !selecting { readMark.padding(6) }
                    }
                    .overlay(alignment: .topTrailing) { if selecting { selectionMark(slot).padding(6) } }
                if gridStyle == .standard { chapterText(slot, compact: true) }
            }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(slot.preferred.map { store.library.chapterDisplayTitle($0) } ?? "Chapter")
                .accessibilityAddTraits(selected.contains(slot.id) ? .isSelected : [])
        } else {
            HStack(spacing: 12) {
                if let entry {
                    MCChapterListArtwork(entry: entry, variant: slot.preferred)
                        .frame(width: 48, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .id("\(slot.preferredID.uuidString)-\(thumbnailRevision)")
                }
                chapterText(slot, compact: false)
                Spacer(minLength: 0)
                if selecting { selectionMark(slot) }
                else if store.library.isRead(slot) { Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary) }
            }.opacity(store.library.isRead(slot) && !selecting ? 0.65 : 1)
        }
    }

    private func selectionMark(_ slot: MCChapterSlot) -> some View {
        Image(systemName: selected.contains(slot.id) ? "checkmark.circle.fill" : "circle")
            .font(.title3).symbolRenderingMode(.palette).foregroundStyle(.white, Color.accentColor)
            .background(Circle().fill(Color.accentColor)).accessibilityLabel(selected.contains(slot.id) ? "Selected" : "Not selected")
    }

    private var readMark: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(.black.opacity(0.58), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.28), lineWidth: 0.5))
            .accessibilityLabel("Read")
    }

    private func chapterText(_ slot: MCChapterSlot, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let variant = slot.preferred, let chapter = store.library.chapter(variant.chapterID) {
                Text(store.library.chapterDisplayTitle(variant)).font(compact ? .caption.weight(.semibold) : .subheadline.weight(.medium)).lineLimit(1)
                let subtitle = variant.edits.title == nil && chapter.record.title != store.library.chapterDisplayTitle(variant) ? chapter.record.title : ""
                if compact || !subtitle.isEmpty {
                    Text(subtitle.isEmpty ? " " : subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(store.sourceName(chapter.identity.listing.connectionID) + (slot.variants.count > 1 ? " · \(slot.variants.count) alternatives" : ""))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func open(_ slot: MCChapterSlot, startPage: Int? = nil, showPanels: Bool = false) {
        do { reader = MCReaderSheet(sequence: try MCReaderSequence(entryID: entryID, slotID: slot.id),
                                    startPage: startPage, showPanels: showPanels) }
        catch { store.error = error.localizedDescription }
    }

    private func openBookmark(_ bookmark: MCPanelBookmark) {
        do { reader = try MCPanelBookmarks.reader(for: bookmark) }
        catch { store.error = "This bookmarked chapter is no longer available in your library." }
    }
    private func resetChapterThumbnails(slotIDs: Set<UUID>? = nil) {
        guard let entry else { return }
        let affected = entry.slots.filter { slotIDs == nil || slotIDs!.contains($0.id) }
        let chapterIDs = Set(affected.flatMap(\.variants).map(\.chapterID))
        if store.perform({ try $0.library.resetChapterThumbnails(entryID: entryID, slotIDs: slotIDs) }) {
            for chapterID in chapterIDs {
                if let chapter = store.library.chapter(chapterID),
                   let url = store.snapshot.chapters.first(where: { $0.chapterID == chapterID })?.chapter.thumbnail {
                    let sourceKey = store.snapshot.connections.first { $0.id == chapter.identity.listing.connectionID }?.sourceKey
                    MCArtworkCache.shared.reset(MCArtworkCache.key(url: url, sourceKey: sourceKey))
                }
            }
            MCThumbnailCache.shared.reset(chapterIDs: chapterIDs)
            thumbnailRevision += 1
        }
    }
    private func copy(_ value: String) {
        UIPasteboard.general.string = value
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func copyOrSearchGesture(for value: String) -> some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .exclusively(before: TapGesture())
            .onEnded { result in
                switch result {
                case .first:
                    search(value)
                case .second:
                    copy(value)
                }
            }
    }

    private func search(_ value: String) {
        (UIApplication.shared.firstKeyWindow?.rootViewController as? TabBarController)?.search(for: value)
    }
}


struct MCChapterOrderView: View {
    let entryID: UUID
    @State private var store = MCCollectionStore.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let entry = store.library.entry(entryID) {
                    let items = store.library.contents(of: entry)
                    ForEach(items) { item in
                        switch item {
                        case .chapter(let id):
                            let slot = entry.slots.first { $0.id == id }
                            Label(slot?.preferred.map { store.library.chapterDisplayTitle($0) } ?? "Chapter", systemImage: "doc.text")
                        case .title(let id):
                            if let child = store.library.entry(id) {
                                Label(store.library.title(child), systemImage: "books.vertical")
                            }
                        }
                    }.onMove { from, to in
                        var order = items
                        order.move(fromOffsets: from, toOffset: to)
                        store.perform { try $0.library.reorderContents(entryID: entryID, order: order) }
                    }
                }
            }.environment(\.editMode, .constant(.active))
                .navigationTitle("Chapters and titles").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .mcErrors(store)
        }
    }
}

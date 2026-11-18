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

struct MCEntryStatusEditor: View {
    let entryID: UUID
    var includeStatus = true
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var status = MCPersonalStatus.planned
    @State private var categories = Set<UUID>()
    @State private var showCategories = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                if includeStatus { Section(header: MDSettingsHeader(title: "Reading status")) {
                    Picker("Status", selection: $status) {
                        ForEach(MCPersonalStatus.allCases) { Text($0.title).tag($0) }
                    }
                } }
                Section(header: MDSettingsHeader(title: "Categories")) {
                    ForEach(store.snapshot.categories) { category in
                        Toggle(category.name, isOn: Binding(
                            get: { categories.contains(category.id) },
                            set: { if $0 { categories.insert(category.id) } else { categories.remove(category.id) } }
                        ))
                    }
                    Button("Manage Categories") { showCategories = true }
                }
            }
            .mdSheet(includeStatus ? "Status and categories" : "Edit category", onClose: { dismiss() }, secondary: MDSheetAction(title: "Cancel") { dismiss() }, primary: MDSheetAction(title: "Save") {
                if store.perform({ state in
                    let valid = categories.intersection(Set(state.categories.map(\.id)))
                    try state.library.editEntry(entryID) { entry in
                        if includeStatus { entry.status = status }
                        entry.categoryIDs = valid
                    }
                }) { dismiss() }
            })
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let entry = store.library.entry(entryID) {
                    status = entry.status
                    categories = entry.categoryIDs
                }
            }
            .sheet(isPresented: $showCategories) { MCCategoriesView() }
            .mcErrors(store)
        }
        .midokuAccent()
    }
}

/// A stable UIKit anchor avoids competing SwiftUI sheet presenters and waits for
/// a library context menu to finish dismissing before opening the category editor.
struct MCEntryCategoryPresenter: UIViewControllerRepresentable {
    @Binding var entry: MCID?
    var includeStatus = false

    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.request = entry
        controller.includeStatus = includeStatus
        controller.onDismiss = { entry = nil }
        controller.schedulePresentation()
    }

    final class Controller: UIViewController {
        var request: MCID?
        var includeStatus = false
        var onDismiss: () -> Void = {}
        private var scheduled = false
        private weak var editor: EditorController?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            schedulePresentation()
        }

        func schedulePresentation(attempt: Int = 0) {
            guard request != nil, editor == nil, !scheduled, attempt < 20 else { return }
            scheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                scheduled = false
                guard let request, viewIfLoaded?.window != nil, editor == nil else { return }
                let presenter = parent ?? self
                guard presenter.presentedViewController == nil, presenter.transitionCoordinator == nil else {
                    schedulePresentation(attempt: attempt + 1)
                    return
                }
                let editor = EditorController(rootView: MCEntryStatusEditor(entryID: request.id, includeStatus: includeStatus))
                editor.onDismiss = { [weak self] in
                    self?.editor = nil
                    self?.request = nil
                    self?.onDismiss()
                }
                self.editor = editor
                presenter.present(editor, animated: true)
            }
        }
    }

    final class EditorController: UIHostingController<MCEntryStatusEditor> {
        var onDismiss: () -> Void = {}
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if isBeingDismissed || presentingViewController == nil { onDismiss() }
        }
    }
}

struct MCEntryView: View {
    let entryID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var showEdit = false
    @State private var showOptions = false
    @State private var showAddNested = false
    @State private var movingEntry: MCID?
    @State private var showCover = false
    @State private var showSources = false
    @State private var showRemovedChapters = false
    @State private var migrationTarget: MCEntryMigrationTarget?
    @State private var selected = Set<UUID>()
    @State private var selecting = false
    @State private var editingChapter: MCID?
    @State private var splittingChapter: MCID?
    @State private var addingChapter: MCID?
    @State private var reader: MCReaderSheet?
    @State private var showBookmarks = false
    @State private var selectedBookmark: MCPanelBookmark?
    @State private var bookmarkedSlotIDs = MCPanelBookmarks.bookmarkedSlotIDs
    @State private var showReorder = false
    @State private var categoryEntry: MCID?
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
    @State private var rowsCache = MCEntryRowsCache()
    @State private var batchEditing: MCBatchSelection?
    @State private var chapterFilter = MCEntryChapterFilter.all
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

    /// Sorted rows and a slot table, rebuilt only after the library changes rather than
    /// on each render; rows then find their slot without scanning the whole entry.
    private var contents: [MCEntryContent] { cachedRows.contents }

    private var cachedRows: MCEntryRowsCache.Rows {
        let key = MCEntryRowsCache.Key(revision: store.revision, entryID: entryID, entry: entry?.updatedAt)
        if rowsCache.key == key, let rows = rowsCache.rows { return rows }
        let rows = MCEntryRowsCache.Rows(contents: computeContents(),
            slots: Dictionary((entry?.slots ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }))
        rowsCache.key = key
        rowsCache.rows = rows
        return rows
    }

    private func computeContents() -> [MCEntryContent] {
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

    /// `.entry__top`: flat glass squares over the backdrop (back, website, options) instead of the system bar.
    private func entryTopBar(_ entry: MCPersonalEntry) -> some View {
        HStack(spacing: 8) {
            MDIconButton(systemImage: "chevron.left", label: "Back", glass: true) { dismiss() }
            Spacer(minLength: 0)
            if let url = entryWebURL(entry) {
                MDIconButton(systemImage: "globe", label: "Open source website", glass: true) { webPage = MCWebPage(url: url) }
            }
            Button { showOptions = true } label: { MDIconBox(systemImage: "ellipsis", glass: true) }
                .buttonStyle(.plain)
                .accessibilityLabel("Entry options")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    /// The entry's options (`.menu` sheet).
    private func optionRows() -> [MDActionRow] {
        guard let entry else { return [] }
        var rows: [MDActionRow] = [
            MDActionRow(systemImage: "square.and.pencil", title: "Edit entry", detail: "Title, cover, description, details") { showEdit = true },
            MDActionRow(systemImage: "plus.rectangle.on.rectangle", title: "Add title", detail: "Group volumes or seasons inside") { showAddNested = true },
            MDActionRow(systemImage: "text.badge.plus", title: "Add to entry", detail: "Put this title inside another") { movingEntry = MCID(id: entryID) }
        ]
        if entry.parentEntryID != nil {
            rows.append(MDActionRow(systemImage: "arrow.up.left", title: "Move to library", detail: "Take it out of its parent title") {
                store.perform { try $0.library.moveEntry(entryID, into: nil) }
            })
        }
        if !entry.exclusions.isEmpty {
            rows.append(MDActionRow(systemImage: "arrow.uturn.backward", title: "Removed chapters",
                                    detail: "\(entry.exclusions.count) removed") { showRemovedChapters = true })
        }
        rows.append(MDActionRow(systemImage: "square.stack.3d.up", title: "Sources", detail: "\(entry.links.count) linked") { showSources = true })
        if store.snapshot.manga.contains(where: { $0.listingID == entry.primaryListingID }) {
            rows.append(MDActionRow(systemImage: "arrow.triangle.branch", title: "Migrate", detail: "Move to another source · progress comes along") {
                migrateEntry(entry)
            })
        }
        rows.append(MDActionRow(systemImage: "arrow.counterclockwise", title: "Reset thumbnails",
                                detail: "Clears picked and made chapter thumbnails", disabled: entry.slots.isEmpty) { confirmResetThumbnails = true })
        rows.append(MDActionRow(systemImage: "line.3.horizontal", title: "Reorder", detail: "Drag chapters and titles into your order") {
            selecting = false; showReorder = true
        })
        if entry.manualOrder && !contents.contains(where: { if case .title = $0 { return true }; return false }) {
            rows.append(MDActionRow(systemImage: "number", title: "Sort by number", detail: "Drop your personal order") {
                store.perform { try $0.library.editEntry(entryID) { $0.manualOrder = false; $0.contentOrder = nil } }
            })
        }
        rows.append(MDActionRow(systemImage: "trash", title: "Remove title", detail: "Delete it from your library", destructive: true) { confirmRemove = true })
        return rows
    }

    var body: some View {
        Group {
            if let entry {
                let next = nextSlot
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        entryTopBar(entry)
                        header(entry, next: next)
                        chapterActions.padding(.top, 28)
                        let visible = contents.filter(passes)
                        if visible.isEmpty {
                            emptyChapters.padding(.horizontal, 16).padding(.top, 12)
                        }
                        if grid {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
                                count: viewportSize.width > viewportSize.height ? min(10, max(2, landscapeColumns)) : min(6, max(2, portraitColumns))), alignment: .leading, spacing: 18) {
                                ForEach(visible) { contentRow($0, grid: true, current: next?.id) }
                            }.padding(.horizontal, 16).padding(.top, 16)
                        } else {
                            Color.clear.frame(height: 8)
                            ForEach(visible) { item in
                                contentRow(item, grid: false, current: next?.id).padding(.horizontal, 16)
                            }
                        }
                    }.padding(.bottom, 28)
                }
                .background(alignment: .top) {
                    MDEntryBackdrop { MCEntryCover(entry: entry) }.ignoresSafeArea(edges: .top)
                }
                .background(Color.mdBg)
                .toolbarBackground(.hidden, for: .navigationBar)
                .mcRefreshable { await store.refresh(entryID: entryID) }
                .navigationTitle("").navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                        } else { UnavailableView("Entry unavailable", systemImage: "book.closed") }
        }
        .sheet(isPresented: $showAddNested) { MCEntryPlacementView(mode: .addInside(entryID)) }
        .sheet(item: $movingEntry) { MCEntryPlacementView(mode: .move($0.id)) }
        .sheet(isPresented: $showEdit) { MCEntryEditor(entryID: entryID) }
        .mdActionSheet(isPresented: $showOptions, title: entry.map { store.library.title($0) } ?? "Options") { optionRows() }
        .fullScreenCover(isPresented: $showCover) { if let entry { MCFullscreenCoverView(entry: entry) } }
        .background { MCEntryCategoryPresenter(entry: $categoryEntry, includeStatus: true).frame(width: 0, height: 0) }
        .sheet(item: $webPage) { MCInAppWebView(url: $0.url).ignoresSafeArea() }
        .sheet(isPresented: $showSources) { MCEntrySourcesView(entryID: entryID) }
        .sheet(isPresented: $showRemovedChapters) { MCRemovedChaptersView(entryID: entryID) }
        .sheet(item: $migrationTarget) { MCEntryMigrationSheet(manga: $0.manga) }
        .sheet(isPresented: $showReorder) { MCChapterOrderView(entryID: entryID) }
        .sheet(item: $batchEditing) { selection in
            MCBatchChapterEditor(entryID: entryID, slotIDs: selection.slotIDs)
        }
        .sheet(item: $editingChapter) { item in
            MCChapterEditor(entryID: entryID, slotID: item.id, resetThumbnail: { resetChapterThumbnails(slotIDs: [item.id]) })
        }
        .sheet(item: $splittingChapter) { item in
            MCChapterSplitter(entryID: entryID, slotID: item.id)
        }
        .sheet(item: $addingChapter) { item in
            if let variant = entry?.slots.first(where: { $0.id == item.id })?.preferred,
               let chapter = store.library.chapter(variant.chapterID), let physical = store.physical(chapter.identity) {
                MCAddChapterToEntryView(manga: physical.manga, chapter: physical.chapter,
                    excludingEntryID: entryID, initialChapterName: store.library.chapterDisplayTitle(variant))
            }
        }
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
        .confirmationDialog("Remove selected chapters?", isPresented: $confirmRemoveChapters) {
            Button("Remove chapters", role: .destructive) {
                if store.perform({ try $0.library.removeSlots(entryID: entryID, slotIDs: selected) }) { selected.removeAll(); selecting = false }
            }
        }
        .mcErrors(store)
        .midokuAccent()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewportSize = $0 }
        .onChange(of: slots.map(\.id)) { _, ids in selected.formIntersection(ids) }
        .onAppear { bookmarkedSlotIDs = MCPanelBookmarks.bookmarkedSlotIDs }
        .onReceive(NotificationCenter.default.publisher(for: MCPanelBookmarks.changed)) { _ in
            bookmarkedSlotIDs = MCPanelBookmarks.bookmarkedSlotIDs
        }
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
        guard let manga = store.storedManga(listingID: entry.primaryListingID) else { return }
        migrationTarget = MCEntryMigrationTarget(manga: manga)
    }

    private var nextSlot: MCChapterSlot? {
        store.library.flattenedChapters(entryID: entryID).map(\.slot).first { !store.library.isRead($0) }
    }

    private func passes(_ item: MCEntryContent) -> Bool {
        guard case .chapter(let id) = item, let slot = cachedRows.slots[id] else { return chapterFilter == .all }
        switch chapterFilter {
            case .all: return true
            case .unread: return !store.library.isRead(slot)
            case .bookmarked: return bookmarkedSlotIDs.contains(slot.id)
        }
    }

    @ViewBuilder private var emptyChapters: some View {
        switch chapterFilter {
            case .all: MDEmpty(systemImage: "book", title: "No chapters yet", detail: Text("The source has not published any chapters for this title."))
            case .unread: MDEmpty(systemImage: "checkmark", title: "All caught up", detail: Text("Every chapter is read. New ones show up here."), tone: .done)
            case .bookmarked: MDEmpty(systemImage: "bookmark", title: "No bookmarks", detail: Text("Hold a chapter to bookmark it."))
        }
    }

    private var chapterActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            MDSectionHead(title: "Chapters", count: "\(store.chapterCount(entryID: entryID))") {
                if store.isRefreshing { MDSpinner(size: 14) }
                Button { chapterGridOverride.wrappedValue = !grid } label: { MDIconBox(systemImage: grid ? "list.bullet" : "square.grid.2x2") }
                    .accessibilityLabel(grid ? "Show chapters as a list" : "Show chapter thumbnails")
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
                } label: { MDIconBox(systemImage: "arrow.up.arrow.down") }
                    .accessibilityLabel("Sort chapters")
                Button { selecting.toggle(); selected.removeAll() } label: {
                    MDIconBox(systemImage: "checkmark.square", active: selecting)
                }.accessibilityLabel(selecting ? "Done selecting" : "Select chapters")
            }
            .buttonStyle(.plain)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MCEntryChapterFilter.allCases, id: \.self) { filter in
                        Button { chapterFilter = filter } label: {
                            MDChip(title: filter.title, count: count(for: filter), active: chapterFilter == filter, large: false)
                        }
                    }
                    Button { showBookmarks = true } label: { MDChip(title: "Page bookmarks", active: false, systemImage: "bookmark", large: false, dashed: true) }
                }.buttonStyle(.plain)
            }
            .scrollClipDisabled()
            if selecting {
                HStack {
                    Text("\(selected.count) selected").font(.mdMono(12, weight: .medium)).foregroundStyle(Color.mdText3)
                    Spacer()
                    Button(selected.count == slots.count ? "Deselect all" : "Select all") {
                        selected = selected.count == slots.count ? [] : Set(slots.map(\.id))
                    }
                    .buttonStyle(MDGhostButtonStyle())
                    Menu {
                        Button("Mark read", systemImage: "checkmark") { store.setRead(entryID: entryID, slotIDs: selected, read: true) }
                        Button("Mark unread", systemImage: "circle") { store.setRead(entryID: entryID, slotIDs: selected, read: false) }
                        Button("Download", systemImage: "arrow.down.to.line") { download(slotIDs: selected) }
                        Button("Rename & renumber…", systemImage: "textformat.123") {
                            batchEditing = MCBatchSelection(slotIDs: slots.map(\.id).filter { selected.contains($0) })
                        }
                        Button("Remove chapters", systemImage: "trash", role: .destructive) { confirmRemoveChapters = true }
                    } label: {
                        Text("Actions").font(.mdSystem(size: 13, weight: .semibold)).foregroundStyle(Color(uiColor: MDColor.onAccent))
                            .padding(.horizontal, 12).frame(height: 36).background(Color.mdAccent)
                    }
                    .disabled(selected.isEmpty)
                    .opacity(selected.isEmpty ? 0.5 : 1)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func count(for filter: MCEntryChapterFilter) -> Int? {
        switch filter {
            case .all: return nil
            case .unread: return store.unreadCount(entryID: entryID)
            case .bookmarked: return bookmarkedSlotIDs.intersection(Set(slots.map(\.id))).count
        }
    }

    private func download(slotIDs: Set<UUID>) {
        var byManga: [String: (manga: AidokuRunner.Manga, chapters: [AidokuRunner.Chapter])] = [:]
        for slot in slots where slotIDs.contains(slot.id) {
            guard let variant = slot.preferred, let chapter = store.library.chapter(variant.chapterID),
                  let physical = store.physical(chapter.identity) else { continue }
            let key = physical.manga.sourceKey + "\u{0}" + physical.manga.key
            byManga[key, default: (physical.manga, [])].chapters.append(physical.chapter)
        }
        for group in byManga.values {
            Task { await DownloadManager.shared.download(manga: group.manga, chapters: group.chapters) }
        }
    }

    /// The header names a single creator: the main artist, or the main author when no artist is known.
    private func mainCreator(_ entry: MCPersonalEntry) -> String {
        let details = store.library.listing(entry.primaryListingID)?.details
        func firstName(_ override: String?, _ names: [String]?) -> String? {
            let candidates = override.map { $0.split(separator: ",").map(String.init) } ?? names ?? []
            return candidates.lazy.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        }
        return firstName(entry.artistOverride, details?.artists) ?? firstName(entry.authorOverride, details?.authors) ?? ""
    }

    private func header(_ entry: MCPersonalEntry, next: MCChapterSlot?) -> some View {
        let title = store.library.title(entry)
        let total = store.chapterCount(entryID: entryID)
        let unread = store.unreadCount(entryID: entryID)
        let percent = total == 0 ? 0 : Int((Double(total - unread) / Double(total) * 100).rounded())
        return VStack(alignment: .leading, spacing: 0) {
            MDEntryHero(title: title, onCover: { showCover = true }, onTitleHold: { search(title) }) {
                MCEntryCover(entry: entry)
            } byline: {
                let artist = mainCreator(entry)
                HStack(spacing: 4) {
                    if !artist.isEmpty {
                        Text(artist).onTapGesture { copy(artist) }.onLongPressGesture { search(artist) }
                    }
                    if let parentID = entry.parentEntryID, let parent = store.library.entry(parentID) {
                        if !artist.isEmpty { Text("·") }
                        NavigationLink(destination: MCEntryView(entryID: parentID)) {
                            Text("in \(store.library.title(parent))").foregroundStyle(Color.mdAccent)
                        }.buttonStyle(.plain)
                    }
                }
            }

            readingActions(entry, next: next).padding(.horizontal, 16).padding(.top, 20)

            MDFactGrid(facts: [
                MDFact(label: "Chapters", value: "\(total)"),
                MDFact(label: "Unread", value: "\(unread)", valueColor: unread > 0 ? .mdAccent : .mdText),
                MDFact(label: "Read", value: "\(percent)%", progress: Double(percent) / 100),
                MDFact(label: "Source", value: mainSourceName(entry) ?? "—",
                       note: entry.links.count > 1 ? "+\(entry.links.count - 1) more" : nil, action: { showSources = true }),
                MDFact(label: "Status", value: publishingStatus(entry) ?? "Unknown", dot: publishingDot(entry)),
                MDFact(label: "Reading", value: entry.status.title,
                       note: entry.lastReadAt.map { "read " + $0.formatted(.relative(presentation: .named)) } ?? "never read",
                       action: { categoryEntry = MCID(id: entryID) })
            ])
            .padding(.horizontal, 16)
            .padding(.top, 16)

            let description = store.library.description(entry)
            let tags = entryTags(entry)
            if !description.isEmpty || !tags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !description.isEmpty { MDDescription(text: description) }
                    if !tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) { ForEach(tags, id: \.self) { MDTag(text: $0) } }
                        }
                        .scrollClipDisabled()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
        }
    }

    private func publishingDot(_ entry: MCPersonalEntry) -> Color? {
        let listingID = entry.primaryListingID ?? entry.links.first?.listingID
        switch store.storedManga(listingID: listingID)?.status {
            case .ongoing: return Color(uiColor: MDColor.mint)
            case .completed: return Color(red: 0.5, green: 0.65, blue: 1)
            case .cancelled, .hiatus: return Color(uiColor: MDColor.amber)
            case .unknown, nil: return nil
        }
    }

    private func readingActions(_ entry: MCPersonalEntry, next: MCChapterSlot?) -> some View {
        let total = store.chapterCount(entryID: entryID)
        let unread = store.unreadCount(entryID: entryID)
        let started = entry.lastReadAt != nil || unread < total
        let title = total == 0 ? "No chapters yet" : next == nil ? "All caught up" : started ? "Resume" : "Start reading"
        let subtitle = next.flatMap { $0.preferred }.map { store.library.chapterDisplayTitle($0) } ?? (total > 0 ? "\(total) chapters read" : nil)
        return HStack(spacing: 8) {
            MDResumeButton(title: title, subtitle: subtitle, systemImage: next == nil && total > 0 ? "checkmark" : "play.fill", disabled: total == 0) {
                Task {
                    guard let slotID = await store.resumeSlot(entryID: entryID),
                          let slot = store.library.flattenedChapters(entryID: entryID).first(where: { $0.slot.id == slotID })?.slot else { return }
                    open(slot)
                }
            }
            MDSquareAction(systemImage: "bookmark.fill", label: "Remove from library; hold to edit status and categories", active: true,
                           action: { confirmRemove = true }, onHold: { categoryEntry = MCID(id: entryID) })
            MDSquareAction(systemImage: "arrow.down.to.line", label: "Download unread chapters") {
                download(slotIDs: Set(slots.filter { !store.library.isRead($0) }.map(\.id)))
            }
            MDSquareAction(systemImage: "arrow.clockwise", label: "Refresh entry", spinning: store.isRefreshing) {
                Task { await store.refresh(entryID: entryID) }
            }
        }
    }

    private func entryActionIcon(_ symbol: String, selected: Bool = false) -> some View {
        Image(systemName: symbol)
            .font(.mdSystem(size: 17, weight: .medium))
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .frame(width: 40, height: 44)
            .contentShape(Rectangle())
    }

    private func coverActions(_ entry: MCPersonalEntry) -> some View {
        HStack(spacing: 4) {
            Button {
                confirmRemove = true
            } label: { coverActionIcon("bookmark.fill") }
            .highPriorityGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                categoryEntry = MCID(id: entryID)
            })
            .accessibilityAction(named: "Edit status and categories") { categoryEntry = MCID(id: entryID) }
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
        Image(systemName: symbol).font(.mdSystem(size: 17, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 36, height: 32)
            .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 0))
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

    /// The series' publishing status as the main source reports it, not the personal reading status.
    private func publishingStatus(_ entry: MCPersonalEntry) -> String? {
        let listingID = entry.primaryListingID ?? entry.links.first?.listingID
        switch store.storedManga(listingID: listingID)?.status {
            case .ongoing: return "Ongoing"
            case .completed: return "Completed"
            case .cancelled: return "Cancelled"
            case .hiatus: return "Hiatus"
            case .unknown, nil: return nil
        }
    }

    private func mainSourceName(_ entry: MCPersonalEntry) -> String? {
        let listingID = entry.primaryListingID ?? entry.links.first?.listingID
        guard let listing = store.library.listing(listingID) else { return nil }
        return store.sourceName(listing.identity.connectionID)
    }

    @ViewBuilder private func contentRow(_ item: MCEntryContent, grid: Bool, current: UUID? = nil) -> some View {
        switch item {
        case .chapter(let id):
            if let slot = cachedRows.slots[id] { chapterRow(slot, grid: grid, current: slot.id == current) }
        case .title(let id):
            if let child = store.library.entry(id) {
                NavigationLink(destination: MCEntryView(entryID: id)) {
                    nestedTitleLabel(child, grid: grid)
                }
                .buttonStyle(.plain)
                .disabled(selecting)
                .mdLongPressActions(store.library.title(child), enabled: !selecting) {
                    [
                        MDActionRow(systemImage: "text.badge.plus", title: "Add to entry") { movingEntry = MCID(id: id) },
                        MDActionRow(systemImage: "checkmark.circle", title: "Mark read") { store.setRead(entryIDs: [id], read: true) },
                        MDActionRow(systemImage: "circle", title: "Mark unread") { store.setRead(entryIDs: [id], read: false) },
                        MDActionRow(systemImage: "arrow.up.left", title: "Move to library") {
                            store.perform { try $0.library.moveEntry(id, into: nil) }
                        }
                    ]
                }
            }
        }
    }

    @ViewBuilder private func nestedTitleLabel(_ child: MCPersonalEntry, grid: Bool) -> some View {
        if grid {
            VStack(alignment: .leading, spacing: 6) {
                MCEntryCover(entry: child).aspectRatio(2/3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 0))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "books.vertical.fill").font(.mdCaption).foregroundStyle(.white)
                            .padding(7).background(.black.opacity(0.65), in: Circle()).padding(6)
                    }
                Label(store.library.title(child), systemImage: "books.vertical").font(.mdCaption.weight(.semibold)).lineLimit(2)
                Text("\(store.chapterCount(entryID: child.id)) chapters · \(store.unreadCount(entryID: child.id)) unread")
                    .font(.mdCaption2).foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 12) {
                MCEntryCover(entry: child).frame(width: 48, height: 72).clipShape(RoundedRectangle(cornerRadius: 0))
                VStack(alignment: .leading, spacing: 4) {
                    Label(store.library.title(child), systemImage: "books.vertical").font(.mdSubheadline.weight(.medium)).lineLimit(2)
                    Text("\(store.chapterCount(entryID: child.id)) chapters · \(store.unreadCount(entryID: child.id)) unread")
                        .font(.mdCaption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.mdCaption).foregroundStyle(.secondary)
            }
        }
    }

    private func chapterRow(_ slot: MCChapterSlot, grid: Bool, current: Bool = false) -> some View {
        Button {
            if selecting { if !selected.insert(slot.id).inserted { selected.remove(slot.id) } }
            else { open(slot) }
        } label: {
            chapterLabel(slot, grid: grid, current: current).frame(maxWidth: .infinity, alignment: .leading).clipped()
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .mdLongPressActions(slot.preferred.map { store.library.chapterDisplayTitle($0) } ?? "Chapter", enabled: !selecting) {
            chapterRows(slot)
        }
    }

    /// Long-press options for a chapter, as a web options sheet.
    private func chapterRows(_ slot: MCChapterSlot) -> [MDActionRow] {
        let bookmarked = bookmarkedSlotIDs.contains(slot.id)
        let next = store.library.nextSlotIDs(entryID: entryID, after: slot.id)
        var rows: [MDActionRow] = [
            MDActionRow(systemImage: "book", title: "Read chapter") { open(slot) },
            MDActionRow(systemImage: bookmarked ? "bookmark.slash" : "bookmark", title: bookmarked ? "Remove chapter bookmark" : "Bookmark chapter") {
                do {
                    try MCPanelBookmarks.toggleChapter(entryID: entryID, slotID: slot.id)
                    UISelectionFeedbackGenerator().selectionChanged()
                } catch { store.error = error.localizedDescription }
            },
            MDActionRow(systemImage: "square.grid.3x3", title: "View panels") { open(slot, showPanels: true) }
        ]
        if let url = chapterWebURL(slot) {
            rows.append(MDActionRow(systemImage: "globe", title: "View source", detail: url.host) { webPage = MCWebPage(url: url) })
        }
        rows.append(MDActionRow(systemImage: "pencil", title: "Edit chapter") { editingChapter = MCID(id: slot.id) })
        rows.append(MDActionRow(systemImage: "scissors", title: slot.preferred?.pageSelection?.ranges.isEmpty == false ? "Edit split" : "Split chapter",
                                disabled: slot.variants.count > 1) { splittingChapter = MCID(id: slot.id) })
        rows.append(MDActionRow(systemImage: "text.badge.plus", title: "Add to entry") { addingChapter = MCID(id: slot.id) })
        rows.append(MDActionRow(systemImage: "checkmark.circle", title: "Mark read") { store.setRead(entryID: entryID, slotIDs: [slot.id], read: true) })
        rows.append(MDActionRow(systemImage: "circle", title: "Mark unread") { store.setRead(entryID: entryID, slotIDs: [slot.id], read: false) })
        rows.append(MDActionRow(systemImage: "checkmark.circle.fill", title: "Read all next", detail: "\(next.count) chapters", disabled: next.isEmpty) {
            store.setRead(entryID: entryID, slotIDs: next, read: true)
        })
        rows.append(MDActionRow(systemImage: "circle.dashed", title: "Unread all next", detail: "\(next.count) chapters", disabled: next.isEmpty) {
            store.setRead(entryID: entryID, slotIDs: next, read: false)
        })
        rows.append(MDActionRow(systemImage: "arrow.down.circle", title: "Download") {
            guard let variant = slot.preferred, let chapter = store.library.chapter(variant.chapterID), let physical = store.physical(chapter.identity) else { return }
            Task { await DownloadManager.shared.download(manga: physical.manga, chapters: [physical.chapter]) }
        })
        if slot.variants.count > 1 {
            for variant in slot.variants {
                let origin = store.library.chapter(variant.chapterID)
                let name = origin.map { store.sourceName($0.identity.listing.connectionID) } ?? "Unavailable"
                rows.append(MDActionRow(systemImage: slot.preferredID == variant.id ? "checkmark" : "arrow.triangle.branch",
                                        title: name, detail: "Preferred source", keepsOpen: true) {
                    store.perform { state in try state.library.editEntry(entryID) { entry in
                        guard let i = entry.slots.firstIndex(where: { $0.id == slot.id }) else { throw MCLibraryFailure.missing }
                        entry.slots[i].preferredID = variant.id; entry.slots[i].completionOverride = nil
                    } }
                })
            }
        }
        rows.append(MDActionRow(systemImage: "trash", title: "Remove from entry", destructive: true) {
            store.perform { try $0.library.removeSlots(entryID: entryID, slotIDs: [slot.id]) }
        })
        return rows
    }
    }

    @ViewBuilder private func chapterLabel(_ slot: MCChapterSlot, grid: Bool, current: Bool = false) -> some View {
        if grid {
            VStack(alignment: .leading, spacing: 6) {
                MCChapterThumbnail(variant: slot.preferred).aspectRatio(2/3, contentMode: .fit)
                    .id("\(slot.preferredID.uuidString)-\(thumbnailRevision)")
                    .overlay(alignment: .bottomLeading) {
                        if gridStyle == .compact, let variant = slot.preferred {
                            Text(store.library.chapterDisplayTitle(variant)).font(.mdCaption.weight(.semibold)).lineLimit(1)
                                .foregroundStyle(.white).padding(.horizontal, 8).padding(.top, 24).padding(.bottom, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 0))
                    // the read mark sits top-right so it never covers the title along the bottom
                    .overlay(alignment: .topTrailing) {
                        if store.library.isRead(slot) && !selecting { readMark.padding(6) }
                    }
                    .overlay(alignment: .bottomTrailing) { if selecting { MDCheck(on: selected.contains(slot.id)).padding(6) } }
                    .overlay {
                        if current || selected.contains(slot.id) {
                            Rectangle().strokeBorder(selected.contains(slot.id) ? Color.mdText : Color.mdAccent, lineWidth: 2).padding(-4)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if bookmarkedSlotIDs.contains(slot.id) { bookmarkMark.padding(6) }
                    }
                if gridStyle == .standard { chapterText(slot, compact: true) }
            }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel((slot.preferred.map { store.library.chapterDisplayTitle($0) } ?? "Chapter")
                    + (bookmarkedSlotIDs.contains(slot.id) ? ", Bookmarked" : ""))
                .accessibilityAddTraits(selected.contains(slot.id) ? .isSelected : [])
        } else {
            let read = store.library.isRead(slot)
            let variant = slot.preferred
            let chapter = variant.flatMap { store.library.chapter($0.chapterID) }
            let label = variant.map { store.library.chapterDisplayTitle($0) } ?? "Chapter"
            let subtitle: String = {
                guard let variant, let chapter else { return "" }
                return variant.edits.title == nil && chapter.record.title != label ? chapter.record.title : ""
            }()
            let date = chapter.flatMap { store.chapterReleaseDate($0.id) }
            let isNew = !read && (date.map { $0 > Date.now.addingTimeInterval(-7 * 86_400) } ?? false)
            let meta = ([read ? "Read" : nil, subtitle.isEmpty ? nil : subtitle,
                         chapter.map { store.sourceName($0.identity.listing.connectionID) },
                         date?.formatted(.dateTime.day().month(.abbreviated))].compactMap { $0 }).joined(separator: " · ")
            MDChapterRow(label: label, meta: meta, read: read && !selecting, current: current, selected: selected.contains(slot.id)) {
                if isNew { MDRowBadge(text: "New") }
                if variant?.pageSelection?.ranges.isEmpty == false { MDRowBadge(text: "Part", glass: true) }
            } trailing: {
                if slot.variants.count > 1 {
                    HStack(spacing: 3) {
                        Image(systemName: "square.stack.3d.up").font(.system(size: 10, weight: .bold))
                        Text("\(slot.variants.count)").font(.mdMono(10, weight: .bold))
                    }
                    .padding(.horizontal, 5).frame(height: 18).background(Color.white.opacity(0.12))
                }
                if bookmarkedSlotIDs.contains(slot.id) { MDFlag(systemImage: "bookmark.fill", accent: true) }
                if selecting { MDCheck(on: selected.contains(slot.id)) }
            }
        }
    }

    private func selectionMark(_ slot: MCChapterSlot) -> some View {
        Image(systemName: selected.contains(slot.id) ? "checkmark.circle.fill" : "circle")
            .font(.mdTitle3).symbolRenderingMode(.palette).foregroundStyle(.white, Color.accentColor)
            .background(Circle().fill(Color.accentColor)).accessibilityLabel(selected.contains(slot.id) ? "Selected" : "Not selected")
    }

    /// `.badge--glass` "✓ Read" in the top-right corner of a thumbnail.
    private var readMark: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy))
            Text("Read").font(.mdMono(10, weight: .bold)).textCase(.uppercase)
        }
        .foregroundStyle(Color.mdText)
        .padding(.horizontal, 5)
        .frame(height: 18)
        .background(.black.opacity(0.6))
        .accessibilityLabel("Read")
    }

    private var bookmarkMark: some View {
        Image(systemName: "bookmark.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.mdAccent)
            .frame(width: 24, height: 24)
            .background(.black.opacity(0.6))
            .accessibilityLabel("Bookmarked chapter")
    }

    private func chapterText(_ slot: MCChapterSlot, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let variant = slot.preferred, let chapter = store.library.chapter(variant.chapterID) {
                Text(store.library.chapterDisplayTitle(variant)).font(.mdSystem(size: compact ? 13 : 15, weight: .semibold)).foregroundStyle(Color.mdText).lineLimit(1)
                let subtitle = variant.edits.title == nil && chapter.record.title != store.library.chapterDisplayTitle(variant) ? chapter.record.title : ""
                if compact || !subtitle.isEmpty {
                    Text(subtitle.isEmpty ? " " : subtitle).font(.mdCaption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(store.sourceName(chapter.identity.listing.connectionID) + (slot.variants.count > 1 ? " · \(slot.variants.count) alternatives" : ""))
                    .font(.mdCaption2).foregroundStyle(.secondary).lineLimit(1)
                if !compact, let date = store.chapterReleaseDate(chapter.id) {
                    Label {
                        Text(date, format: .dateTime.day().month(.abbreviated).year())
                    } icon: { Image(systemName: "calendar") }
                    .font(.mdCaption2).foregroundStyle(.secondary)
                    .accessibilityLabel("Released \(date.formatted(date: .abbreviated, time: .omitted))")
                }
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
                   let url = store.storedChapter(chapterID)?.thumbnail {
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
                .mdSheet("Chapters and titles", onClose: { dismiss() })
                .mcErrors(store)
        }
    }
}

/// Long text folded to a few lines, with More and Less to expand and collapse it.
/// The button only appears when the text is actually longer than the folded lines.
struct MCExpandableText: View {
    let text: String
    var lineLimit = 3
    @State private var expanded = false
    @State private var foldedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .lineLimit(expanded ? nil : lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .topLeading) {
                    // Hidden copies measure the folded and full heights at the same width.
                    ZStack(alignment: .topLeading) {
                        Text(text).lineLimit(lineLimit).fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { foldedHeight = $0 }
                        Text(text).fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                    }
                    .hidden()
                }
            if fullHeight > foldedHeight + 1 {
                Button(expanded ? "Less" : "More") {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                }
                .font(.mdSubheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel(expanded ? "Show less description" : "Show full description")
            }
        }
    }
}

/// Not observed: filling the cache during a render must not schedule another one.
final class MCEntryRowsCache {
    struct Key: Equatable {
        let revision: Int
        let entryID: UUID
        let entry: Date?
    }
    struct Rows {
        let contents: [MCEntryContent]
        let slots: [UUID: MCChapterSlot]
    }
    var key: Key?
    var rows: Rows?
}

struct MCBatchSelection: Identifiable {
    let id = UUID()
    let slotIDs: [UUID]
}

enum MCEntryChapterFilter: CaseIterable {
    case all, unread, bookmarked

    var title: String {
        switch self {
            case .all: "All"
            case .unread: "Unread"
            case .bookmarked: "Bookmarked"
        }
    }
}

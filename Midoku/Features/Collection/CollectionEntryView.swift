import AidokuRunner
import SwiftUI

struct MCEntryView: View {
    let entryID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var showEdit = false
    @State private var showSources = false
    @State private var showAddChapters = false
    @State private var showRemovedChapters = false
    @State private var selected = Set<UUID>()
    @State private var selecting = false
    @State private var editingChapter: MCID?
    @State private var resettingChapter: MCID?
    @State private var reader: MCReaderSheet?
    @State private var showReorder = false
    @State private var confirmRemove = false
    @State private var confirmReset = false
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
        return entry.descendingDisplay ? Array(entry.slots.reversed()) : entry.slots
    }

    var body: some View {
        Group {
            if let entry {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                        header(entry).padding(.horizontal)
                        Section {
                            if slots.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Add chapters from another library entry or from a source.").foregroundStyle(.secondary)
                                    Button("Add chapters from library", systemImage: "plus") { showAddChapters = true }
                                        .buttonStyle(.borderedProminent)
                                }
                                .padding(.horizontal)
                            }
                            if grid {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
                                    count: viewportSize.width > viewportSize.height ? min(10, max(2, landscapeColumns)) : min(6, max(2, portraitColumns))), alignment: .leading, spacing: 18) {
                                    ForEach(slots) { chapterRow($0, grid: true) }
                                }.padding(.horizontal)
                            } else {
                                ForEach(slots) { slot in
                                    chapterRow(slot, grid: false).padding(.horizontal)
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
                            Button("Add chapters from library", systemImage: "plus") { showAddChapters = true }
                            if !entry.exclusions.isEmpty {
                                Button("Removed chapters (\(entry.exclusions.count))", systemImage: "arrow.uturn.backward") { showRemovedChapters = true }
                            }
                            Button("Reset edits", systemImage: "arrow.counterclockwise") { confirmReset = true }
                            Button("Sources and alternatives", systemImage: "square.stack.3d.up") { showSources = true }
                            Picker("Chapter layout", selection: chapterGridOverride) {
                                Text("Use appearance setting").tag(Bool?.none)
                                Text("Grid").tag(Bool?.some(true))
                                Text("List").tag(Bool?.some(false))
                            }
                            Button("Reset chapter thumbnails", systemImage: "arrow.counterclockwise") { confirmResetThumbnails = true }
                                .disabled(entry.slots.isEmpty)
                            Button("Reorder chapters", systemImage: "line.3.horizontal") { selecting = false; showReorder = true }
                            if entry.manualOrder {
                                Button("Restore chapter-number order") { store.perform { try $0.library.editEntry(entryID) { $0.manualOrder = false } } }
                            }
                            Button("Refresh sources", systemImage: "arrow.clockwise") { Task { await store.refresh(entryID: entryID) } }.disabled(store.isRefreshing)
                            Divider()
                            Button("Remove from library", systemImage: "trash", role: .destructive) { confirmRemove = true }
                        } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Entry options")
                    }
                }
            } else { ContentUnavailableView("Entry unavailable", systemImage: "book.closed") }
        }
        .sheet(isPresented: $showEdit) { MCEntryEditor(entryID: entryID) }
        .sheet(isPresented: $showSources) { MCEntrySourcesView(entryID: entryID) }
        .sheet(isPresented: $showAddChapters) { MCAddExistingChaptersView(entryID: entryID) }
        .sheet(isPresented: $showRemovedChapters) { MCRemovedChaptersView(entryID: entryID) }
        .sheet(isPresented: $showReorder) { MCChapterOrderView(entryID: entryID) }
        .sheet(item: $editingChapter) { MCChapterEditor(entryID: entryID, slotID: $0.id) }
        .fullScreenCover(item: $reader) { MCReaderView(sequence: $0.sequence).ignoresSafeArea() }
        .confirmationDialog("Remove this entry from library?", isPresented: $confirmRemove) {
            Button("Remove entry", role: .destructive) { if store.removeEntries([entryID]) { dismiss() } }
        } message: { Text("Reading history and downloaded chapters are kept.") }
        .confirmationDialog("Reset entry edits?", isPresented: $confirmReset) {
            Button("Reset edits", role: .destructive) { store.perform { try $0.library.resetDetails(entryID) } }
        } message: { Text("Resets the entry’s title, description, author and cover. Chapters, categories and reading progress are kept.") }
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

    private var chapterActions: some View {
        VStack(spacing: 12) {
            HStack {
                Text(selecting ? "\(selected.count) selected" : "\(slots.count) chapters").font(.headline)
                Spacer()
                if store.isRefreshing { ProgressView() }
                Button { selecting.toggle(); selected.removeAll() } label: {
                    Image(systemName: selecting ? "checkmark.circle.fill" : "checkmark.circle").frame(width: 32, height: 32)
                }.accessibilityLabel(selecting ? "Done selecting" : "Select chapters")
                Button { store.perform { try $0.library.editEntry(entryID) { $0.descendingDisplay.toggle() } } } label: {
                    Image(systemName: "arrow.up.arrow.down").frame(width: 32, height: 32)
                }.accessibilityLabel("Reverse displayed chapter order")
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
                MCEntryCover(entry: entry).frame(width: 88, height: 132).clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 8) {
                    let title = store.library.title(entry)
                    Text(title)
                        .font(.title3.bold())
                        .lineLimit(4)
                        .contentShape(Rectangle())
                        .gesture(copyOrSearchGesture(for: title))
                    let creators = entry.authorOverride
                        ?? store.library.listing(entry.primaryListingID)?.details.authors?.joined(separator: ", ")
                        ?? store.library.listing(entry.primaryListingID)?.details.artists?.joined(separator: ", ")
                        ?? ""
                    if !creators.isEmpty {
                        Text(creators)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                            .gesture(copyOrSearchGesture(for: creators))
                    }
                    Text("\(entry.status.title) · \(entry.links.count) sources").font(.caption).foregroundStyle(.secondary)
                    if let sourceName = mainSourceName(entry) {
                        Label("Main source: \(sourceName)", systemImage: "globe")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !store.library.description(entry).isEmpty {
                        Text(store.library.description(entry)).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
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
            HStack(spacing: 10) {
                Button {
                    if let slot = entry.slots.first(where: { !store.library.isRead($0) }) ?? entry.slots.first { open(slot) }
                } label: {
                    Label("Read", systemImage: "book.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(entry.slots.isEmpty)

                Button { confirmRemove = true } label: {
                    Label("Unsave", systemImage: "bookmark.slash").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
            }
        }
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

    private func chapterRow(_ slot: MCChapterSlot, grid: Bool) -> some View {
        Button {
            if selecting { if !selected.insert(slot.id).inserted { selected.remove(slot.id) } }
            else { open(slot) }
        } label: {
            chapterLabel(slot, grid: grid)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 8))
        .contextMenu {

                Button("Read chapter", systemImage: "book") { open(slot) }
                Button("Edit chapter", systemImage: "pencil") { editingChapter = MCID(id: slot.id) }
                Button("Reset edits", systemImage: "arrow.counterclockwise") { resettingChapter = MCID(id: slot.id) }
                Button(store.library.isRead(slot) ? "Mark unread" : "Mark read") { store.setRead(entryID: entryID, slotIDs: [slot.id], read: !store.library.isRead(slot)) }
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

    private func open(_ slot: MCChapterSlot) {
        do { reader = MCReaderSheet(sequence: try MCReaderSequence(entryID: entryID, slotID: slot.id)) }
        catch { store.error = error.localizedDescription }
    }
    private func resetChapterThumbnails() {
        guard let entry else { return }
        let chapterIDs = Set(entry.slots.flatMap(\.variants).map(\.chapterID))
        if store.perform({ try $0.library.resetChapterThumbnails(entryID: entryID) }) {
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
                ForEach(store.library.entry(entryID)?.slots ?? []) { slot in
                    Text(slot.preferred.map { store.library.chapterDisplayTitle($0) } ?? "Chapter")
                }.onMove { from, to in
                    store.perform { state in
                        try state.library.editEntry(entryID) { entry in entry.manualOrder = true; entry.slots.move(fromOffsets: from, toOffset: to) }
                    }
                }
            }.environment(\.editMode, .constant(.active))
                .navigationTitle("Chapter order").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .mcErrors(store)
        }
    }
}

import AidokuRunner
import SwiftUI

private struct MCRemoteCoverField: View {
    @Binding var value: String
    let loading: Bool
    let use: () -> Void

    var body: some View {
        HStack {
            TextField("Image URL", text: $value)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(use)
            if loading {
                ProgressView()
            } else {
                Button("Use", action: use)
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

struct MCEntryEditor: View {
    let entryID: UUID?
    @State private var groupingEntryIDs: [UUID]
    private let onCreated: ((UUID) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var title = ""
    @State private var author = ""
    @State private var artist = ""
    @State private var summary = ""
    @State private var status = MCPersonalStatus.planned
    @State private var getNewChapters = true
    @State private var categories = Set<UUID>()
    @State private var cover: MCLibraryCover?
    @State private var coverURL = ""
    @State private var loadingCoverURL = false
    @State private var clearCover = false
    @State private var restoreCover = false
    @State private var showCategories = false
    @State private var loaded = false
    @State private var resetConfirm = false
    @State private var inheritedTitle: String?
    @State private var groupingMode = MCEntryGroupingMode.nested
    @State private var chapterNaming = MCMergedChapterNaming.keepOriginal

    init(entryID: UUID) {
        self.entryID = entryID
        _groupingEntryIDs = State(initialValue: [])
        onCreated = nil
    }

    init(grouping entryIDs: [UUID], onCreated: @escaping (UUID) -> Void) {
        entryID = nil
        _groupingEntryIDs = State(initialValue: entryIDs)
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                if entryID == nil {
                    Section {
                        Picker("Combine titles", selection: $groupingMode) {
                            ForEach(MCEntryGroupingMode.allCases) { Text($0.title).tag($0) }
                        }
                        if groupingMode == .mergeChapters {
                            Picker("Chapter names", selection: $chapterNaming) {
                                ForEach(MCMergedChapterNaming.allCases) { Text($0.title).tag($0) }
                            }
                        }
                        Menu("Inherit details from…", systemImage: "doc.on.doc") {
                            ForEach(groupingEntryIDs.compactMap { store.library.entry($0) }) { entry in
                                Button(store.library.title(entry)) { inheritDetails(from: entry) }
                            }
                        }.disabled(loadingCoverURL)
                        if let inheritedTitle {
                            Text("Copied from \(inheritedTitle)").font(.caption).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Group \(groupingEntryIDs.count) titles")
                    } footer: {
                        Text(groupingMode == .nested
                             ? "Creates a parent title and keeps the selected titles nested inside it. Inherited details can be edited below."
                             : "Moves all chapters, including chapters in nested titles, into one new title. The original titles are replaced. Progress, source links and chapter edits are kept; duplicate source chapters are included once. Inherited details can be edited below.")
                    }
                    Section {
                        ForEach(groupingEntryIDs, id: \.self) { id in
                            if let entry = store.library.entry(id) {
                                Text(store.library.title(entry))
                            }
                        }.onMove { from, to in groupingEntryIDs.move(fromOffsets: from, toOffset: to) }
                    } header: {
                        Text("Title order")
                    } footer: {
                        Text(groupingMode == .mergeChapters && chapterNaming == .numberInOrder
                             ? "Drag to reorder titles. Their chapters become Chapter 1, Chapter 2, and so on in this order, keeping each title’s personal chapter order."
                             : "Drag to choose the order of titles and their chapters.")
                    }
                }
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Artist", text: $artist)
                    TextField("Author", text: $author)
                    TextField("Description", text: $summary, axis: .vertical).lineLimit(4...12)
                    Picker("Reading status", selection: $status) { ForEach(MCPersonalStatus.allCases) { Text($0.title).tag($0) } }
                    if let entryID, store.library.entry(entryID)?.primaryListingID != nil {
                        Toggle("Get new chapters", isOn: $getNewChapters)
                    }
                }
                Section("Cover") {
                    if let cover { MCCustomCoverImage(cover: cover, size: CGSize(width: 100, height: 150)).frame(width: 100, height: 150) }
                    MCRemoteCoverField(value: $coverURL, loading: loadingCoverURL) {
                        Task { await useCoverURL() }
                    }
                    Text("URL covers are cached and fetched again after clearing the image cache.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Hide cover", isOn: $clearCover)
                    Button(entryID == nil ? "Clear cover" : "Reset entry cover", systemImage: "arrow.counterclockwise") {
                        cover = nil; coverURL = ""; clearCover = false; restoreCover = true
                    }.disabled(loadingCoverURL)
                    if restoreCover && entryID != nil { Text("The original source cover will be restored when you save.").font(.caption).foregroundStyle(.secondary) }
                }
                Section("Categories") {
                    ForEach(store.snapshot.categories) { item in
                        Toggle(item.name, isOn: Binding(get: { categories.contains(item.id) }, set: { if $0 { categories.insert(item.id) } else { categories.remove(item.id) } }))
                    }
                    Button("Manage categories") { showCategories = true }
                }
                if entryID != nil {
                    Section { Button("Reset edits", role: .destructive) { resetConfirm = true } }
                }
            }
            .environment(\.editMode, .constant(entryID == nil ? .active : .inactive))
            .navigationTitle(entryID == nil ? "Group into new title" : "Edit entry").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(entryID == nil ? "Create" : "Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loadingCoverURL)
                }
            }
            .onAppear {
                guard !loaded else { return }; loaded = true
                if let entryID, let entry = store.library.entry(entryID) {
                    title = store.library.title(entry); summary = store.library.description(entry)
                    author = entry.authorOverride ?? store.library.listing(entry.primaryListingID)?.details.authors?.joined(separator: ", ") ?? ""
                    artist = entry.artistOverride ?? store.library.listing(entry.primaryListingID)?.details.artists?.joined(separator: ", ") ?? ""
                    status = entry.status; categories = entry.categoryIDs; clearCover = entry.hidesCover
                    getNewChapters = entry.links.first(where: { $0.listingID == entry.primaryListingID })?.followsNewChapters ?? true
                }
            }
            .sheet(isPresented: $showCategories) { MCCategoriesView() }
            .confirmationDialog("Reset this entry’s details?", isPresented: $resetConfirm) {
                Button("Reset edits", role: .destructive) {
                    guard let entryID else { return }
                    if store.perform({ try $0.library.resetDetails(entryID) }) { dismiss() }
                }
            } message: { Text("Restores entry details and cover. Chapter edits, categories and progress are kept.") }
            .mcErrors(store)
        }
    }

    private var coverSource: AidokuRunner.Source? {
        guard let entryID, let entry = store.library.entry(entryID),
              let listing = store.library.listing(entry.primaryListingID) else { return nil }
        return store.source(listing.identity.connectionID)
    }

    private func inheritDetails(from entry: MCPersonalEntry) {
        let connectionID = store.library.listing(entry.primaryListingID)?.identity.connectionID
        let sourceKey = store.snapshot.connections.first { $0.id == connectionID }?.sourceKey
        let details = store.library.titleDetails(of: entry, sourceKey: sourceKey)
        title = details.title; summary = details.description
        author = details.author; artist = details.artist
        status = details.status; categories = details.categoryIDs
        cover = details.cover; clearCover = details.hidesCover
        coverURL = details.cover?.url?.absoluteString ?? ""
        restoreCover = false
        inheritedTitle = details.title
    }

    private func useCoverURL() async {
        guard !loadingCoverURL else { return }
        loadingCoverURL = true
        defer { loadingCoverURL = false }
        do {
            cover = try await MCRemoteCoverLoader.load(coverURL, source: coverSource)
            clearCover = false
            restoreCover = false
        } catch {
            store.error = error.localizedDescription
        }
    }

    private func save() {
        guard let entryID else {
            do {
                let details = MCEntryDetails(title: title, description: summary, author: author, artist: artist,
                    status: status, categoryIDs: categories.intersection(Set(store.snapshot.categories.map(\.id))),
                    cover: cover, hidesCover: clearCover)
                let createdID = try store.groupEntries(groupingEntryIDs, details: details, mode: groupingMode, naming: chapterNaming)
                dismiss()
                onCreated?(createdID)
            } catch {
                store.error = error.localizedDescription
            }
            return
        }
        if store.perform({ state in
            guard let original = state.library.entry(entryID) else { throw MCLibraryFailure.missing }
            let listing = state.library.listing(original.primaryListingID)
            let knownChapters = Set(state.library.chapters.filter { $0.identity.listing == listing?.identity }.map(\.id))
            if let cover { state.library.covers.append(cover) }
            let validCategories = categories.intersection(Set(state.categories.map(\.id)))
            try state.library.editEntry(entryID) { entry in
                if title != (original.titleOverride ?? listing?.details.title ?? "") || listing == nil { entry.titleOverride = title.trimmingCharacters(in: .whitespacesAndNewlines) }
                if summary != (original.descriptionOverride ?? listing?.details.description ?? "") { entry.descriptionOverride = summary }
                if author != (original.authorOverride ?? listing?.details.authors?.joined(separator: ", ") ?? "") { entry.authorOverride = author }
                if artist != (original.artistOverride ?? listing?.details.artists?.joined(separator: ", ") ?? "") { entry.artistOverride = artist }
                entry.status = status; entry.categoryIDs = validCategories; entry.hidesCover = clearCover
                if let index = entry.links.firstIndex(where: { $0.listingID == entry.primaryListingID }),
                   entry.links[index].followsNewChapters != getNewChapters {
                    if getNewChapters && entry.links[index].needsInitialImport != true {
                        entry.links[index].followBaseline = knownChapters
                    }
                    entry.links[index].followsNewChapters = getNewChapters
                }
                if restoreCover { entry.coverID = nil }
                if let cover { entry.coverID = cover.id }
                if clearCover { entry.coverID = nil }
            }
        }) { dismiss() }
    }
}

struct MCChapterEditor: View {
    let entryID: UUID
    let slotID: UUID
    let resetThumbnail: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var title = ""
    @State private var number = ""
    @State private var volume = ""
    @State private var cover: MCLibraryCover?
    @State private var coverURL = ""
    @State private var loadingCoverURL = false
    @State private var loaded = false
    @State private var confirmReset = false
    private var variant: MCChapterVariant? { store.library.entry(entryID)?.slots.first { $0.id == slotID }?.preferred }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Chapter title", text: $title)
                TextField("Chapter number", text: $number).keyboardType(.decimalPad)
                TextField("Volume", text: $volume)
                MCRemoteCoverField(value: $coverURL, loading: loadingCoverURL) {
                    Task { await useCoverURL() }
                }
                if let cover { MCCustomCoverImage(cover: cover, size: CGSize(width: 120, height: 180)).frame(width: 120, height: 180) }
                Section {
                    Button("Reset thumbnail", systemImage: "photo.badge.arrow.down") {
                        resetThumbnail()
                        cover = nil; coverURL = ""
                    }.disabled(loadingCoverURL)
                    Button("Reset edits", systemImage: "arrow.counterclockwise", role: .destructive) { confirmReset = true }
                        .disabled(loadingCoverURL)
                }
            }.navigationTitle("Edit chapter").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save(reset: false) }.disabled(loadingCoverURL) }
                }
                .onAppear {
                    guard !loaded, let variant else { return }; loaded = true
                    title = store.library.chapterDisplayTitle(variant); number = store.library.number(variant) ?? ""
                    volume = variant.edits.volume ?? store.library.chapter(variant.chapterID)?.record.volume ?? ""
                    cover = store.library.covers.first { $0.id == variant.edits.coverID }
                    coverURL = cover?.url?.absoluteString ?? ""
                }
                .confirmationDialog("Reset chapter edits?", isPresented: $confirmReset) {
                    Button("Reset edits", role: .destructive) { save(reset: true) }
                } message: { Text("Restores the source title, number, volume and thumbnail.") }
                .mcErrors(store)
        }
    }

    private var coverSource: AidokuRunner.Source? {
        guard let variant, let chapter = store.library.chapter(variant.chapterID) else { return nil }
        return store.source(chapter.identity.listing.connectionID)
    }

    private func useCoverURL() async {
        guard !loadingCoverURL else { return }
        loadingCoverURL = true
        defer { loadingCoverURL = false }
        do {
            cover = try await MCRemoteCoverLoader.load(coverURL, source: coverSource)
        } catch {
            store.error = error.localizedDescription
        }
    }

    private func save(reset: Bool) {
        guard let variant else { return }
        if store.perform({ state in
            if let cover, !reset, !state.library.covers.contains(where: { $0.id == cover.id }) { state.library.covers.append(cover) }
            try state.library.editEntry(entryID) { entry in
                guard let s = entry.slots.firstIndex(where: { $0.id == slotID }),
                      let v = entry.slots[s].variants.firstIndex(where: { $0.id == variant.id }) else { throw MCLibraryFailure.missing }
                if reset { entry.slots[s].variants[v].edits = MCChapterEdits() }
                else {
                    if title != store.library.chapterDisplayTitle(variant) { entry.slots[s].variants[v].edits.title = title }
                    if number != (store.library.number(variant) ?? "") { entry.slots[s].variants[v].edits.number = number }
                    if volume != (variant.edits.volume ?? store.library.chapter(variant.chapterID)?.record.volume ?? "") { entry.slots[s].variants[v].edits.volume = volume }
                    if let cover { entry.slots[s].variants[v].edits.coverID = cover.id }
                }
            }
        }) { dismiss() }
    }
}

struct MCCategoriesView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            MCCategoriesPage()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct MCCategoriesPage: View {
    @State private var store = MCCollectionStore.shared
    @State private var name = ""
    @State private var renaming: MCCategory?
    @State private var renamedTitle = ""
    var body: some View {
        Form {
            Section("Categories") {
                ForEach(store.snapshot.categories) { category in
                    HStack {
                        Text(category.name)
                        Spacer()
                        Button { renamedTitle = category.name; renaming = category } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless).accessibilityLabel("Rename \(category.name)")
                    }
                }.onDelete { indices in
                    let ids = Set(indices.map { store.snapshot.categories[$0].id })
                    store.perform { state in
                        state.categories.removeAll { ids.contains($0.id) }
                        for i in state.library.entries.indices { state.library.entries[i].categoryIDs.subtract(ids) }
                    }
                }.onMove { from, to in store.perform { $0.categories.move(fromOffsets: from, toOffset: to) } }
            }
            Section {
                TextField("New category", text: $name)
                Button("Add category") {
                    let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard validName(value) else { return }
                    if store.perform({ $0.categories.append(MCCategory(name: value)) }) { name = "" }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Categories").navigationBarTitleDisplayMode(.inline)
        .alert("Rename category", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renamedTitle)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                guard let category = renaming else { return }
                let value = renamedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard validName(value, excluding: category.id) else { return }
                if AppSettings.library.defaultCategory.get() == category.name { AppSettings.library.defaultCategory.set(value) }
                store.perform { state in
                    if let index = state.categories.firstIndex(where: { $0.id == category.id }) { state.categories[index].name = value }
                }
                renaming = nil
            }
        }
        .task { await store.importLegacyCategories() }
        .mcErrors(store)
    }
    private func validName(_ value: String, excluding id: UUID? = nil) -> Bool {
        guard !value.isEmpty, value.count <= 80,
              !store.snapshot.categories.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(value) == .orderedSame }) else {
            store.error = "Use a unique category name between 1 and 80 characters."
            return false
        }
        return true
    }
}

struct MCAddSourceView: View {
    let manga: AidokuRunner.Manga
    let chapters: [AidokuRunner.Chapter]
    @State private var store = MCCollectionStore.shared
    @State private var categories = Set<UUID>()
    @State private var status = MCPersonalStatus.planned
    @State private var follow = true
    @State private var title = ""
    @State private var author = ""
    @State private var artist = ""
    @State private var summary = ""
    @State private var cover: MCLibraryCover?
    @State private var coverURL = ""
    @State private var loadingCoverURL = false
    @State private var loaded = false
    @State private var showCategories = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Artist", text: $artist)
                    TextField("Author", text: $author)
                    TextField("Description", text: $summary, axis: .vertical).lineLimit(4...12)
                    Picker("Reading status", selection: $status) { ForEach(MCPersonalStatus.allCases) { Text($0.title).tag($0) } }
                    Toggle("Get new chapters", isOn: $follow)
                }
                Section("Cover") {
                    if let cover { MCCustomCoverImage(cover: cover, size: CGSize(width: 94, height: 140)).frame(width: 94, height: 140) }
                    MCRemoteCoverField(value: $coverURL, loading: loadingCoverURL) {
                        Task { await useCoverURL() }
                    }
                    Text("Use an image URL so the cover can reload after clearing the cache.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Categories") {
                    ForEach(store.snapshot.categories) { item in
                        Toggle(item.name, isOn: Binding(get: { categories.contains(item.id) }, set: { if $0 { categories.insert(item.id) } else { categories.remove(item.id) } }))
                    }
                    Button("Manage categories") { showCategories = true }
                }
            }.navigationTitle("Add to library").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Add") { save() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
                .task {
                    guard !loaded else { return }; loaded = true
                    title = manga.title; summary = manga.description ?? ""; author = manga.authors?.joined(separator: ", ") ?? ""
                    artist = manga.artists?.joined(separator: ", ") ?? ""
                    await store.importLegacyCategories()
                    if let name = AppSettings.library.defaultCategory.get(), let category = store.snapshot.categories.first(where: { $0.name == name }) { categories = [category.id] }
                }
                .sheet(isPresented: $showCategories) { MCCategoriesView() }
                .mcErrors(store)
        }
    }

    private func useCoverURL() async {
        guard !loadingCoverURL else { return }
        loadingCoverURL = true
        defer { loadingCoverURL = false }
        do {
            let source = SourceStore.shared.source(for: manga.sourceKey)
            cover = try await MCRemoteCoverLoader.load(coverURL, source: source)
        } catch {
            store.error = error.localizedDescription
        }
    }

    private func save() {
        do {
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try store.add(manga, chapters: chapters, categories: categories.intersection(Set(store.snapshot.categories.map(\.id))), status: status, follow: follow,
                              title: title == manga.title ? nil : title,
                              description: summary == (manga.description ?? "") ? nil : summary,
                              author: author == (manga.authors?.joined(separator: ", ") ?? "") ? nil : author,
                              artist: artist == (manga.artists?.joined(separator: ", ") ?? "") ? nil : artist,
                              cover: cover)
            Task { await MangaManager.shared.addToLibrary(manga: manga, chapters: chapters) }
            dismiss()
        } catch { store.error = error.localizedDescription }
    }
}

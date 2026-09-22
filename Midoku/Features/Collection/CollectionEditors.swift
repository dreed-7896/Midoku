import AidokuRunner
import PhotosUI
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
    let entryID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var title = ""
    @State private var author = ""
    @State private var artist = ""
    @State private var summary = ""
    @State private var status = MCPersonalStatus.planned
    @State private var categories = Set<UUID>()
    @State private var photo: PhotosPickerItem?
    @State private var cover: MCLibraryCover?
    @State private var coverURL = ""
    @State private var loadingCoverURL = false
    @State private var clearCover = false
    @State private var showCategories = false
    @State private var loaded = false
    @State private var resetConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                    TextField("Artist", text: $artist)
                    TextField("Description", text: $summary, axis: .vertical).lineLimit(4...12)
                    Picker("Reading status", selection: $status) { ForEach(MCPersonalStatus.allCases) { Text($0.title).tag($0) } }
                }
                Section("Cover") {
                    if let cover, let image = UIImage(data: cover.data) { Image(uiImage: image).resizable().scaledToFit().frame(height: 150) }
                    PhotosPicker("Choose cover", selection: $photo, matching: .images)
                    MCRemoteCoverField(value: $coverURL, loading: loadingCoverURL) {
                        Task { await useCoverURL() }
                    }
                    Toggle("Hide cover", isOn: $clearCover)
                }
                Section("Categories") {
                    ForEach(store.snapshot.categories) { item in
                        Toggle(item.name, isOn: Binding(get: { categories.contains(item.id) }, set: { if $0 { categories.insert(item.id) } else { categories.remove(item.id) } }))
                    }
                    Button("Manage categories") { showCategories = true }
                }
                Section { Button("Reset edits", role: .destructive) { resetConfirm = true } }
            }
            .navigationTitle("Edit entry").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .onAppear {
                guard !loaded else { return }; loaded = true
                if let entry = store.library.entry(entryID) {
                    title = store.library.title(entry); summary = store.library.description(entry)
                    author = entry.authorOverride ?? store.library.listing(entry.primaryListingID)?.details.authors?.joined(separator: ", ") ?? ""
                    artist = entry.artistOverride ?? store.library.listing(entry.primaryListingID)?.details.artists?.joined(separator: ", ") ?? ""
                    status = entry.status; categories = entry.categoryIDs; clearCover = entry.hidesCover
                }
            }
            .onChange(of: photo) { _, photo in Task {
                do { if let data = try await photo?.loadTransferable(type: Data.self) { cover = try store.saveCover(data: data); clearCover = false; coverURL = "" } }
                catch { store.error = error.localizedDescription }
            } }
            .sheet(isPresented: $showCategories) { MCCategoriesView() }
            .confirmationDialog("Reset this entry’s details?", isPresented: $resetConfirm) {
                Button("Reset edits", role: .destructive) {
                    if store.perform({ try $0.library.resetDetails(entryID) }) { dismiss() }
                }
            } message: { Text("Restores entry details and cover. Chapter edits, categories and progress are kept.") }
            .mcErrors(store)
        }
    }

    private var coverSource: AidokuRunner.Source? {
        guard let entry = store.library.entry(entryID),
              let listing = store.library.listing(entry.primaryListingID) else { return nil }
        return store.source(listing.identity.connectionID)
    }

    private func useCoverURL() async {
        guard !loadingCoverURL else { return }
        loadingCoverURL = true
        defer { loadingCoverURL = false }
        do {
            cover = try await MCRemoteCoverLoader.load(coverURL, source: coverSource, store: store)
            clearCover = false
            photo = nil
        } catch {
            store.error = error.localizedDescription
        }
    }

    private func save() {
        if store.perform({ state in
            guard let original = state.library.entry(entryID) else { throw MCLibraryFailure.missing }
            let listing = state.library.listing(original.primaryListingID)
            if let cover { state.library.covers.append(cover) }
            let validCategories = categories.intersection(Set(state.categories.map(\.id)))
            try state.library.editEntry(entryID) { entry in
                if title != (original.titleOverride ?? listing?.details.title ?? "") || listing == nil { entry.titleOverride = title.trimmingCharacters(in: .whitespacesAndNewlines) }
                if summary != (original.descriptionOverride ?? listing?.details.description ?? "") { entry.descriptionOverride = summary }
                if author != (original.authorOverride ?? listing?.details.authors?.joined(separator: ", ") ?? "") { entry.authorOverride = author }
                if artist != (original.artistOverride ?? listing?.details.artists?.joined(separator: ", ") ?? "") { entry.artistOverride = artist }
                entry.status = status; entry.categoryIDs = validCategories; entry.hidesCover = clearCover
                if let cover { entry.coverID = cover.id }
                if clearCover { entry.coverID = nil }
            }
        }) { dismiss() }
    }
}

struct MCChapterEditor: View {
    let entryID: UUID
    let slotID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var title = ""
    @State private var number = ""
    @State private var volume = ""
    @State private var cover: MCLibraryCover?
    @State private var photo: PhotosPickerItem?
    @State private var coverURL = ""
    @State private var loadingCoverURL = false
    @State private var loaded = false
    private var variant: MCChapterVariant? { store.library.entry(entryID)?.slots.first { $0.id == slotID }?.preferred }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Chapter title", text: $title)
                TextField("Chapter number", text: $number).keyboardType(.decimalPad)
                TextField("Volume", text: $volume)
                PhotosPicker("Choose chapter thumbnail", selection: $photo, matching: .images)
                MCRemoteCoverField(value: $coverURL, loading: loadingCoverURL) {
                    Task { await useCoverURL() }
                }
                if let cover, let image = UIImage(data: cover.data) { Image(uiImage: image).resizable().scaledToFit().frame(height: 180) }
                Button("Reset edits") { save(reset: true) }
            }.navigationTitle("Edit chapter").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save(reset: false) } }
                }
                .onAppear {
                    guard !loaded, let variant else { return }; loaded = true
                    title = store.library.chapterDisplayTitle(variant); number = store.library.number(variant) ?? ""
                    volume = variant.edits.volume ?? store.library.chapter(variant.chapterID)?.record.volume ?? ""
                }
                .onChange(of: photo) { _, photo in Task {
                    do { if let data = try await photo?.loadTransferable(type: Data.self) { cover = try store.saveCover(data: data); coverURL = "" } }
                    catch { store.error = error.localizedDescription }
                } }.mcErrors(store)
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
            cover = try await MCRemoteCoverLoader.load(coverURL, source: coverSource, store: store)
            photo = nil
        } catch {
            store.error = error.localizedDescription
        }
    }

    private func save(reset: Bool) {
        guard let variant else { return }
        if store.perform({ state in
            if let cover, !reset { state.library.covers.append(cover) }
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
    @State private var photo: PhotosPickerItem?
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
                    TextField("Author", text: $author)
                    TextField("Artist", text: $artist)
                    TextField("Description", text: $summary, axis: .vertical).lineLimit(4...12)
                    Picker("Reading status", selection: $status) { ForEach(MCPersonalStatus.allCases) { Text($0.title).tag($0) } }
                    Toggle("Follow new chapters", isOn: $follow)
                }
                Section("Cover") {
                    if let cover, let image = UIImage(data: cover.data) { Image(uiImage: image).resizable().scaledToFit().frame(height: 140) }
                    PhotosPicker("Choose cover", selection: $photo, matching: .images)
                    MCRemoteCoverField(value: $coverURL, loading: loadingCoverURL) {
                        Task { await useCoverURL() }
                    }
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
                .onChange(of: photo) { _, value in Task {
                    do { if let data = try await value?.loadTransferable(type: Data.self) { cover = try store.saveCover(data: data); coverURL = "" } }
                    catch { store.error = error.localizedDescription }
                } }
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
            cover = try await MCRemoteCoverLoader.load(coverURL, source: source, store: store)
            photo = nil
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

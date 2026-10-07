import SwiftUI

/// Load inside the presented view instead of capturing the parent's empty state
/// during its first sheet presentation. Library bookmarks are grouped by title.
struct MCPanelBookmarksView: View {
    let titleKey: String?
    let select: (MCPanelBookmark) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var bookmarks: [MCPanelBookmark]
    @State private var filter = BookmarkFilter.all
    @State private var query = ""

    private enum BookmarkFilter: String, CaseIterable {
        case all = "All", chapters = "Chapters", panels = "Panels"
    }

    private var filteredBookmarks: [MCPanelBookmark] {
        bookmarks.filter { bookmark in
            let matchesKind = filter == .all || (filter == .chapters ? bookmark.isChapter : !bookmark.isChapter)
            let matchesQuery = query.isEmpty || bookmark.chapterTitle.localizedCaseInsensitiveContains(query)
                || (bookmark.title?.localizedCaseInsensitiveContains(query) ?? false)
                || (bookmark.chapterNumber.map { "Chapter \($0.formatted())".localizedCaseInsensitiveContains(query) } ?? false)
            return matchesKind && matchesQuery
        }
    }

    init(titleKey: String? = nil, select: @escaping (MCPanelBookmark) -> Void) {
        self.titleKey = titleKey
        self.select = select
        _bookmarks = State(initialValue: titleKey.map(MCPanelBookmarks.forTitle) ?? MCPanelBookmarks.all)
    }

    private struct TitleGroup: Identifiable {
        let id: String
        let title: String
        let panels: [MCPanelBookmark]
    }

    private var groups: [TitleGroup] {
        Dictionary(grouping: filteredBookmarks, by: \.titleKey).map { key, panels in
            let title: String
            if let id = UUID(uuidString: key), let entry = store.library.entry(id) {
                title = store.library.title(entry)
            } else if let savedTitle = panels.first?.title {
                title = savedTitle
            } else if let first = panels.first, let manga = store.snapshot.manga.first(where: {
                $0.manga.sourceKey == first.sourceKey && $0.manga.key == first.mangaKey
            }) {
                title = manga.manga.title ?? "Unavailable title"
            } else { title = "Unavailable title" }
            return TitleGroup(id: key, title: title, panels: panels)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.panels) { bookmark in
                            Button {
                                select(bookmark)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    if bookmark.isChapter {
                                        Image(systemName: "book.closed.fill")
                                            .font(.title2).foregroundStyle(Color.accentColor)
                                            .frame(width: 64, height: 88)
                                            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                                    } else if let data = bookmark.preview, let image = UIImage(data: data) {
                                        Image(uiImage: image).resizable().scaledToFit()
                                            .frame(width: 64, height: 88).clipped()
                                    } else {
                                        Image(systemName: "photo").frame(width: 64, height: 88)
                                            .foregroundStyle(.secondary)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(bookmark.chapterTitle).font(.headline).lineLimit(2)
                                        if bookmark.isChapter {
                                            Label("Chapter bookmark", systemImage: "bookmark.fill")
                                                .font(.caption).foregroundStyle(Color.accentColor)
                                        } else {
                                            Text(bookmark.chapterNumber.map { "Chapter \($0.formatted()) · Panel \(bookmark.page)" }
                                                 ?? "Panel \(bookmark.page)")
                                                .font(.subheadline).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                            .contextMenu {
                                Button("Remove bookmark", systemImage: "bookmark.slash", role: .destructive) {
                                    MCPanelBookmarks.remove(bookmark.id)
                                    reload()
                                }
                            }
                        }.onDelete { offsets in
                            let ids = offsets.map { group.panels[$0].id }
                            for id in ids { MCPanelBookmarks.remove(id) }
                            reload()
                        }
                    }
                }
            }
            .overlay {
                if filteredBookmarks.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "No \(filter == .all ? "bookmarks" : filter.rawValue.lowercased()) yet" : "No matching bookmarks",
                        systemImage: "bookmark", description: Text("Hold a chapter or panel to bookmark it."))
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Bookmark type", selection: $filter) {
                    ForEach(BookmarkFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 10).background(.bar)
            }
            .searchable(text: $query, prompt: "Search bookmarks")
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { reload() }
            .onReceive(NotificationCenter.default.publisher(for: MCPanelBookmarks.changed)) { _ in reload() }
        }
        .midokuAccent()
    }

    private func reload() {
        bookmarks = titleKey.map(MCPanelBookmarks.forTitle) ?? MCPanelBookmarks.all
    }
}

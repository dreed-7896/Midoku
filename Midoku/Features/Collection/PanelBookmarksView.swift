import SwiftUI

/// Load inside the presented view instead of capturing the parent's empty state
/// during its first sheet presentation. Library bookmarks are grouped by title.
struct MCPanelBookmarksView: View {
    let titleKey: String?
    let select: (MCPanelBookmark) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var bookmarks: [MCPanelBookmark]

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
        Dictionary(grouping: bookmarks, by: \.titleKey).map { key, panels in
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
                                    if let data = bookmark.preview, let image = UIImage(data: data) {
                                        Image(uiImage: image).resizable().scaledToFit()
                                            .frame(width: 64, height: 88).clipped()
                                    } else {
                                        Image(systemName: "photo").frame(width: 64, height: 88)
                                            .foregroundStyle(.secondary)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(bookmark.chapterTitle).font(.headline).lineLimit(2)
                                        Text(bookmark.chapterNumber.map { "Chapter \($0.formatted()) · Panel \(bookmark.page)" }
                                             ?? "Panel \(bookmark.page)")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }.onDelete { offsets in
                            let ids = offsets.map { group.panels[$0].id }
                            for id in ids { MCPanelBookmarks.remove(id) }
                            reload()
                        }
                    }
                }
            }
            .overlay {
                if bookmarks.isEmpty { ContentUnavailableView("No bookmarked panels", systemImage: "bookmark") }
            }
            .navigationTitle("Bookmarked panels")
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

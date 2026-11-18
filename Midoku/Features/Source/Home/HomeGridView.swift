//
//  HomeGridView.swift
//  Midoku
//
//  Created by Skitty on 5/27/25.
//

import AidokuRunner
import SwiftUI

struct HomeGridView: View {
    let source: AidokuRunner.Source
    let entries: [AidokuRunner.Manga]
    @Binding var bookmarkedItems: Set<String>
    var loadMore: (() async -> Void)?
    var onSelect: ((AidokuRunner.Manga) -> Void)?

    @State private var loadingMore = false
    @State private var columns: [GridItem]

    @EnvironmentObject private var path: NavigationCoordinator

    static let spacing: CGFloat = 12

    init(
        source: AidokuRunner.Source,
        entries: [AidokuRunner.Manga],
        bookmarkedItems: Binding<Set<String>> = .constant([]),
        loadMore: (() async -> Void)? = nil,
        onSelect: ((AidokuRunner.Manga) -> Void)? = nil
    ) {
        self.source = source
        self.entries = entries
        self._bookmarkedItems = bookmarkedItems
        self.loadMore = loadMore
        self.onSelect = onSelect
        self._columns = State(initialValue: Self.getColumns())
    }

    /// `.grid3`: three columns on a phone, more on wider screens; 10pt between columns.
    static func getColumns() -> [GridItem] {
        let width = UIScreen.main.bounds.width - 32
        let count = max(3, Int(floor((width + 10) / 140)))
        return (0..<count).map { _ in GridItem(.flexible(), spacing: 10, alignment: .top) }
    }

    var body: some View {
        LazyVGrid(
            columns: columns,
            spacing: 18
        ) {
            ForEach(entries.indices, id: \.self) { index in
                mangaGridItem(entry: entries[index])
            }
            loadMoreView
        }
        .padding([.horizontal, .bottom])
        .onChange(of: entries) { _ in
            loadingMore = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .orientationDidChange)) { _ in
            columns = Self.getColumns()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init(AppSettings.appearance.layout.key))) { _ in
            columns = Self.getColumns()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init(AppSettings.appearance.customPortraitRows.key))) { _ in
            columns = Self.getColumns()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init(AppSettings.appearance.customLandscapeRows.key))) { _ in
            columns = Self.getColumns()
        }
    }

    private func mangaGridItem(entry: AidokuRunner.Manga) -> some View {
        let inLibrary = bookmarkedItems.contains(entry.key)
        return Button {
            if let onSelect {
                onSelect(entry)
            } else {
                path.push(MangaViewController(source: source, manga: entry, parent: path.rootViewController))
            }
        } label: {
            MDMangaCard(source: source, title: entry.title, coverImage: entry.cover ?? "", saved: inLibrary)
        }
        .buttonStyle(MangaGridButtonStyle())
        .mdLongPressActions(entry.title) {
            var rows: [MDActionRow] = []
            // a remove button for manga from the local source
            if entry.isLocal() {
                rows.append(MDActionRow(systemImage: "trash", title: NSLocalizedString("REMOVE"), destructive: true) {
                    Task {
                        await LocalFileManager.shared.removeManga(with: entry.key)
                        NotificationCenter.default.post(name: .init("refresh-content"), object: nil)
                    }
                })
            }
            if inLibrary {
                rows.append(MDActionRow(systemImage: "trash", title: NSLocalizedString("REMOVE_FROM_LIBRARY"), destructive: true) {
                    bookmarkedItems.remove(entry.key)
                    Task { await MangaManager.shared.removeFromLibrary(mangaId: entry.identifier) }
                })
            } else {
                rows.append(MDActionRow(systemImage: "plus.circle", title: NSLocalizedString("ADD_TO_LIBRARY")) {
                    Task {
                        if await MangaManager.shouldAskForCategories() {
                            // open category select view
                            let viewController = UINavigationController(rootViewController: CategorySelectViewController(manga: entry))
                            path.present(viewController)
                        } else {
                            bookmarkedItems.insert(entry.key)
                            await MangaManager.shared.addToLibrary(manga: entry, fetchMangaDetails: true)
                        }
                    }
                })
            }
            return rows
        }
    }

    @ViewBuilder
    var loadMoreView: some View {
        if !loadingMore, !entries.isEmpty, let loadMore {
            Spacer()
                .onAppear {
                    loadingMore = true
                    Task {
                        await loadMore()
                    }
                }
        } else {
            EmptyView()
        }
    }

    static var placeholder: some View {
        LazyVGrid(columns: Self.getColumns(), spacing: 18) {
            ForEach(0..<30) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    MangaGridItem.placeholder
                    MDSkeleton().frame(height: 12)
                    MDSkeleton().frame(width: 60, height: 12)
                }
            }
        }
        .shimmering()
        .padding([.horizontal, .bottom])
    }
}

//
//  MangaUpdatesView.swift
//  Midoku (iOS)
//
//  Created by axiel7 on 09/02/2024.
//

import AidokuRunner
import SwiftUI

struct MangaUpdatesView: View {
    struct UpdateSection: Hashable {
        let day: Int
        var items: [Item]
    }
    struct Item: Hashable {
        let mangaId: MangaIdentifier
        var updates: [UpdateInfo]
    }
    struct UpdateInfo: Identifiable, Hashable {
        let id: String
        let chapterIdentifier: ChapterIdentifier
        let date: Date
        let manga: AidokuRunner.Manga
        let chapter: Chapter?
        var viewed: Bool
    }

    private let limit = 25

    @State private var entries: [UpdateSection] = []
    @State private var offset = 0
    @State private var loadingMore = false
    @State private var reachedEnd = false
    @State private var hasNoUpdates = false
    @State private var loadingTask: Task<(), Never>?

    @EnvironmentObject private var path: NavigationCoordinator

    var body: some View {
        Group {
            List {
                listItemsWithSections

                if !reachedEnd {
                    loadingView
                        .onAppear {
                            if !loadingMore {
                                reachedEnd = true
                                loadingMore = true
                                loadingTask = Task {
                                    await loadNewEntries()
                                }
                            }
                        }
                } else if loadingMore {
                    loadingView
                }
            }
            .listStyle(.plain)
            .refreshable {
                loadingTask?.cancel()
                await MangaManager.shared.refreshLibrary(forceAll: true)
                await MCCollectionStore.shared.refresh()
                offset = 0
                entries = []
                reachedEnd = false
                hasNoUpdates = false
                loadingMore = true
                await loadNewEntries()
            }
            .overlay {
                if hasNoUpdates {
                    VStack(alignment: .center) {
                        Spacer()
                        Text(NSLocalizedString("NO_UPDATES"))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(NSLocalizedString("MANGA_UPDATES"))
        .onReceive(NotificationCenter.default.publisher(for: .mangaUpdatesViewed)) { notification in
            guard let objects = notification.object as? [MangaUpdateItem] else { return }

            for section in 0..<entries.count {
                for item in 0..<entries[section].items.count {
                    guard let manga = entries[section].items[item].updates.first?.manga else { continue }
                    if objects.contains(where: { $0.chapterId.mangaIdentifier == manga.identifier }) {
                        for i in 0..<entries[section].items[item].updates.count {
                            entries[section].items[item].updates[i].viewed = true
                        }
                    }
                }
            }
        }
    }

    var listItemsWithSections: some View {
        ForEach(entries, id: \.day) { entry in
            Section {
                let items = entry.items
                ForEach(items, id: \.mangaId) { item in
                    let updates = item.updates
                    if let update = updates.first {
                        NavigationLink(
                            destination: MangaView(manga: update.manga, path: path)
                                .onAppear {
                                    setOpened(manga: update.manga)
                                }
                        ) {
                            MangaUpdateItemView(updates: updates)
                        }
                        .offsetListSeparator()
                        .id(item.mangaId)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                removeUpdateItem(item: item, day: entry.day)
                            } label: {
                                Label(NSLocalizedString("DELETE"), systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text(Date.makeRelativeDate(days: entry.day))
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
            .listRowSeparator(.hidden)
        }
    }

    var loadingView: some View {
        HStack {
            Spacer()
            ProgressView()
                .id(UUID()) // fixes progress view being invisible
            Spacer()
        }
        .listRowSeparator(.hidden)
    }
}

extension MangaUpdatesView {
    private func loadNewEntries() async {
        let legacyUpdates = await CoreDataManager.shared.container.performBackgroundTask { [offset] context in
            CoreDataManager.shared.getRecentMangaUpdates(limit: limit, offset: offset, context: context).compactMap {
                if let mangaObj = CoreDataManager.shared.getManga(
                    mangaId: $0.identifier.mangaIdentifier,
                    context: context
                ) {
                    return UpdateInfo(
                        id: $0.id,
                        chapterIdentifier: $0.identifier,
                        date: $0.date ?? Date(),
                        manga: mangaObj.toNewManga(),
                        chapter: $0.chapter?.toChapter(),
                        viewed: $0.viewed
                    )
                } else {
                    return nil
                }
            }
        }
        guard !Task.isCancelled else { return }
        let store = MCCollectionStore.shared
        let personalLibrary = store.library
        let personalUpdates: [UpdateInfo] = offset == 0 ? personalLibrary.updates.compactMap { update in
            guard let physical = personalLibrary.chapter(update.chapterID).flatMap({
                store.physical($0.identity)
            }) else { return nil }
            let manga = physical.manga
            let chapter = physical.chapter
            return UpdateInfo(
                id: update.id.uuidString,
                chapterIdentifier: ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key),
                date: update.discoveredAt,
                manga: manga,
                chapter: Chapter(sourceId: manga.sourceKey, id: chapter.key, mangaId: manga.key,
                    title: chapter.title, scanlator: chapter.scanlators?.joined(separator: ", "),
                    url: chapter.url?.absoluteString, lang: chapter.language ?? "en",
                    chapterNum: chapter.chapterNumber, volumeNum: chapter.volumeNumber,
                    dateUploaded: chapter.dateUploaded, thumbnail: chapter.thumbnail,
                    locked: chapter.locked, sourceOrder: 0),
                viewed: false
            )
        } : []
        let legacyIDs = Set(legacyUpdates.map(\.chapterIdentifier))
        let newUpdates = legacyUpdates + personalUpdates.filter { !legacyIDs.contains($0.chapterIdentifier) }
        guard !newUpdates.isEmpty else {
            reachedEnd = true
            loadingMore = false
            withAnimation {
                hasNoUpdates = entries.isEmpty
            }
            return
        }

        let newUpdatesGrouped = Dictionary(grouping: newUpdates, by: \.manga.identifier)
        var updatesDict: [Int: [MangaIdentifier: [UpdateInfo]]] = entries
            .reduce(into: [:]) {
                $0[$1.day] = $1.items.reduce(into: [:]) {
                    $0[$1.mangaId] = $1.updates
                }
            }
        for obj in newUpdatesGrouped {
            for info in obj.value.sorted(by: { $0.date < $1.date }) {
                let day = Calendar.autoupdatingCurrent.dateComponents(
                    Set([Calendar.Component.day]),
                    from: info.date,
                    to: Date.endOfDay()
                ).day ?? 0

                var updatesOfTheDay = updatesDict[day] ?? [:]
                var newValue = updatesOfTheDay[obj.key] ?? []
                if !newValue.contains(where: { $0.chapterIdentifier == info.chapterIdentifier }) {
                    newValue.append(info)
                }
                updatesOfTheDay[obj.key] = newValue
                updatesDict[day] = updatesOfTheDay
            }
        }
        let newEntries: [UpdateSection] = updatesDict
            .map {
                .init(
                    day: $0.key,
                    items: $0.value
                        .map { .init(mangaId: $0.key, updates: $0.value) }
                        .sorted { ($0.updates.first?.date ?? Date()) > ($1.updates.first?.date ?? Date()) }
                )
            }
            .sorted { $0.day < $1.day }

        guard !Task.isCancelled else { return }

        offset += limit
        reachedEnd = legacyUpdates.count < limit

        withAnimation {
            entries = newEntries
            loadingMore = false
            if reachedEnd && newEntries.isEmpty {
                hasNoUpdates = true
            }
        }
    }

    private func setOpened(manga: AidokuRunner.Manga) {
        if !AppSettings.general.incognitoMode.get() {
            Task {
                await CoreDataManager.shared.setOpened(mangaId: manga.identifier)
                NotificationCenter.default.post(name: .updateLibrary, object: nil)
            }
        }
    }

    private func removeUpdateItem(item: Item, day: Int) {
        let updates = item.updates.map {
            $0.chapterIdentifier
        }

        var newEntries = entries
        if let sectionIndex = newEntries.firstIndex(where: { $0.day == day }) {
            var section = newEntries[sectionIndex]
            section.items.removeAll(where: { $0.mangaId == item.mangaId })
            if section.items.isEmpty {
                newEntries.remove(at: sectionIndex)
            } else {
                newEntries[sectionIndex] = section
            }
        }

        withAnimation {
            entries = newEntries
            if newEntries.isEmpty { hasNoUpdates = true }
        }

        MCCollectionStore.shared.perform { state in
            let identifiers = Set(updates)
            let removedIDs = Set(state.library.updates.filter { item in
                guard let chapter = state.library.chapter(item.chapterID),
                      let listing = state.library.listings.first(where: { $0.identity == chapter.identity.listing }),
                      let manga = state.manga.first(where: { $0.listingID == listing.id })?.manga else { return false }
                let id = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key,
                    chapterKey: chapter.record.id)
                return identifiers.contains(id)
            }.map(\.id))
            state.library.updates.removeAll { removedIDs.contains($0.id) }
        }

        Task {
            await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.removeMangaUpdates(
                    updates: updates,
                    context: context
                )
                try? context.save()
            }
        }
    }
}

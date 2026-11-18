//
//  ChapterListHeaderView.swift
//  Midoku
//
//  Created by Skitty on 4/23/25.
//

import SwiftUI
import AidokuRunner

struct ChapterListHeaderView: View {
    private let chapterCount: Int?

    @Binding var sortOption: ChapterSortOption
    @Binding var sortAscending: Bool

    @Binding var filters: [ChapterFilterOption]
    @Binding var langFilter: String?
    @Binding var scanlatorFilter: [String]

    @Binding var displayMode: ChapterTitleDisplayMode

    private var showMenu: Bool = false
    private var languages: [String] = []
    private var scanlators: [String] = []
    private var mangaId: MangaIdentifier
    private var unreadCount: Int?
    private var downloadedCount: Int?

    init(
        allChapters: [AidokuRunner.Chapter]? = nil,
        filteredChapters: [AidokuRunner.Chapter]? = nil,
        sortOption: Binding<ChapterSortOption>,
        sortAscending: Binding<Bool>,
        filters: Binding<[ChapterFilterOption]>,
        langFilter: Binding<String?>,
        scanlatorFilter: Binding<[String]>,
        displayMode: Binding<ChapterTitleDisplayMode>,
        mangaId: MangaIdentifier,
        unreadCount: Int? = nil,
        downloadedCount: Int? = nil
    ) {
        self.unreadCount = unreadCount
        self.downloadedCount = downloadedCount
        self.chapterCount = filteredChapters?.count
        self._sortOption = sortOption
        self._sortAscending = sortAscending
        self._filters = filters
        self._langFilter = langFilter
        self._scanlatorFilter = scanlatorFilter
        self._displayMode = displayMode
        self.mangaId = mangaId

        if let allChapters, !allChapters.isEmpty {
            var languages: Set<String> = []
            var scanlators: Set<String> = []
            for chapter in allChapters {
                if let chapterScanlators = chapter.scanlators, !scanlators.isEmpty {
                    for scanlator in chapterScanlators {
                        scanlators.insert(scanlator)
                    }
                } else {
                    scanlators.insert("")
                }
                if let lang = chapter.language {
                    languages.insert(lang)
                }
            }
            self.languages = languages.sorted()
            self.scanlators = scanlators.sorted()
            self.showMenu = true
        }
    }

    private func isOn(_ method: ChapterFilterMethod) -> Bool {
        filters.contains { $0.type == method && !$0.exclude }
    }

    /// The web's chapter chips: All, Unread, Downloaded (one at a time; the menu keeps the finer options).
    private func choose(_ method: ChapterFilterMethod?) {
        filters.removeAll { $0.type == .unread || $0.type == .downloaded }
        if let method { filters.append(ChapterFilterOption(type: method, exclude: false)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MDSectionHead(title: "Chapters", count: chapterCount.map(String.init) ?? "…") {
                if showMenu {
                    Button {
                        sortAscending.toggle()
                    } label: {
                        MDIconBox(systemImage: "arrow.up.arrow.down")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(sortAscending ? "Show newest first" : "Show oldest first")
                    menu
                }
            }
            if showMenu {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        let none = !isOn(.unread) && !isOn(.downloaded)
                        Button { choose(nil) } label: { MDChip(title: "All", active: none, large: false) }
                        Button { choose(.unread) } label: { MDChip(title: "Unread", count: unreadCount, active: isOn(.unread), large: false) }
                        Button { choose(.downloaded) } label: { MDChip(title: "Downloaded", count: downloadedCount, active: isOn(.downloaded), large: false) }
                    }
                    .buttonStyle(.plain)
                }
                .scrollClipDisabled()
            }
        }
    }

    var menu: some View {
        Menu {
            Section(NSLocalizedString("SORT_BY")) {
                ForEach(ChapterSortOption.allCases, id: \.self) { option in
                    Button {
                        if sortOption == option {
                            sortAscending.toggle()
                        } else {
                            sortOption = option
                            sortAscending = false
                        }
                    } label: {
                        Label {
                            Text(option.stringValue)
                        } icon: {
                            if sortOption == option {
                                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                            }
                        }
                    }
                }
            }
            Section(NSLocalizedString("FILTER_BY")) {
                ForEach(ChapterFilterMethod.allCases, id: \.self) { option in
                    let filterIdx = filters.firstIndex(where: { $0.type == option })
                    Button {
                        if let filterIdx {
                            if filters[filterIdx].exclude {
                                filters.remove(at: filterIdx)
                            } else {
                                filters[filterIdx].exclude = true
                            }
                        } else {
                            filters.append(ChapterFilterOption(type: option, exclude: false))
                        }
                    } label: {
                        Label {
                            Text(option.stringValue)
                        } icon: {
                            if let filterIdx, filters[filterIdx].exclude {
                                Image(systemName: "xmark")
                            } else if filterIdx != nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                if languages.count > 1 {
                    Menu(NSLocalizedString("LANGUAGE")) {
                        ForEach(languages, id: \.self) { lang in
                            Button {
                                let langValue = langFilter == lang ? nil : lang
                                langFilter = langValue
                            } label: {
                                Label {
                                    Text(SourceLanguage.displayName(for: lang))
                                } icon: {
                                    if langFilter == lang {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
                if scanlators.count > 1 {
                    Menu(NSLocalizedString("SCANLATOR")) {
                        ForEach(scanlators, id: \.self) { scanlator in
                            Button {
                                if let filterIndex = scanlatorFilter.firstIndex(of: scanlator) {
                                    scanlatorFilter.remove(at: filterIndex)
                                } else {
                                    scanlatorFilter.append(scanlator)
                                }
                            } label: {
                                Label {
                                    Text(scanlator.isEmpty ? NSLocalizedString("NO_SCANLATOR") : scanlator)
                                } icon: {
                                    if scanlatorFilter.contains(scanlator) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .menuActionDismissDisabled()
            Section(NSLocalizedString("TITLE_DISPLAY_MODE")) {
                ForEach(ChapterTitleDisplayMode.allCases, id: \.rawValue) { mode in
                    Button {
                        displayMode = mode
                        let key = "Manga.chapterDisplayMode.\(mangaId)"
                        if mode == .default {
                            UserDefaults.standard.removeObject(forKey: key)
                        } else {
                            UserDefaults.standard.set(mode.rawValue, forKey: key)
                        }
                    } label: {
                        Label {
                            Text(mode.localizedTitle)
                        } icon: {
                            if displayMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            MDIconBox(systemImage: "slider.horizontal.3", badge: filters.count + (langFilter == nil ? 0 : 1) + scanlatorFilter.count)
        }
        .accessibilityLabel("Filter and sort chapters")
    }
}

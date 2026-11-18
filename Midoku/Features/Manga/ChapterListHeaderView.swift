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
    @State private var showSheet = false
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
                if let chapterScanlators = chapter.scanlators, !chapterScanlators.isEmpty {
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

    private var activeFilterCount: Int {
        filters.count + (langFilter == nil ? 0 : 1) + scanlatorFilter.count
    }

    var menu: some View {
        Button { showSheet = true } label: {
            MDIconBox(systemImage: "slider.horizontal.3", active: activeFilterCount > 0,
                      badge: activeFilterCount > 0 ? activeFilterCount : nil)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort and filter chapters")
        .sheet(isPresented: $showSheet) {
            sheet
                .presentationDetents([.medium, .large])
                .midokuAccent()
        }
    }

    /// Midoku Web's "Sort and filter" sheet.
    private var sheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    group(NSLocalizedString("SORT_BY")) {
                        VStack(spacing: 10) {
                            MDSegmented(options: ChapterSortOption.allCases, selection: $sortOption) { $0.stringValue }
                            MDSegmented(options: [false, true], selection: $sortAscending) { $0 ? "Oldest first" : "Newest first" }
                        }
                    }
                    group(NSLocalizedString("FILTER_BY")) {
                        MDFlow {
                            ForEach(ChapterFilterMethod.allCases, id: \.self) { option in
                                let index = filters.firstIndex { $0.type == option }
                                let excluded = index.map { filters[$0].exclude } ?? false
                                chip(excluded ? "Not \(option.stringValue.lowercased())" : option.stringValue,
                                     on: index != nil, systemImage: excluded ? "xmark" : nil) {
                                    if let index {
                                        if filters[index].exclude { filters.remove(at: index) } else { filters[index].exclude = true }
                                    } else {
                                        filters.append(ChapterFilterOption(type: option, exclude: false))
                                    }
                                }
                            }
                        }
                        Text("Tap once to show only, again to hide, again to clear.")
                            .font(.mdSystem(size: 12)).foregroundStyle(Color.mdText3)
                    }
                    if languages.count > 1 {
                        group(NSLocalizedString("LANGUAGE")) {
                            MDFlow {
                                ForEach(languages, id: \.self) { lang in
                                    chip(SourceLanguage.displayName(for: lang), on: langFilter == lang) {
                                        langFilter = langFilter == lang ? nil : lang
                                    }
                                }
                            }
                        }
                    }
                    if scanlators.count > 1 {
                        group(NSLocalizedString("SCANLATOR")) {
                            MDFlow {
                                ForEach(scanlators, id: \.self) { scanlator in
                                    chip(scanlator.isEmpty ? NSLocalizedString("NO_SCANLATOR") : scanlator, on: scanlatorFilter.contains(scanlator)) {
                                        if let index = scanlatorFilter.firstIndex(of: scanlator) {
                                            scanlatorFilter.remove(at: index)
                                        } else {
                                            scanlatorFilter.append(scanlator)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    group(NSLocalizedString("TITLE_DISPLAY_MODE")) {
                        MDFlow {
                            ForEach(ChapterTitleDisplayMode.allCases, id: \.rawValue) { mode in
                                chip(mode.localizedTitle, on: displayMode == mode) { setDisplayMode(mode) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            .mdSheet("Sort and filter", onClose: { showSheet = false },
                     secondary: MDSheetAction(title: "Clear filters", disabled: activeFilterCount == 0) {
                         filters = []; langFilter = nil; scanlatorFilter = []
                     },
                     primary: MDSheetAction(title: "Done") { showSheet = false })
        }
    }

    private func setDisplayMode(_ mode: ChapterTitleDisplayMode) {
        displayMode = mode
        let key = "Manga.chapterDisplayMode.\(mangaId)"
        if mode == .default {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(mode.rawValue, forKey: key)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).mdLabel()
            content()
        }
    }

    private func chip(_ title: String, on: Bool, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { MDChip(title: title, active: on, systemImage: systemImage, large: false) }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
    }
}

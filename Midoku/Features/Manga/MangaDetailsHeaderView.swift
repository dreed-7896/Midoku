//
//  MangaDetailsHeaderView.swift
//  Midoku
//
//  Created by Skitty on 8/18/23.
//

import SwiftUI
import AidokuRunner
import MarkdownUI
import NukeUI
import SafariServices

struct MangaDetailsHeaderView: View {
    @Binding var source: AidokuRunner.Source?

    @Binding var manga: AidokuRunner.Manga
    @Binding var chapters: [AidokuRunner.Chapter]
    @Binding var nextChapter: AidokuRunner.Chapter?
    @Binding var readingInProgress: Bool
    @Binding var allChaptersLocked: Bool
    @Binding var allChaptersRead: Bool
    @Binding var initialDataLoaded: Bool

    @Binding var bookmarked: Bool
    @Binding var hasCategories: Bool
    @Binding var coverPressed: Bool
    @Binding var chapterSortOption: ChapterSortOption
    @Binding var chapterSortAscending: Bool

    @Binding var filters: [ChapterFilterOption]
    @Binding var langFilter: String?
    @Binding var scanlatorFilter: [String]

    @Binding var descriptionExpanded: Bool

    @Binding var chapterTitleDisplayMode: ChapterTitleDisplayMode

    var hasOtherDownloads: Bool
    var transitionNamespace: Namespace.ID
    var onTitlePressed: (() -> Void)?
    var onCreatorPressed: ((String) -> Void)?
    var onTrackerButtonPressed: (() -> Void)?
    var onReadButtonPressed: (() -> Void)?
    var readCount = 0
    var downloadedCount = 0
    var refreshing = false
    var onRefresh: (() -> Void)?
    var onDownloadUnread: (() -> Void)?

    @EnvironmentObject private var path: NavigationCoordinator

    @State private var readButtonText = NSLocalizedString("LOADING_ELLIPSIS")
    @State private var readButtonDisabled = true
    @State private var animationTrigger = false
    @State private var longHeldTitle = false
    @State private var longHeldCreator = false
    @State private var longHeldSafari = false
    @State private var isTracking = false
    @State private var hasAvailableTrackers = false
    @State private var showLibraryRemoveConfirm = false
    @State private var changingBookmark = false
    @State private var categoryEntry: MCID?
    @State private var showPlacementOptions = false

    private var placement: MCSourcePlacement { MCCollectionStore.shared.placement(for: manga) }

    private var saveTitle: String {
        switch placement {
        case .nested(_, let parent): "In \(parent)"
        case .linked(_, let title): "In \(title)"
        case .topLevel, .none: bookmarked ? "Saved" : "Save"
        }
    }

    private var saveSymbol: String {
        switch placement {
        case .nested: "folder.fill"
        case .linked: "link"
        case .topLevel, .none: bookmarked ? "bookmark.fill" : "bookmark"
        }
    }

    private var isSaved: Bool {
        switch placement {
        case .nested, .linked, .topLevel: true
        case .none: bookmarked
        }
    }

    /// Nested and merged titles are not top-level saves, so ask what to do instead of toggling.
    private func savePressed() {
        switch placement {
        case .nested, .linked:
            showPlacementOptions = true
        case .topLevel, .none:
            if bookmarked && isTracking {
                showLibraryRemoveConfirm = true
            } else {
                Task { await toggleBookmarked() }
            }
        }
    }

    static let coverWidth: CGFloat = 114

    init(
        source: Binding<AidokuRunner.Source?>,
        manga: Binding<AidokuRunner.Manga>,
        chapters: Binding<[AidokuRunner.Chapter]>,
        nextChapter: Binding<AidokuRunner.Chapter?>,
        readingInProgress: Binding<Bool>,
        allChaptersLocked: Binding<Bool>,
        allChaptersRead: Binding<Bool>,
        initialDataLoaded: Binding<Bool>,
        bookmarked: Binding<Bool>,
        hasCategories: Binding<Bool>,
        coverPressed: Binding<Bool>,
        chapterSortOption: Binding<ChapterSortOption>,
        chapterSortAscending: Binding<Bool>,
        filters: Binding<[ChapterFilterOption]>,
        langFilter: Binding<String?>,
        scanlatorFilter: Binding<[String]>,
        descriptionExpanded: Binding<Bool>,
        chapterTitleDisplayMode: Binding<ChapterTitleDisplayMode>,
        hasOtherDownloads: Bool,
        transitionNamespace: Namespace.ID,
        onTitlePressed: (() -> Void)? = nil,
        onCreatorPressed: ((String) -> Void)? = nil,
        onTrackerButtonPressed: (() -> Void)? = nil,
        onReadButtonPressed: (() -> Void)? = nil,
        readCount: Int = 0,
        downloadedCount: Int = 0,
        refreshing: Bool = false,
        onRefresh: (() -> Void)? = nil,
        onDownloadUnread: (() -> Void)? = nil
    ) {
        self.readCount = readCount
        self.downloadedCount = downloadedCount
        self.refreshing = refreshing
        self.onRefresh = onRefresh
        self.onDownloadUnread = onDownloadUnread
        self._source = source
        self._manga = manga
        self._chapters = chapters
        self._nextChapter = nextChapter
        self._readingInProgress = readingInProgress
        self._allChaptersLocked = allChaptersLocked
        self._allChaptersRead = allChaptersRead
        self._initialDataLoaded = initialDataLoaded
        self._bookmarked = bookmarked
        self._hasCategories = hasCategories
        self._coverPressed = coverPressed
        self._chapterSortOption = chapterSortOption
        self._chapterSortAscending = chapterSortAscending
        self._filters = filters
        self._langFilter = langFilter
        self._scanlatorFilter = scanlatorFilter
        self._descriptionExpanded = descriptionExpanded
        self._chapterTitleDisplayMode = chapterTitleDisplayMode
        self.hasOtherDownloads = hasOtherDownloads
        self.transitionNamespace = transitionNamespace
        self.onTitlePressed = onTitlePressed
        self.onCreatorPressed = onCreatorPressed
        self.onTrackerButtonPressed = onTrackerButtonPressed
        self.onReadButtonPressed = onReadButtonPressed

        self._isTracking = State(initialValue: TrackerManager.shared.isTracking(
            mangaId: manga.wrappedValue.identifier
        ))
    }

    private var total: Int { (manga.chapters ?? chapters).count }
    private var unread: Int { max(0, total - readCount) }
    private var readPercent: Int { total == 0 ? 0 : Int((Double(readCount) / Double(total) * 100).rounded()) }

    private var statusDot: Color {
        switch manga.status {
            case .completed: Color(red: 0.5, green: 0.65, blue: 1)
            case .hiatus, .cancelled: Color(uiColor: MDColor.amber)
            default: Color(uiColor: MDColor.mint)
        }
    }

    /// The Resume button's two lines.
    private var readButtonLines: (String, String?) {
        if allChaptersLocked { return (NSLocalizedString("ALL_CHAPTERS_LOCKED"), nil) }
        if allChaptersRead { return ("All caught up", "\(total) chapters read") }
        if source == nil { return (NSLocalizedString("UNAVAILABLE"), nil) }
        guard let chapter = nextChapter else { return (initialDataLoaded ? NSLocalizedString("NO_CHAPTERS_AVAILABLE") : NSLocalizedString("LOADING_ELLIPSIS"), nil) }
        return (readingInProgress ? "Resume" : "Start reading", chapter.formattedTitle(forceMode: chapterTitleDisplayMode))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MDEntryHero(
                title: manga.title,
                onCover: { coverPressed = true },
                onTitleHold: { onTitlePressed?() }
            ) {
                MangaCoverView(source: source, coverImage: manga.cover ?? "", width: 156, height: 234, title: manga.title)
                    .id(manga.cover ?? "")
                    .matchedTransitionSourcePlease(id: manga.identifier, in: transitionNamespace)
            } byline: {
                if let creators = creatorNames, !creators.isEmpty {
                    let value = creators.joined(separator: ", ")
                    Text(value)
                        .lineLimit(2)
                        .onTapGesture { copy(value) }
                        .onLongPressGesture { onCreatorPressed?(value) }
                }
            }

            HStack(spacing: 8) {
                let lines = readButtonLines
                MDResumeButton(
                    title: lines.0,
                    subtitle: lines.1,
                    systemImage: allChaptersRead ? "checkmark" : "play.fill",
                    disabled: readButtonDisabled || nextChapter == nil
                ) { onReadButtonPressed?() }
                MDSquareAction(systemImage: saveSymbol, label: saveTitle, active: isSaved, action: savePressed, onHold: showLibraryEditor)
                    .allowsHitTesting(isSaved || source != nil)
                if source != nil, !manga.isLocal() {
                    MDSquareAction(systemImage: "arrow.down.to.line", label: "Download unread chapters") { onDownloadUnread?() }
                }
                MDSquareAction(systemImage: "arrow.clockwise", label: "Refresh title", spinning: refreshing) { onRefresh?() }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)

            MDFactGrid(facts: [
                MDFact(label: "Chapters", value: initialDataLoaded ? "\(total)" : "…"),
                MDFact(label: "Unread", value: initialDataLoaded ? "\(unread)" : "…", valueColor: unread > 0 ? .mdAccent : .mdText),
                MDFact(label: "Read", value: "\(readPercent)%", progress: Double(readPercent) / 100),
                MDFact(label: "Source", value: source?.name ?? "—", note: hasAvailableTrackers ? (isTracking ? "tracking" : "track…") : nil,
                       action: hasAvailableTrackers ? { onTrackerButtonPressed?() } : nil),
                MDFact(label: "Status", value: manga.status == .unknown ? "Unknown" : manga.status.title, dot: manga.status == .unknown ? nil : statusDot),
                MDFact(label: "Library", value: isSaved ? saveTitle : "Not saved", note: isSaved ? "hold to edit" : "tap to save",
                       action: { if isSaved { showLibraryEditor() } else { savePressed() } })
            ])
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if (manga.description?.isEmpty == false) || !(manga.tags ?? []).isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if let description = manga.description, !description.isEmpty {
                        MDDescription(text: description)
                    }
                    tagsView
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }

            if let url = manga.url, url.scheme == "http" || url.scheme == "https" {
                Button {
                    path.present(SFSafariViewController(url: url))
                } label: {
                    Label("Open on the source's website", systemImage: "globe")
                        .font(.mdSystem(size: 13, weight: .semibold))
                        .foregroundStyle(Color.mdText2)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .simultaneousGesture(LongPressGesture().onEnded { finished in
                    if finished { UIPasteboard.general.string = url.absoluteString; longHeldSafari = true }
                })
            }

            // hide the chapter list header if there are no chapters and the other downloads header is shown
            if !(manga.chapters ?? chapters).isEmpty || !hasOtherDownloads {
                ChapterListHeaderView(
                    allChapters: manga.chapters,
                    filteredChapters: manga.chapters != nil ? chapters : (initialDataLoaded ? [] : nil),
                    sortOption: $chapterSortOption,
                    sortAscending: $chapterSortAscending,
                    filters: $filters,
                    langFilter: $langFilter,
                    scanlatorFilter: $scanlatorFilter,
                    displayMode: $chapterTitleDisplayMode,
                    mangaId: manga.identifier,
                    unreadCount: unread,
                    downloadedCount: downloadedCount
                )
                .padding(.horizontal, 16)
                .padding(.top, 28)
                .padding(.bottom, 4)
            }
        }
        .background(alignment: .top) {
            MDEntryBackdrop {
                MangaCoverView(source: source, coverImage: manga.cover ?? "", width: UIScreen.main.bounds.width, height: 470)
            }
            .padding(.top, -200)
        }
        .alert(NSLocalizedString("REMOVE_FROM_LIBRARY_CONFIRM"), isPresented: $showLibraryRemoveConfirm) {
            Button(NSLocalizedString("CANCEL"), role: .cancel) {}
            Button(NSLocalizedString("REMOVE"), role: .destructive) {
                guard bookmarked else { return }
                Task { await toggleBookmarked() }
            }
        } message: {
            Text(NSLocalizedString("REMOVE_FROM_LIBRARY_CONFIRM_TEXT"))
        }
        .alert(NSLocalizedString("LINK_COPIED"), isPresented: $longHeldSafari) {
            Button(NSLocalizedString("OK"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("LINK_COPIED_TEXT"))
        }
        .animation(.default, value: animationTrigger)
        .animation(.default, value: descriptionExpanded)
        .foregroundStyle(.primary)
        .textCase(.none)
        .background { MCEntryCategoryPresenter(entry: $categoryEntry, includeStatus: true).frame(width: 0, height: 0) }
        .onChange(of: manga) { _ in
            animationTrigger.toggle()
        }
        .onChange(of: nextChapter) { _ in
            updateReadButtonText()
        }
        .onChange(of: readingInProgress) { _ in
            updateReadButtonText()
        }
        .onChange(of: allChaptersLocked) { _ in
            updateReadButtonText()
        }
        .onChange(of: allChaptersRead) { _ in
            updateReadButtonText()
        }
        .onChange(of: source != nil) { _ in
            updateReadButtonText()
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateTrackers)) { _ in
            isTracking = TrackerManager.shared.isTracking(mangaId: manga.identifier)
        }
        .task {
            updateReadButtonText()
            hasAvailableTrackers = await TrackerManager.shared.hasAvailableTrackers(mangaId: manga.identifier)
        }
        .confirmationDialog(saveTitle, isPresented: $showPlacementOptions, titleVisibility: .visible) {
            switch placement {
            case .nested(let id, _):
                Button("Move to library top level") {
                    MCCollectionStore.shared.perform { try $0.library.moveEntry(id, into: nil) }
                }
                Button("Remove from library", role: .destructive) {
                    Task { await MangaManager.shared.removeFromLibrary(mangaId: manga.identifier); bookmarked = false }
                }
            case .linked:
                Button("Also save as a separate title") { Task { await addToLibrary() } }
            case .topLevel, .none:
                EmptyView()
            }
        } message: {
            switch placement {
            case .nested: Text("This title is nested inside another library title, so it does not appear at the top of your library.")
            case .linked: Text("This source is part of a merged library title.")
            case .topLevel, .none: EmptyView()
            }
        }
    }

    private var creatorNames: [String]? {
        let values = (manga.authors ?? []) + (manga.artists ?? [])
        let unique = values.reduce(into: [String]()) { result, value in
            if !result.contains(value) { result.append(value) }
        }
        return unique.isEmpty ? nil : unique
    }

    private func copy(_ value: String) {
        UIPasteboard.general.string = value
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @ViewBuilder
    var labelsView: some View {
        if manga.status != .unknown || (manga.contentRating != .unknown && manga.contentRating != .safe) || (bookmarked && source != nil) {
            HStack(spacing: 6) {
                if manga.status != .unknown {
                    LabelView(text: manga.status.title)
                }
                if manga.contentRating != .unknown && manga.contentRating != .safe {
                    LabelView(
                        text: manga.contentRating.title,
                        background: manga.contentRating == .suggestive
                            ? .orange.opacity(0.3)
                            : .red.opacity(0.3)
                    )
                }
                if let source, bookmarked {
                    LabelView(
                        text: source.name,
                        background: Color(red: 0.25, green: 0.55, blue: 1).opacity(0.3)
                    )
                }
            }
            .padding(.bottom, 8)
            .animation(.default, value: manga.status)
            .animation(.default, value: bookmarked)
        }
    }

    var buttonsView: some View {
        HStack(spacing: 8) {
            Button {
                savePressed()
            } label: {
                Image(systemName: saveSymbol)
            }
            .buttonStyle(MangaActionButtonStyle(selected: isSaved))
            .accessibilityLabel(saveTitle)
            .highPriorityGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                showLibraryEditor()
            })
            .alert(NSLocalizedString("REMOVE_FROM_LIBRARY_CONFIRM"), isPresented: $showLibraryRemoveConfirm) {
                Button(NSLocalizedString("CANCEL"), role: .cancel) {}
                Button(NSLocalizedString("REMOVE"), role: .destructive) {
                    guard bookmarked else { return }
                    Task {
                        await toggleBookmarked()
                    }
                }
            } message: {
                Text(NSLocalizedString("REMOVE_FROM_LIBRARY_CONFIRM_TEXT"))
            }

            if hasAvailableTrackers {
                Button {
                    onTrackerButtonPressed?()
                } label: {
                    Image(systemName: "clock.arrow.2.circlepath")
                }
                .buttonStyle(MangaActionButtonStyle(selected: isTracking))
            }

            if let url = manga.url {
                Button {
                    guard url.scheme == "http" || url.scheme == "https" else { return }
                    path.present(SFSafariViewController(url: url))
                } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(MangaActionButtonStyle())
                .transition(.opacity)
                .simultaneousGesture(
                    LongPressGesture()
                        .onEnded { finished in
                            if finished {
                                UIPasteboard.general.string = url.absoluteString
                                longHeldSafari = true
                            }
                        }
                )
                .alert(
                    NSLocalizedString("LINK_COPIED"),
                    isPresented: $longHeldSafari
                ) {
                    Button(NSLocalizedString("OK"), role: .cancel) {}
                } message: {
                    Text(NSLocalizedString("LINK_COPIED_TEXT"))
                }
            }
        }
    }

    @ViewBuilder
    var tagsView: some View {
        if let tags = manga.tags, !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        if let source, let filter = source.matchingGenreFilter(for: tag) {
                            Button {
                                let viewController = MangaListViewController(source: source, title: tag)
                                viewController.getEntries = { page in
                                    try await source.getSearchMangaList(query: nil, page: page, filters: [filter])
                                }
                                path.push(viewController)
                            } label: {
                                MDTag(text: tag)
                            }
                            .buttonStyle(.plain)
                        } else {
                            MDTag(text: tag)
                        }
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    func toggleBookmarked() async {
        guard !changingBookmark else { return }
        changingBookmark = true
        defer { changingBookmark = false }
        let mangaId = manga.identifier
        let store = MCCollectionStore.shared
        let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.hasLibraryManga(
                mangaId: mangaId,
                context: context
            )
        }
        if inLibrary || store.entryID(for: manga) != nil {
            // remove from library
            await MangaManager.shared.removeFromLibrary(mangaId: mangaId)
            bookmarked = false
        } else {
            await addToLibrary()
        }
    }

    private func addToLibrary() async {
        let store = MCCollectionStore.shared
        await store.importLegacyCategories()
        let categories: Set<UUID> = if let name = AppSettings.library.defaultCategory.get(),
            let category = store.snapshot.categories.first(where: { $0.name == name }) {
            [category.id]
        } else {
            []
        }
        do {
            _ = try store.add(manga, chapters: manga.chapters ?? chapters, categories: categories)
            bookmarked = true
            await MangaManager.shared.addToLibrary(manga: manga, chapters: manga.chapters ?? chapters)
        } catch {
            store.error = error.localizedDescription
        }
    }

    private func showLibraryEditor() {
        if let id = MCCollectionStore.shared.entryID(for: manga) {
            categoryEntry = MCID(id: id)
        } else {
            path.present(UIHostingController(rootView: MCAddSourceView(manga: manga, chapters: manga.chapters ?? chapters)))
        }
    }

    func updateReadButtonText() {
        var title = ""
        if allChaptersLocked {
            title = NSLocalizedString("ALL_CHAPTERS_LOCKED")
            readButtonDisabled = true
        } else if allChaptersRead {
            title = NSLocalizedString("ALL_CHAPTERS_READ")
            readButtonDisabled = true
        } else if source == nil {
            title = NSLocalizedString("UNAVAILABLE")
            readButtonDisabled = true
        } else {
            if let chapter = nextChapter {
                if !readingInProgress {
                    title = NSLocalizedString("START_READING")
                } else {
                    title = NSLocalizedString("CONTINUE_READING")
                }
                switch chapterTitleDisplayMode {
                    case .volume:
                        if let volumeNum = chapter.volumeNumber {
                            title += " " + String(format: NSLocalizedString("VOL_X"), volumeNum)
                        } else if let chapterNum = chapter.chapterNumber {
                            // Force display as volume if no volume number
                            title += " " + String(format: NSLocalizedString("VOL_X"), chapterNum)
                        }
                    case .chapter:
                        if let chapterNum = chapter.chapterNumber {
                            title += " " + String(format: NSLocalizedString("CH_X"), chapterNum)
                        } else if let volumeNum = chapter.volumeNumber {
                            // Force display as chapter if no chapter number
                            title += " " + String(format: NSLocalizedString("CH_X"), volumeNum)
                        }
                    case .default:
                        if let volumeNum = chapter.volumeNumber {
                            title += " " + String(format: NSLocalizedString("VOL_X"), volumeNum)
                        }
                        if let chapterNum = chapter.chapterNumber {
                            title += " " + String(format: NSLocalizedString("CH_X"), chapterNum)
                        }
                }
            } else {
                title = NSLocalizedString("NO_CHAPTERS_AVAILABLE")
            }
            readButtonDisabled = false
        }
        readButtonText = title
    }
}

struct LabelView: View {
    let text: String
    var background = Color(UIColor.tertiarySystemFill)

    var body: some View {
        Text(text)
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .font(.mdCaption2)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 0, style: .continuous))
    }
}

private struct TagView: View {
    let text: String

    var body: some View {
        Text(text)
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .font(.mdFootnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .textSelection(.enabled)
            .background(Color(UIColor.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 0))
    }
}

private struct MangaActionButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
//        Group {
//            if selected {
//                configuration.label
//                    .foregroundStyle(.white)
//            } else {
//                configuration.label
//                    .foregroundStyle(.tint)
//            }
//        }
        configuration.label
            .foregroundStyle(selected ? Color.white : Color.accentColor)
            .opacity(configuration.isPressed ? 0.4 : 1)
            .font(.mdSystem(size: 16, weight: .semibold))
            .frame(width: 40, height: 32)
            .background(selected ? Color.accentColor : Color(UIColor.secondarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 0, style: .continuous))
    }
}

@available(iOS 17.0, macOS 14.0, *)
#Preview {
    @Previewable @State var bookmarked = false
    @Previewable @State var chapterSortOption = ChapterSortOption.sourceOrder
    @Previewable @State var chapterSortAscending = false

    @Previewable @State var filters: [ChapterFilterOption] = []
    @Previewable @State var langFilter: String?
    @Previewable @State var scanlatorFilter: [String] = []
    @Previewable @State var chapterTitleDisplayMode = ChapterTitleDisplayMode.default
    @Previewable @Namespace var transitionNamespace

    MangaDetailsHeaderView(
        source: Binding.constant(AidokuRunner.Source.demo()),
        manga: Binding.constant(AidokuRunner.Manga(
            sourceKey: "",
            key: "",
            title: "Manga",
            authors: ["Author"],
            description: "Description"
        )),
        chapters: Binding.constant([]),
        nextChapter: Binding.constant(nil),
        readingInProgress: Binding.constant(false),
        allChaptersLocked: Binding.constant(false),
        allChaptersRead: Binding.constant(false),
        initialDataLoaded: Binding.constant(true),
        bookmarked: $bookmarked,
        hasCategories: Binding.constant(false),
        coverPressed: Binding.constant(false),
        chapterSortOption: $chapterSortOption,
        chapterSortAscending: $chapterSortAscending,
        filters: $filters,
        langFilter: $langFilter,
        scanlatorFilter: $scanlatorFilter,
        descriptionExpanded: Binding.constant(false),
        chapterTitleDisplayMode: $chapterTitleDisplayMode,
        hasOtherDownloads: false,
        transitionNamespace: transitionNamespace,
    )
}

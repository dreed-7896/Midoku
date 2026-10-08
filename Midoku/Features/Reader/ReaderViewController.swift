//
//  ReaderViewController.swift
//  Midoku (iOS)
//
//  Created by Skitty on 8/14/22.
//

import AidokuRunner
import SafariServices
import SwiftUI
import UIKit

/// The lazy grid creates image views only as their rows enter the sheet. Each
/// thumbnail uses the reader's page loader and shared Nuke pipeline, so a page
/// loaded here is available from the same cache when the reader displays it.
private struct ReaderPanelGrid: View {
    let pages: [Page]
    let temporaryPageStore: ReaderTemporaryPageStore
    let select: (Int) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Button { select(index + 1) } label: {
                            VStack(spacing: 4) {
                                ReaderPanelThumbnail(page: pages[index], temporaryPageStore: temporaryPageStore)
                                    .frame(height: 150).clipped()
                                    .background(Color(uiColor: .secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Text("\(index + 1)").font(.caption).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding(12)
            }
            .navigationTitle("View panels")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ReaderPanelThumbnail: UIViewRepresentable {
    let page: Page
    let temporaryPageStore: ReaderTemporaryPageStore

    final class Coordinator {
        var task: Task<Void, Never>?
        var pageKey: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ReaderPageView {
        ReaderPageView(temporaryPageStore: temporaryPageStore)
    }

    func updateUIView(_ view: ReaderPageView, context: Context) {
        let key = "\(page.chapterId):\(page.index)"
        guard context.coordinator.pageKey != key else { return }
        context.coordinator.task?.cancel()
        view.clearPage()
        context.coordinator.pageKey = key
        context.coordinator.task = Task {
            _ = await view.setPage(page, sourceId: page.sourceId)
        }
    }

    static func dismantleUIView(_ view: ReaderPageView, coordinator: Coordinator) {
        coordinator.task?.cancel()
        view.clearPage()
    }
}

class ReaderViewController: BaseObservingViewController {
    enum Reader {
        case paged
        case scroll
        case text
    }

    private let baseSource: AidokuRunner.Source?
    private let baseManga: AidokuRunner.Manga
    let collectionSequence: MCReaderSequence?
    var source: AidokuRunner.Source? { collectionSequence?.route(chapter)?.source ?? (collectionSequence == nil ? baseSource : nil) }
    var manga: AidokuRunner.Manga { collectionSequence?.route(chapter)?.manga ?? baseManga }

    func physicalChapter(_ chapter: AidokuRunner.Chapter) -> AidokuRunner.Chapter {
        collectionSequence?.route(chapter)?.chapter ?? chapter
    }
    func physicalIdentifier(_ chapter: AidokuRunner.Chapter) -> ChapterIdentifier {
        collectionSequence?.route(chapter)?.identifier ?? .init(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key)
    }
    var chapter: AidokuRunner.Chapter
    var pages: [Page] = []
    var readingMode: ReadingMode = .rtl
    var defaultReadingMode: ReadingMode?
    private var tapZone: TapZone?
    private let temporaryPageStore = ReaderTemporaryPageStore()

    private var chapterList: [AidokuRunner.Chapter]
    private var chaptersToMark: [AidokuRunner.Chapter] = []
    private var chaptersToRemoveDownload: [AidokuRunner.Chapter] = []
    private var forceStartPage: Int?
    private var currentPage = 1
    private var currentPosition: Double?
    private struct PendingProgress {
        let identifier: ChapterIdentifier
        let chapter: AidokuRunner.Chapter
        let page: Int
        let totalPages: Int
        let position: Double?
    }
    private struct PendingSession {
        let identifier: ChapterIdentifier
        let startDate: Date
        let endDate: Date
        let pagesRead: Int
    }
    private var pendingProgress: [ChapterIdentifier: PendingProgress] = [:]
    private var pendingCompletions: [ChapterIdentifier: AidokuRunner.Chapter] = [:]
    private var pendingSessions: [PendingSession] = []
    private var persistenceTask: Task<Void, Never>?
    private var persistenceGeneration = 0
    private var displayedPages: ClosedRange<Int>?
    private var displayedChapterKey: String?
    private var needsDescriptionUpdate = false
    private var needsPageControlUpdate = false
    private var sessionReadPages: Set<Int> = []
    private var sessionStartDate: Date?
    private var sessionLastInteraction: Date?
    var showPanelsOnOpen = false
    var isNavigationScreen = false
    var onNavigateBack: (() -> Void)?
    var onNavigationExit: (() -> Void)?
    private lazy var popGestureDelegate = ReaderPopGestureDelegate(reader: self)
    private let orientationRegistrationID = UUID()
    private var chapterLoadTask: Task<Void, Never>?
    private var hasExited = false
    private weak var readerTabBarController: UITabBarController?
    private var previousTabBarHidden: Bool?

    weak var reader: ReaderReaderDelegate?

    // Dictionary popup state
    private lazy var dictionaryCoordinator = ReaderDictionaryCoordinator(owner: self)
    private var _dictionaryLongPressSelection: Any?
    @available(iOS 18.0, *)
    private var dictionaryLongPressSelection: TextRecognizer.Result? {
        get { _dictionaryLongPressSelection as? TextRecognizer.Result }
        set { _dictionaryLongPressSelection = newValue }
    }
    private var isDictionaryOCRActiveForCurrentChapter: Bool {
        AppSettings.dictionary.isOCREnabled(language: chapter.language ?? source?.languages.first)
    }
    private var isDictionarySingleTapLookupActiveForCurrentChapter: Bool {
        AppSettings.dictionary.lookupGesture.get() == .singleTap && isDictionaryOCRActiveForCurrentChapter
    }
    private var isDictionaryLongPressLookupActiveForCurrentChapter: Bool {
        AppSettings.dictionary.lookupGesture.get() == .longPress && isDictionaryOCRActiveForCurrentChapter
    }

    private lazy var activityIndicator = UIActivityIndicatorView(style: .medium)
    let controlsView = ReaderControlsView()
    private var toolbarView: ReaderToolbarView { controlsView.toolbar }
    private(set) var readerControlsVisible = true

    private var squeezeTimer: Timer?
    private var longSqueezeTimer: Timer?
    private var squeezeStartTime: Date?
    private let doubleSqueezeInterval: TimeInterval = 0.3
    private let longSqueezeThreshold: TimeInterval = 0.5

    private lazy var descriptionButtonController: UIHostingController<ReaderPageDescriptionButtonView> = {
        let buttonView = ReaderPageDescriptionButtonView(source: source, pages: [])
        let hostingController = UIHostingController(rootView: buttonView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.alpha = 0
        hostingController.view.isHidden = true
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        return hostingController
    }()
    private lazy var descriptionTrailingConstraint =
        descriptionButtonController.view.trailingAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.trailingAnchor,
            constant: -16
        )
    private lazy var accessoryBottomWithControls = [
        descriptionButtonController.view.bottomAnchor.constraint(equalTo: controlsView.topAnchor, constant: -8)
    ]
    private lazy var accessoryBottomFullscreen = [
        descriptionButtonController.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
    ]

    private var barToggleTapGesture: UITapGestureRecognizer?
    private var barToggleSecondaryTapGesture: UITapGestureRecognizer?
    private var barDismissNavigationBarTapGesture: UITapGestureRecognizer?
    private var dictionaryLongPressGesture: UILongPressGestureRecognizer?

    var statusBarHidden = false

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        UIStatusBarAnimation.fade
    }
    override var prefersStatusBarHidden: Bool {
        statusBarHidden
    }
    override var prefersHomeIndicatorAutoHidden: Bool {
        statusBarHidden
    }

    init(
        source: AidokuRunner.Source?,
        manga: AidokuRunner.Manga,
        chapter: AidokuRunner.Chapter,
        startPage: Int? = nil,
        collectionSequence: MCReaderSequence? = nil
    ) {
        self.baseSource = source
        self.baseManga = manga
        self.collectionSequence = collectionSequence
        self.chapter = chapter
        self.chapterList = collectionSequence.map { Array($0.chapters.reversed()) } ?? manga.chapters ?? []
        self.chaptersToMark = [chapter]
        self.defaultReadingMode = switch manga.viewer {
            case .rightToLeft: .rtl
            case .leftToRight: .ltr
            case .vertical: .vertical
            case .webtoon: .webtoon
            case .unknown: .none
        }
        self.forceStartPage = startPage
        super.init()
    }

    deinit {
        Task { [temporaryPageStore] in
            await temporaryPageStore.removeAll()
        }
    }

    override func configure() {
        node.backgroundColor = .systemBackground
        if !isNavigationScreen { navigationController?.navigationBar.prefersLargeTitles = false }

        navigationController?.setNavigationBarHidden(true, animated: false)
        navigationController?.isToolbarHidden = true
        controlsView.closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        controlsView.chaptersButton.addTarget(self, action: #selector(openChapterList), for: .touchUpInside)
        controlsView.panelsButton.addTarget(self, action: #selector(openPanels), for: .touchUpInside)
        controlsView.settingsButton.addTarget(self, action: #selector(openReaderSettings), for: .touchUpInside)
        controlsView.webButton.addTarget(self, action: #selector(openWebView), for: .touchUpInside)
        controlsView.autoScrollButton.addTarget(self, action: #selector(toggleAutoScroll), for: .touchUpInside)
        loadNavbarTitle()

        toolbarView.sliderView.addTarget(self, action: #selector(sliderMoved(_:)), for: .valueChanged)
        toolbarView.sliderView.addTarget(self, action: #selector(sliderStopped(_:)), for: .editingDidEnd)
        toolbarView.previousChapterButton.addTarget(self, action: #selector(previousChapter), for: .touchUpInside)
        toolbarView.nextChapterButton.addTarget(self, action: #selector(nextChapter), for: .touchUpInside)
        updateChapterButtons()
        add(child: descriptionButtonController)
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsView)

        // loading indicator
        activityIndicator.startAnimating()
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)

        // initialize dictionary engine
        if
            #available(iOS 18.0, *),
            AppSettings.dictionary.enable.get()
                {
            DictionaryManager.shared.rebuildLookupQuery()
        }
        configureDictionaryLookupGesture()
        configureDictionaryOverlayInteractionMode()

        // bar toggle tap gesture
        configureBarToggleTapGestures()

        // page offset tap gesture
        let pageOffsetGesture = UITapGestureRecognizer(target: self, action: #selector(toggleOffset))
        pageOffsetGesture.numberOfTouchesRequired = 2
        pageOffsetGesture.numberOfTapsRequired = 2
        view.addGestureRecognizer(pageOffsetGesture)

        // set reader
        let readingModeKey = "Reader.readingMode.\(manga.identifier)"
        UserDefaults.standard.register(defaults: [readingModeKey: "default"])
        setReadingMode(UserDefaults.standard.string(forKey: readingModeKey))

        // set up apple pencil squeeze handler
        if #available(iOS 17.5, *) {
            let pencilInteraction = UIPencilInteraction(delegate: self)
            view.addInteraction(pencilInteraction)
        }

        // load current tap zone
        updateTapZone()

        // load chapter list
        loadCurrentChapter()
    }

    override func constrain() {
        let panelWidth = controlsView.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, constant: -32)
        panelWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            panelWidth,
            controlsView.widthAnchor.constraint(lessThanOrEqualToConstant: 600),
            controlsView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            controlsView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        descriptionTrailingConstraint.isActive = true
        NSLayoutConstraint.activate(accessoryBottomWithControls)

        updateAutoScrollButton()
    }

    override func observe() {
        addObserver(forName: "Reader.readingMode.\(manga.identifier)") { [weak self] _ in
            guard let self else { return }
            self.setReadingMode(UserDefaults.standard.string(forKey: "Reader.readingMode.\(self.manga.identifier)"))
            self.reader?.setChapter(self.chapter, startPage: self.currentPage)
            // if the tap zone is auto, it will changed based on the current reader
            self.updateTapZone()
        }
        addObserver(forName: "Reader.disableDoubleTap") { [weak self] _ in
            self?.configureBarToggleTapGestures()
        }
        addObserver(forName: "Reader.autoScroll") { [weak self] _ in
            self?.updateAutoScrollButton()
        }
        addObserver(forName: .readerTapZones) { [weak self] _ in
            self?.updateTapZone()
        }
        let reloadBlock: (Notification) -> Void = { [weak self] _ in
            guard let self else { return }
            self.reader?.setChapter(self.chapter, startPage: self.currentPage)
        }
        // reload pages when processors change
        addObserver(forName: "Reader.downsampleImages", using: reloadBlock)
        addObserver(forName: "Reader.upscaleImages", using: reloadBlock)
        addObserver(forName: "Reader.cropBorders", using: reloadBlock)
        addObserver(forName: "Reader.liveText", using: reloadBlock)
        addObserver(forName: AppSettings.dictionary.overlayPadding.key, using: reloadBlock)
        addObserver(forName: AppSettings.dictionary.overlayTextScaleMultiplier.key, using: reloadBlock)
        let dictionaryReloadBlock: (Notification) -> Void = { [weak self] _ in
            guard let self else { return }
            self.configureBarToggleTapGestures()
            self.configureDictionaryLookupGesture()
            self.configureDictionaryOverlayInteractionMode()
            self.reader?.setChapter(self.chapter, startPage: self.currentPage)
        }
        for key in [
            AppSettings.dictionary.enable.key,
            AppSettings.dictionary.lookupGesture.key,
            AppSettings.dictionary.textOverlayMode.key,
            AppSettings.dictionary.restrictOCRLanguages.key,
            AppSettings.dictionary.restrictedOCRLanguages.key
        ] {
            addObserver(forName: key, using: dictionaryReloadBlock)
        }
        addObserver(forName: .dictionaryDictionariesChanged, using: dictionaryReloadBlock)
        // Switch text reader style (paged <-> scroll) without restart
        addObserver(forName: "Reader.textReaderStyle") { [weak self] _ in
            guard let self else { return }
            // Only switch if we're currently in a text reader
            if self.reader is ReaderTextViewController || self.reader is ReaderPagedTextViewController {
                // Save current position before switching so the new reader can restore it
                Task {
                    await self.updateReadPosition()
                    await MainActor.run {
                        self.setReader(.text)
                        self.reader?.setChapter(self.chapter, startPage: self.currentPage)
                        self.updateTapZone()
                    }
                }
            }
        }
        addObserver(forName: ReaderTextTheme.changeNotification) { [weak self] _ in
            self?.updateTextThemeOverride()
        }
        addObserver(forName: .readerOrientation) { [weak self] _ in
            self?.registerScreenOrientation()
        }
        addObserver(forName: UIScene.willDeactivateNotification) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.updateReadPosition()
            }

            if #available(iOS 26.0, *) {
                statusBarHidden = false
            }
        }
        addObserver(forName: UIScene.didActivateNotification) { [weak self] _ in
            guard let self else { return }
            if self.sessionStartDate == nil {
                self.sessionReadPages = [self.currentPage]
                self.sessionStartDate = Date.now
                self.sessionLastInteraction = nil
            }
        }
        if #available(iOS 26.0, *) {
            addObserver(forName: UIScene.willEnterForegroundNotification) { [weak self] _ in
                if self?.navigationController?.toolbar.alpha == 0 {
                    self?.hideBars()
                }
            }
        }
        addObserver(forName: "Reader.autoScroll") { [weak self] _ in
            self?.updateAutoScrollButton()
        }

    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hideAppTabBar()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // SwiftUI can update its hosting navigation controller during the push.
        hideAppTabBar()

        sessionReadPages = [self.currentPage]
        sessionStartDate = Date.now
        sessionLastInteraction = nil

        navigationController?.setNavigationBarHidden(true, animated: false)
        navigationController?.isToolbarHidden = true
        view.bringSubviewToFront(controlsView)

        if showPanelsOnOpen && !pages.isEmpty {
            showPanelsOnOpen = false
            openPanels()
        }

        if isNavigationScreen, let navigationController {
            popGestureDelegate.install(on: navigationController)
            registerScreenOrientation()
        }
        configureNavigationBarDismissTapGesture(enabled: isDictionarySingleTapLookupActiveForCurrentChapter)

        // resume auto scroll if it was paused when presenting a sheet
        if let reader = reader as? ReaderWebtoonViewController {
            reader.resumeAutoScroll()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        (reader as? ReaderWebtoonViewController)?.captureReadingPosition()
        (reader as? ReaderWebtoonViewController)?.stopAutoScroll()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        popGestureDelegate.restore()
        InterfaceOrientationCoordinator.shared.unregister(orientationsWithID: orientationRegistrationID)
        if isNavigationScreen, let gesture = barDismissNavigationBarTapGesture {
            gesture.view?.removeGestureRecognizer(gesture)
            barDismissNavigationBarTapGesture = nil
        }
        if isNavigationScreen, isMovingFromParent || navigationController == nil {
            finishNavigationExit()
        }

        if !chaptersToRemoveDownload.isEmpty {
            let identifiers = chaptersToRemoveDownload.map { physicalIdentifier($0) }
            chaptersToRemoveDownload = []
            UserDefaults.standard.set(try? JSONEncoder().encode(identifiers), forKey: "Data.chaptersToBeDeleted")
            Task {
                await DownloadManager.shared.delete(chapters: identifiers)
                UserDefaults.standard.removeObject(forKey: "Data.chaptersToBeDeleted")
            }
        }

        // Keep persistence and its library notifications out of the dismissal
        // animation as well as out of scrolling.
        Task {
            await updateReadPosition()
        }
    }
}

extension ReaderViewController {
    @objc func openPanels() {
        guard !pages.isEmpty else { return }
        (reader as? ReaderWebtoonViewController)?.stopAutoScroll()
        let grid = ReaderPanelGrid(pages: pages, temporaryPageStore: temporaryPageStore) { [weak self] page in
            guard let self else { return }
            self.dismiss(animated: true) {
                if let webtoon = self.reader as? ReaderWebtoonViewController {
                    webtoon.jumpToPage(page)
                } else if let paged = self.reader as? ReaderPagedViewController {
                    paged.jumpToActualPage(page)
                } else {
                    self.reader?.setChapter(self.chapter, startPage: page)
                }
            }
        }
        let controller = UIHostingController(rootView: grid)
        if let sheet = controller.sheetPresentationController { sheet.detents = [.medium(), .large()] }
        present(controller, animated: true)
    }

    private func stageReadPosition(
        currentPage: Int? = nil,
        totalPages: Int? = nil,
        chapter: AidokuRunner.Chapter? = nil,
        scrollPosition: Double? = nil
    ) {
        let effectiveTotalPages = totalPages ?? toolbarView.totalPages ?? 0
        let effectiveCurrentPage = currentPage ?? self.currentPage

        guard
            !AppSettings.general.incognitoMode.get(),
            effectiveTotalPages > 0 // ensure chapter pages are loaded
        else {
            return
        }

        let currentPage = effectiveCurrentPage
        let chapter = chapter ?? self.chapter
        let position = scrollPosition ?? currentPosition

        let chapterId = physicalIdentifier(chapter)
        pendingProgress[chapterId] = PendingProgress(
            identifier: chapterId,
            chapter: physicalChapter(chapter),
            page: currentPage,
            totalPages: effectiveTotalPages,
            position: position
        )
    }

    private func stageReadingSession() {
        guard let sessionStartDate else { return }
        let pagesRead = sessionReadPages.count
        if pagesRead > 0, sessionLastInteraction != nil, !AppSettings.general.incognitoMode.get() {
            pendingSessions.append(PendingSession(identifier: physicalIdentifier(chapter),
                                                  startDate: sessionStartDate, endDate: .now, pagesRead: pagesRead))
        }
        self.sessionStartDate = nil
    }

    /// Called only when leaving the reader, deactivating the app, or explicitly
    /// replacing the text reader. Chapter crossings only stage updates in memory.
    func updateReadPosition() async {
        if !hasExited { (reader as? ReaderWebtoonViewController)?.captureReadingPosition() }
        stageReadPosition()
        stageReadingSession()
        ReaderProgressStore.flush()

        let progress = Array(pendingProgress.values)
        let completions = pendingCompletions
        let sessions = pendingSessions
        pendingProgress.removeAll(keepingCapacity: true)
        pendingCompletions.removeAll(keepingCapacity: true)
        pendingSessions.removeAll(keepingCapacity: true)
        guard !progress.isEmpty || !completions.isEmpty || !sessions.isEmpty else { return }

        // Backgrounding and closing can overlap. Snapshot before suspending and
        // serialize saves so an older checkpoint cannot replace a newer one.
        let previousTask = persistenceTask
        persistenceGeneration += 1
        let generation = persistenceGeneration
        let task = Task {
            await previousTask?.value
            let completionsByManga = Dictionary(grouping: completions, by: { $0.key.mangaIdentifier })
            for (mangaId, items) in completionsByManga {
                await HistoryManager.shared.addHistory(mangaId: mangaId, chapters: items.map { $0.value })
            }
            for item in progress {
                let identifier = item.identifier
                let (completed, _) = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.getProgress(chapterId: identifier, context: context)
                }
                await HistoryManager.shared.setProgress(chapterId: item.identifier, chapter: item.chapter,
                    progress: item.page, totalPages: item.totalPages, scrollPosition: item.position, completed: completed)
            }
            for session in sessions {
                await HistoryManager.shared.addSession(chapterId: session.identifier,
                    data: .init(startDate: session.startDate, endDate: session.endDate, pagesRead: session.pagesRead))
            }
        }
        persistenceTask = task
        await task.value
        if persistenceGeneration == generation { persistenceTask = nil }
    }

    func loadChapterList() async {
        if collectionSequence != nil { return }
        let updatedManga = try? await source?.getMangaUpdate(
            manga: manga,
            needsDetails: false,
            needsChapters: true
        )
        chapterList = updatedManga?.chapters ?? []
        updateChapterButtons()
    }

    func loadCurrentChapter() {
        if chapterList.isEmpty {
            Task {
                await loadChapterList()
            }
        }

        let requestedChapter = chapter
        let identifier = physicalIdentifier(requestedChapter)
        let explicitPage = forceStartPage
        forceStartPage = nil
        chapterLoadTask?.cancel()
        chapterLoadTask = Task { [weak self] in
            let (_, historyPage) = await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.getProgress(chapterId: identifier, context: context)
            }
            guard let self, !hasExited, !Task.isCancelled, chapter == requestedChapter else { return }
            let local = ReaderProgressStore.position(for: identifier)
            currentPage = max(1, explicitPage ?? local?.page ?? historyPage ?? 1)
            currentPosition = explicitPage == nil ? local?.scrollPosition : nil
            reader?.setChapter(requestedChapter, startPage: currentPage)
        }
    }

    func loadNavbarTitle() {
        let volume: String? =
            if chapter.chapterNumber != nil, let volumeNum = chapter.volumeNumber {
                String(format: NSLocalizedString("VOLUME_X"), volumeNum)
            } else {
                nil
            }

        let title =
            if let chapterNum = chapter.chapterNumber {
                String(format: NSLocalizedString("CHAPTER_X"), chapterNum)
            } else if let volumeNum = chapter.volumeNumber {
                String(format: NSLocalizedString("VOLUME_X"), volumeNum)
            } else {
                chapter.title ?? ""
            }

        navigationItem.setTitle(upper: volume, lower: title)
        controlsView.webButton.isEnabled = chapter.url != nil
        // re-apply theme title colors, since setTitle recreates the title view
        updateTextThemeOverride()
    }

    func showLoadFailAlert() {
        let alert = UIAlertController(
            title: NSLocalizedString("FAILED_CHAPTER_LOAD"),
            message: NSLocalizedString("FAILED_CHAPTER_LOAD_INFO"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK"), style: .cancel))
        present(alert, animated: true)
    }

    @objc func openReaderSettings() {
        (reader as? ReaderWebtoonViewController)?.stopAutoScroll()

        let currentReader: Reader
        switch reader {
            case is ReaderTextViewController, is ReaderPagedTextViewController:
                currentReader = .text
            case is ReaderPagedViewController:
                currentReader = .paged
            case is ReaderWebtoonViewController:
                currentReader = .scroll
            default:
                currentReader = .paged
        }
        let vc = UIHostingController(
            rootView: ReaderSettingsView(
                mangaId: manga.identifier,
                reader: currentReader,
                chapterLanguage: chapter.language ?? source?.languages.first
            )
        )
        if currentReader == .text {
            vc.overrideUserInterfaceStyle = ReaderTextTheme.getInterfaceStyleOverride()
        }
        present(vc, animated: true)
    }

    @objc func openWebView() {
        guard let url = chapter.url, url.scheme == "http" || url.scheme == "https" else { return }
        (reader as? ReaderWebtoonViewController)?.stopAutoScroll()
        present(SFSafariViewController(url: url), animated: true)
    }

    @objc func openChapterList() {
        (reader as? ReaderWebtoonViewController)?.stopAutoScroll()

        var view = ReaderChapterListView(
            chapterList: chapterList,
            chapter: chapter,
            collectionSequence: collectionSequence
        )
        view.chapterSet = { [weak self] chapter in
            guard let self else { return }
            if chapter != self.chapter {
                self.setChapter(chapter)
                self.loadCurrentChapter()
            }
        }
        present(UIHostingController(rootView: view), animated: true)
    }

    @objc func close() {
        (reader as? ReaderWebtoonViewController)?.captureReadingPosition()
        hasExited = true
        chapterLoadTask?.cancel()
        // viewDidDisappear saves the final position; temporary files are removed on deinit,
        // after page requests have released them (including cancelled interactive dismissals).
        if isNavigationScreen {
            if let onNavigateBack { onNavigateBack() }
            else { navigationController?.popViewController(animated: true) }
        } else { dismiss(animated: true) }
    }

    func finishNavigationExit() {
        (reader as? ReaderWebtoonViewController)?.captureReadingPosition()
        hasExited = true
        chapterLoadTask?.cancel()
        popGestureDelegate.restore()
        InterfaceOrientationCoordinator.shared.unregister(orientationsWithID: orientationRegistrationID)
        restoreAppTabBar()
        onNavigationExit?()
        onNavigationExit = nil
    }

    private func hideAppTabBar() {
        guard isNavigationScreen, let controller = tabBarController else { return }
        if previousTabBarHidden == nil {
            readerTabBarController = controller
            if #available(iOS 26.0, *) {
                previousTabBarHidden = controller.isTabBarHidden
            } else {
                previousTabBarHidden = controller.tabBar.isHidden
            }
        }
        // The app uses a UIKit tab controller outside the SwiftUI navigation stack.
        // SwiftUI's tab-bar toolbar preference cannot hide that controller's Search tab.
        if #available(iOS 26.0, *) {
            controller.setTabBarHidden(true, animated: false)
        } else {
            controller.tabBar.isHidden = true
        }
    }

    private func restoreAppTabBar() {
        guard let controller = readerTabBarController, let hidden = previousTabBarHidden else { return }
        previousTabBarHidden = nil
        readerTabBarController = nil
        if #available(iOS 26.0, *) {
            controller.setTabBarHidden(hidden, animated: false)
        } else {
            controller.tabBar.isHidden = hidden
        }
    }

    private func registerScreenOrientation() {
        guard isNavigationScreen, viewIfLoaded?.window != nil else { return }
        let orientations: UIInterfaceOrientationMask
        switch UserDefaults.standard.string(forKey: "Reader.orientation") {
        case "portrait": orientations = .portrait
        case "landscape": orientations = .landscape
        default: orientations = .all
        }
        InterfaceOrientationCoordinator.shared.register(orientations: orientations, id: orientationRegistrationID)
    }

    @objc func sliderMoved(_ sender: ReaderSliderView) {
        reader?.sliderMoved(value: sender.currentValue)
    }
    @objc func sliderStopped(_ sender: ReaderSliderView) {
        reader?.sliderStopped(value: sender.currentValue)
    }
}

// MARK: - Reading Mode
extension ReaderViewController {
    func setReadingMode(_ mode: String?) {
        switch mode {
            case "rtl": readingMode = .rtl
            case "ltr": readingMode = .ltr
            case "vertical": readingMode = .vertical
            case "scroll", "webtoon": readingMode = .webtoon
            case "continuous": readingMode = .continuous
            case "default":
                let defaultMode = UserDefaults.standard.string(forKey: "Reader.readingMode")
                if defaultMode == "default" {
                    setReadingMode("auto")
                } else {
                    setReadingMode(defaultMode)
                }
                return
            default: // auto
                // use given default reading mode
                if let defaultReadingMode {
                    readingMode = defaultReadingMode
                } else if CoreDataManager.shared.hasManga(mangaId: manga.identifier) {
                    // fall back to stored manga viewer
                    let sourceMode = CoreDataManager.shared.getMangaSourceReadingMode(mangaId: manga.identifier)
                    if let mode = ReadingMode(rawValue: sourceMode) {
                        readingMode = mode
                    } else {
                        readingMode = .rtl
                    }
                } else {
                    // fall back to rtl reading mode
                    readingMode = .rtl
                }
        }

        if !(reader is ReaderTextViewController) {
            switch readingMode {
                case .ltr, .rtl, .vertical:
                    setReader(.paged)
                case .webtoon, .continuous:
                    setReader(.scroll)
            }
        }
    }

    func setReader(_ type: Reader) {
        let pageController: ReaderReaderDelegate?
        switch type {
            case .paged:
                if readingMode == .rtl {
                    toolbarView.sliderView.direction = .backward
                } else {
                    toolbarView.sliderView.direction = .forward
                }
                if !(reader is ReaderPagedViewController) {
                    pageController = ReaderPagedViewController(source: source, manga: manga, temporaryPageStore: temporaryPageStore)
                } else {
                    pageController = nil
                }
            case .scroll:
                toolbarView.sliderView.direction = .forward
                if !(reader is ReaderWebtoonViewController) {
                    pageController = ReaderWebtoonViewController(source: source, manga: manga, temporaryPageStore: temporaryPageStore)
                } else {
                    pageController = nil
                }
            case .text:
                // Text always reads left-to-right, regardless of manga setting
                toolbarView.sliderView.direction = .forward

                // Check user preference for text reader style
                let textReaderStyle = UserDefaults.standard.string(forKey: "Reader.textReaderStyle") ?? "paged"
                if textReaderStyle == "paged" {
                    // Kindle-like paginated experience
                    if !(reader is ReaderPagedTextViewController) {
                        pageController = ReaderPagedTextViewController(source: source, manga: manga)
                    } else {
                        pageController = nil
                    }
                } else {
                    // Original scroll-based text reader
                    if !(reader is ReaderTextViewController) {
                        pageController = ReaderTextViewController(source: source, manga: manga)
                    } else {
                        pageController = nil
                    }
                }
        }
        if let pageController {
            (pageController as? ReaderPagedViewController)?.viewModel.collectionSequence = collectionSequence
            (pageController as? ReaderWebtoonViewController)?.viewModel.collectionSequence = collectionSequence
            (pageController as? ReaderPagedTextViewController)?.viewModel.collectionSequence = collectionSequence
            (pageController as? ReaderTextViewController)?.viewModel.collectionSequence = collectionSequence
            if let webtoonReader = reader as? ReaderWebtoonViewController {
                webtoonReader.stopAutoScroll()
            }
            reader?.remove()
            pageController.delegate = self
            reader = pageController
            add(child: pageController, below: descriptionButtonController.view)
        }
        reader?.readingMode = readingMode
        configureDictionaryOverlayInteractionMode()
        configureDictionaryOverlayTapHandler()
        updateAutoScrollButton()
        view.bringSubviewToFront(controlsView)
        updateTextThemeOverride()
    }

    func updateTextThemeOverride() {
        let theme = ReaderTextTheme.getCurrent()
        let isTextReader = reader is ReaderTextViewController || reader is ReaderPagedTextViewController
        let styleOverride: UIUserInterfaceStyle = isTextReader ? ReaderTextTheme.getInterfaceStyleOverride() : .unspecified
        if isNavigationScreen { overrideUserInterfaceStyle = styleOverride }
        else { navigationController?.overrideUserInterfaceStyle = styleOverride }
        // presented sheets don't inherit the override
        presentedViewController?.overrideUserInterfaceStyle = styleOverride
        let themed = isTextReader && (theme != .default || styleOverride != .unspecified)

        // the bar appearance objects don't follow the trait override,
        // so the theme colors are written into them directly
        let backgroundColor = ReaderTextTheme.getCurrentBackground()
        let textColor = ReaderTextTheme.getCurrentText()
        let titleColor = themed ? textColor : nil
        if !isNavigationScreen, let navigationBar = navigationController?.navigationBar {
            func applyTheme(_ appearance: UINavigationBarAppearance) {
                if themed {
                    if #available(iOS 26.0, *), reader is ReaderTextViewController {
                        // text scrolls under the bar, so keep it transparent
                        appearance.configureWithTransparentBackground()
                    } else {
                        // nothing extends under the bar, so match the page color
                        appearance.backgroundEffect = nil
                        appearance.backgroundColor = backgroundColor
                        appearance.shadowColor = .clear
                    }
                    appearance.titleTextAttributes[.foregroundColor] = textColor
                } else {
                    appearance.configureWithDefaultBackground()
                    appearance.titleTextAttributes.removeValue(forKey: .foregroundColor)
                }
            }
            let standard = navigationBar.standardAppearance
            applyTheme(standard)
            navigationBar.standardAppearance = standard
            if let compact = navigationBar.compactAppearance {
                applyTheme(compact)
                navigationBar.compactAppearance = compact
            }
            if let scrollEdge = navigationBar.scrollEdgeAppearance {
                applyTheme(scrollEdge)
                navigationBar.scrollEdgeAppearance = scrollEdge
            }
        }
        // the two-line title view (volume + chapter) uses plain labels instead
        if let stackView = navigationItem.titleView as? UIStackView {
            let labels = stackView.arrangedSubviews.compactMap { $0 as? UILabel }
            if labels.count == 2 {
                labels[0].textColor = titleColor?.withAlphaComponent(0.6) ?? .secondaryLabel
                labels[1].textColor = titleColor ?? .label
            }
        }
    }
}

// MARK: - Auto Scroll
extension ReaderViewController {
    @objc private func toggleAutoScroll() {
        guard let webtoonReader = reader as? ReaderWebtoonViewController else { return }
        if !webtoonReader.isAutoScrolling {
            UserDefaults.standard.set(true, forKey: "Reader.autoScroll")
        }
        webtoonReader.toggleAutoScroll()
        updateAutoScrollButtonIcon()
    }

    private func updateAutoScrollButton() {
        let webtoonReader = reader as? ReaderWebtoonViewController
        if !UserDefaults.standard.bool(forKey: "Reader.autoScroll") {
            webtoonReader?.stopAutoScroll()
        }
        webtoonReader?.onAutoScrollStateChange = { [weak self] _ in
            self?.updateAutoScrollButtonIcon()
        }
        webtoonReader?.onContentScrollingChange = { [weak self] scrolling in
            if !scrolling { self?.renderCurrentPageControls() }
        }
        controlsView.autoScrollButton.isEnabled = webtoonReader != nil
        updateAutoScrollButtonIcon()
    }

    private func updateAutoScrollButtonIcon() {
        let isAutoScrolling = (reader as? ReaderWebtoonViewController)?.isAutoScrolling == true
        controlsView.autoScrollButton.configuration?.image = UIImage(systemName: isAutoScrolling ? "pause.fill" : "play.fill")
        controlsView.autoScrollButton.accessibilityLabel = isAutoScrolling ? "Pause auto scroll" : "Start auto scroll"
    }
}

// MARK: - Reader Holding Delegate
extension ReaderViewController: @MainActor ReaderHoldingDelegate {
    var barsHidden: Bool { statusBarHidden }

    private func areDuplicates(_ a: AidokuRunner.Chapter, _ b: AidokuRunner.Chapter) -> Bool {
        a.chapterNumber == b.chapterNumber
            && a.volumeNumber == b.volumeNumber
            && (!(a.chapterNumber == nil && a.volumeNumber == nil) || a.title == b.title)
    }

    private func isValidScanlatorMatch(for next: AidokuRunner.Chapter, current: Set<String>) -> Bool {
        let nextScanlators = Set(next.scanlators ?? [])
        return current.isEmpty ? nextScanlators.isEmpty : !current.isDisjoint(with: nextScanlators)
    }

    private func findBestChapterMatch(from index: Int, step: Int) -> AidokuRunner.Chapter {
        let firstCandidate = chapterList[index]
        let currentScanlators = Set(chapter.scanlators ?? [])

        var i = index
        while i >= 0 && i < chapterList.count {
            let next = chapterList[i]
            guard areDuplicates(next, firstCandidate) else { break }

            let identifier = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: next.key)
            let isReadable = !next.locked || DownloadManager.shared.getDownloadStatus(for: identifier) == .finished

            if isReadable && isValidScanlatorMatch(for: next, current: currentScanlators) {
                return next
            }
            i += step
        }

        return firstCandidate
    }

    func getNextChapter() -> AidokuRunner.Chapter? {
        resolveNextChapter(markingDuplicates: true)
    }

    private func resolveNextChapter(markingDuplicates: Bool) -> AidokuRunner.Chapter? {
        if let collectionSequence { return collectionSequence.adjacent(to: chapter, offset: 1) }
        guard
            var index = chapterList.firstIndex(of: chapter)
        else {
            return nil
        }

        let skipDuplicates = UserDefaults.standard.bool(forKey: "Reader.skipDuplicateChapters")
        let markDuplicates = UserDefaults.standard.bool(forKey: "Reader.markDuplicateChapters")

        index -= 1
        var nextChapterInList: AidokuRunner.Chapter?

        while index >= 0 {
            let new = chapterList[index]
            let identifier = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: new.key)

            let readable = !new.locked
                || DownloadManager.shared.getDownloadStatus(for: identifier) == .finished

            if readable {
                let isDuplicate = areDuplicates(new, chapter)

                if nextChapterInList == nil {
                    nextChapterInList = new
                }
                if markingDuplicates && markDuplicates && isDuplicate {
                    chaptersToMark.append(new)
                }
                if !isDuplicate {
                    return skipDuplicates ? findBestChapterMatch(from: index, step: -1) : nextChapterInList
                } else if !skipDuplicates && !markDuplicates {
                    return new
                }
            }
            index -= 1
        }
        return nil
    }

    func getPreviousChapter() -> AidokuRunner.Chapter? {
        resolvePreviousChapter(markingDuplicates: true)
    }

    private func resolvePreviousChapter(markingDuplicates: Bool) -> AidokuRunner.Chapter? {
        if let collectionSequence { return collectionSequence.adjacent(to: chapter, offset: -1) }
        guard
            var index = chapterList.firstIndex(of: chapter)
        else {
            return nil
        }
        // find previous non-duplicate chapter
        let markDuplicates = UserDefaults.standard.bool(forKey: "Reader.markDuplicateChapters")

        index += 1
        while index < chapterList.count {
            let new = chapterList[index]
            let identifier = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: new.key)

            let readable = !new.locked
                || DownloadManager.shared.getDownloadStatus(for: identifier) == .finished

            if readable {
                let isDuplicate = areDuplicates(new, chapter)
                if !isDuplicate {
                    return findBestChapterMatch(from: index, step: 1)
                }
                if markingDuplicates && markDuplicates {
                    chaptersToMark.append(new)
                }
            }
            index += 1
        }
        return nil
    }

    func setChapter(_ chapter: AidokuRunner.Chapter) {
        guard chapter != self.chapter else { return }

        // Infinite scrolling crosses chapters while momentum is still active.
        // Capture the outgoing chapter synchronously without starting disk work.
        stageReadPosition()
        stageReadingSession()
        sessionReadPages = []
        sessionStartDate = .now
        sessionLastInteraction = nil

        self.chapter = chapter
        chapterLoadTask?.cancel()
        currentPosition = nil
        updateChapterButtons()
        self.chaptersToMark = [chapter]
        configureBarToggleTapGestures()
        configureDictionaryLookupGesture()
        configureDictionaryOverlayInteractionMode()
        loadNavbarTitle()
    }

    private func updateChapterButtons() {
        toolbarView.previousChapterButton.isEnabled = resolvePreviousChapter(markingDuplicates: false) != nil
        toolbarView.nextChapterButton.isEnabled = resolveNextChapter(markingDuplicates: false) != nil
    }

    func setCurrentPage(_ page: Int, position: Double? = nil) {
        setCurrentPages(page...page, position: position)
    }

    func setCurrentPages(_ pages: ClosedRange<Int>) {
        setCurrentPages(pages, position: nil)
    }

    private func setCurrentPages(_ pages: ClosedRange<Int>, position: Double? = nil) {
        guard !hasExited, let totalPages = toolbarView.totalPages, totalPages > 0 else { return }

        let page = max(1, min(pages.lowerBound, totalPages))
        let changedPage = displayedPages != pages || displayedChapterKey != chapter.key
        if changedPage {
            displayedPages = pages
            displayedChapterKey = chapter.key
            needsDescriptionUpdate = true
            needsPageControlUpdate = true
        }

        sessionLastInteraction = Date.now
        for page in pages {
            guard page >= 1 && page <= totalPages else { continue }
            sessionReadPages.insert(page)
        }

        currentPage = page
        currentPosition = position
        ReaderProgressStore.record(identifier: physicalIdentifier(chapter), page: page,
                                   scrollPosition: position, slotID: collectionSequence?.route(chapter)?.slotID)
        if changedPage {
            renderCurrentPageControls()
        }
        // No timer, disk save, library notification or tracker request while
        // reading, including pauses between swipes. Save at lifecycle boundaries.
        // Mark as completed when reaching the last page
        // Exception: Don't mark for the pre-pagination placeholder (single text page before
        // ReaderPagedTextViewController has paginated it). Once paginated, even single-page
        // chapters should be marked as read.
        let isPrePaginationPlaceholder = totalPages == 1
            && self.pages.first?.isTextPage == true
            && !(reader is ReaderPagedTextViewController && (reader as? ReaderPagedTextViewController)?.hasPaginated == true)
        if pages.upperBound >= totalPages && !isPrePaginationPlaceholder {
            setCompleted()
        }
    }

    private func renderCurrentPageControls() {
        // Keep progress current while scrolling, without moving the slider's
        // constraints or rebuilding SwiftUI accessories at every panel boundary.
        guard (reader as? ReaderWebtoonViewController)?.isContentScrolling != true else { return }
        if needsDescriptionUpdate, let displayedPages {
            needsDescriptionUpdate = false
            updateDescriptionButton(pages: displayedPages)
        }
        if needsPageControlUpdate, readerControlsVisible {
            needsPageControlUpdate = false
            toolbarView.currentPage = currentPage
            toolbarView.updateSliderPosition()
        }
    }

    private func updateDescriptionButton(pages: ClosedRange<Int>) {
        let pageItems = pages.compactMap { self.pages[safe: $0 - 1]?.toNew() }
        if pageItems.contains(where: { $0.hasDescription }) {
            descriptionButtonController.rootView = ReaderPageDescriptionButtonView(
                source: source,
                pages: pageItems
            )
            descriptionButtonController.view.isHidden = false
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.descriptionButtonController.view.alpha = 1
            }
        } else {
            guard !descriptionButtonController.view.isHidden else { return }
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.descriptionButtonController.view.alpha = 0
            } completion: { _ in
                self.descriptionButtonController.view.isHidden = true
            }
        }
    }

    func setPages(_ pages: [Page]) {
        guard !hasExited else { return }
        // If already in a text reader with text pages, just update toolbar - don't trigger any switches
        if
            reader is ReaderPagedTextViewController || reader is ReaderTextViewController,
            pages.allSatisfy({ $0.isTextPage }),
            pages.count > 1
        {
            self.pages = pages
            toolbarView.totalPages = pages.count
            activityIndicator.stopAnimating()
            return
        }
        self.pages = pages
        toolbarView.totalPages = pages.count
        activityIndicator.stopAnimating()
        if showPanelsOnOpen && !pages.isEmpty && view.window != nil {
            showPanelsOnOpen = false
            // Present after the reader's current load/layout transaction finishes.
            DispatchQueue.main.async { [weak self] in self?.openPanels() }
        }
        if pages.isEmpty {
            // no pages, show error
            showLoadFailAlert()
        } else if pages.count == 1 && pages[0].isTextPage {
            // single text page, should switch to text reader
            if !(reader is ReaderPagedTextViewController) && !(reader is ReaderTextViewController) {
                setReader(.text)
                setChapter(chapter)
                loadCurrentChapter()
            } else {
            }
        } else if reader is ReaderPagedTextViewController && pages.allSatisfy({ $0.isTextPage }) {
            // Already in paginated text reader with multiple text pages (from pagination)
            // Don't switch away - this is our internal page count update
            // Just update the toolbar, don't reload
        } else {
            // otherwise, make sure we're not in the text reader
            if reader is ReaderTextViewController || reader is ReaderPagedTextViewController {
                switch readingMode {
                    case .ltr, .rtl, .vertical:
                        setReader(.paged)
                    case .webtoon, .continuous:
                        setReader(.scroll)
                }
                setChapter(chapter)
                loadCurrentChapter()
            }
        }
    }

    func displayPage(_ page: Int) {
        toolbarView.displayPage(page)
    }

    func setSliderOffset(_ offset: CGFloat) {
        toolbarView.sliderView.currentValue = offset
    }

    func setCompleted() {
        guard !AppSettings.general.incognitoMode.get(), !chaptersToMark.isEmpty else { return }

        for chapter in chaptersToMark {
            pendingCompletions[physicalIdentifier(chapter)] = physicalChapter(chapter)
        }
        chaptersToMark.removeAll()

        if AppSettings.downloads.deleteDownloadAfterReading.get() {
            chaptersToRemoveDownload.append(chapter)
        }
    }

    private func configureBarToggleTapGestures() {
        if let barToggleTapGesture {
            view.removeGestureRecognizer(barToggleTapGesture)
        }
        if let barToggleSecondaryTapGesture {
            view.removeGestureRecognizer(barToggleSecondaryTapGesture)
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.delegate = self
        let singleTapLookupEnabled = isDictionarySingleTapLookupActiveForCurrentChapter
        configureNavigationBarDismissTapGesture(enabled: singleTapLookupEnabled)

        if !singleTapLookupEnabled, !UserDefaults.standard.bool(forKey: "Reader.disableDoubleTap") {
            let doubleTap = UITapGestureRecognizer(
                target: self,
                action: nil
            )
            doubleTap.numberOfTapsRequired = 2
            doubleTap.delegate = self
            view.addGestureRecognizer(doubleTap)
            tap.require(toFail: doubleTap)
            barToggleSecondaryTapGesture = doubleTap
        } else {
            barToggleSecondaryTapGesture = nil
        }

        view.addGestureRecognizer(tap)
        barToggleTapGesture = tap
    }

    private func configureNavigationBarDismissTapGesture(enabled: Bool) {
        guard let navigationBar = navigationController?.navigationBar else { return }

        if barDismissNavigationBarTapGesture == nil {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleNavigationBarTapToDismissBars(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            navigationBar.addGestureRecognizer(tap)
            barDismissNavigationBarTapGesture = tap
        }
        barDismissNavigationBarTapGesture?.isEnabled = enabled
    }

    @objc private func handleNavigationBarTapToDismissBars(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .ended else { return }
        guard isDictionarySingleTapLookupActiveForCurrentChapter else { return }
        hideBars()
    }

    private func configureDictionaryLookupGesture() {
        if let gesture = dictionaryLongPressGesture {
            view.removeGestureRecognizer(gesture)
            dictionaryLongPressGesture = nil
        }
        clearDictionarySelectionHighlight()
        if #available(iOS 18.0, *) {
            dictionaryLongPressSelection = nil
        }

        guard
            isDictionaryLongPressLookupActiveForCurrentChapter,
            !AppSettings.dictionary.textOverlayMode.get()
        else {
            return
        }

        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleDictionaryLongPress(_:)))
        gesture.minimumPressDuration = 0.25
        gesture.allowableMovement = 60
        gesture.cancelsTouchesInView = false
        view.addGestureRecognizer(gesture)
        dictionaryLongPressGesture = gesture
    }

    @objc private func handleDictionaryLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        guard
            #available(iOS 18.0, *),
            isDictionaryLongPressLookupActiveForCurrentChapter,
            !AppSettings.dictionary.textOverlayMode.get(),
            !dictionaryCoordinator.isPopupVisible,
            LookupEngine.shared.isReady
        else {
            return
        }

        let point = gestureRecognizer.location(in: view)
        switch gestureRecognizer.state {
            case .began, .changed:
                guard
                    let reader = reader as? ReaderDictionaryReader,
                    let result = reader.recognizedText(at: point)
                else {
                    dictionaryLongPressSelection = nil
                    clearDictionarySelectionHighlight()
                    return
                }
                dictionaryLongPressSelection = result
                updateDictionarySelectionHighlight(text: result.text, charRects: result.charRects)

            case .ended:
                defer {
                    dictionaryLongPressSelection = nil
                    clearDictionarySelectionHighlight()
                }
                var selection = dictionaryLongPressSelection
                if selection == nil, let reader = reader as? ReaderDictionaryReader {
                    selection = reader.recognizedText(at: point)
                }
                if let selection {
                    _ = dictionaryCoordinator.performLookup(
                        text: selection.text,
                        contextText: selection.fullText,
                        anchorRect: selection.charRect,
                        charRects: selection.charRects,
                        page: currentPage
                    )
                }

            default:
                dictionaryLongPressSelection = nil
                clearDictionarySelectionHighlight()
        }
    }

    @available(iOS 18.0, *)
    private func updateDictionarySelectionHighlight(text: String, charRects: [CGRect]) {
        dictionaryCoordinator.updateSelectionHighlight(text: text, charRects: charRects)
    }

    private func clearDictionarySelectionHighlight() {
        if #available(iOS 18.0, *) {
            dictionaryCoordinator.clearSelectionHighlight()
        }
    }
}

// MARK: - Tap Zones
extension ReaderViewController {
    private enum ReaderControlTapZoneConstants {
        static let minimumTapZoneHeight: CGFloat = 44
    }

    func updateTapZone() {
        let enabledTapZone = UserDefaults.standard.string(forKey: "Reader.tapZones")
        let tapZone: TapZone? = switch enabledTapZone {
            case "auto": switch reader {
                case is ReaderPagedViewController: .leftRight
                case is ReaderWebtoonViewController: .lShaped
                case is ReaderTextViewController: .lShaped
                case is ReaderPagedTextViewController: .leftRight  // Kindle-style tap zones
                default: .leftRight
            }
            case "left-right": .leftRight
            case "l-shaped": .lShaped
            case "kindle": .kindle
            case "edge": .edge
            default: nil
        }
        self.tapZone = tapZone
    }

    @objc func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let point = gestureRecognizer.location(in: view)
        let overlayModeEnabled = AppSettings.dictionary.textOverlayMode.get()
        let singleTapLookupEnabled = isDictionarySingleTapLookupActiveForCurrentChapter
        let singleTapOCRLookupEnabled = singleTapLookupEnabled && !overlayModeEnabled

        // dismiss dictionary popup if visible
        if #available(iOS 18.0, *), dictionaryCoordinator.isPopupVisible {
            dictionaryCoordinator.dismissAllPopups()
            return
        }

        // dismiss text overlay box if visible
        if
            #available(iOS 18.0, *),
            overlayModeEnabled,
            let reader = reader as? ReaderDictionaryReader,
            reader.dismissActiveDictionaryOverlay()
        {
            return
        }

        // toggle bars when tapping safe areas
        if singleTapLookupEnabled, isReaderControlToggleTapZone(point) {
            toggleBarVisibility()
            return
        }

        // check for dictionary lookup
        if
            #available(iOS 18.0, *),
            singleTapOCRLookupEnabled,
            let reader = reader as? ReaderDictionaryReader,
            LookupEngine.shared.isReady
        {
            if let result = reader.recognizedText(at: point) {
                if dictionaryCoordinator.performLookup(
                    text: result.text,
                    contextText: result.fullText,
                    anchorRect: result.charRect,
                    charRects: result.charRects,
                    page: currentPage
                ).openedPopup {
                    return
                }
            }
        }

        guard let reader, let tapZone else {
            toggleBarVisibility()
            return
        }

        let relativePoint = CGPoint(
            x: point.x / view.bounds.width,
            y: point.y / view.bounds.height
        )

        let type = tapZone.regions
            .first { $0.bounds.contains(relativePoint) }
            .map(\.type)

        if let type {
            // hide the bars when tapping regardless
            if readerControlsVisible {
                hideBars()
            }
            // handle page moving
            if UserDefaults.standard.bool(forKey: "Reader.invertTapZones") {
                switch type {
                    case .left: reader.moveRight()
                    case .right: reader.moveLeft()
                }
            } else {
                switch type {
                    case .left: reader.moveLeft()
                    case .right: reader.moveRight()
                }
            }
        } else {
            toggleBarVisibility()
        }
    }

    private func isReaderControlToggleTapZone(_ point: CGPoint) -> Bool {
        let topZoneHeight = readerControlTopTapZoneHeight
        if point.y <= topZoneHeight {
            return true
        }
        let bottomZoneMinY = view.bounds.height - readerControlBottomTapZoneHeight
        return point.y >= bottomZoneMinY
    }

    private var readerControlTopTapZoneHeight: CGFloat {
        view.safeAreaInsets.top + ReaderControlTapZoneConstants.minimumTapZoneHeight
    }

    private var readerControlBottomTapZoneHeight: CGFloat {
        view.safeAreaInsets.bottom + ReaderControlTapZoneConstants.minimumTapZoneHeight
    }
}

// MARK: - Apple Pencil Squeeze
extension ReaderViewController: UIPencilInteractionDelegate {
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        // if pencil squeezing is disabled globally, ignore interaction (hig)
        guard UIPencilInteraction.preferredSqueezeAction != .ignore else { return }

        switch squeeze.phase {
            case .began:
                squeezeStartTime = Date()
                longSqueezeTimer = Timer.scheduledTimer(
                    withTimeInterval: longSqueezeThreshold,
                    repeats: false
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.longSqueezeTimer = nil
                        self?.openChapterList()
                    }
                }
            case .ended:
                guard let startTime = squeezeStartTime else { return }
                let duration = Date().timeIntervalSince(startTime)
                squeezeStartTime = nil
                longSqueezeTimer?.invalidate()
                longSqueezeTimer = nil

                if duration >= longSqueezeThreshold {
                    // long squeeze: chapter selector
                    squeezeTimer?.invalidate()
                    squeezeTimer = nil
                    return
                } else {
                    if let timer = squeezeTimer {
                        // double squeeze: previous page
                        timer.invalidate()
                        squeezeTimer = nil
                        previousPage()
                    } else {
                        // single squeeze: next page
                        squeezeTimer = Timer.scheduledTimer(
                            withTimeInterval: doubleSqueezeInterval,
                            repeats: false
                        ) { [weak self] _ in
                            Task { @MainActor in
                                self?.squeezeTimer = nil
                                self?.nextPage()
                            }
                        }
                    }
                }
            default:
                break
        }

    }

    private func nextPage() {
        switch readingMode {
            case .rtl: reader?.moveLeft()
            default: reader?.moveRight()
        }
    }

    private func previousPage() {
        switch readingMode {
            case .rtl: reader?.moveRight()
            default: reader?.moveLeft()
        }
    }
}

extension ReaderViewController {
    private func configureDictionaryOverlayInteractionMode() {
        guard #available(iOS 18.0, *), let reader = reader as? ReaderDictionaryReader else { return }

        let mode: DictionaryOverlayInteractionMode
        if !AppSettings.dictionary.textOverlayMode.get() {
            mode = .none
        } else if isDictionarySingleTapLookupActiveForCurrentChapter {
            mode = .singleTap
        } else if isDictionaryLongPressLookupActiveForCurrentChapter {
            mode = .longPress
        } else {
            mode = .none
        }

        reader.setDictionaryOverlayInteractionMode(mode)
    }

    private func configureDictionaryOverlayTapHandler() {
        guard #available(iOS 18.0, *), let reader = reader as? ReaderDictionaryReader else { return }
        reader.setDictionaryOverlayTapHandler { [weak self] text, contextText, rect, charRects in
            guard let self, AppSettings.dictionary.textOverlayMode.get() else { return }
            _ = dictionaryCoordinator.performLookup(
                text: text,
                contextText: contextText,
                anchorRect: rect,
                charRects: charRects,
                page: currentPage
            )
        }
    }
}

// MARK: - Bar Visibility
extension ReaderViewController {
    @objc func toggleBarVisibility() {
        if readerControlsVisible { hideBars() } else { showBars() }
    }

    func showBars() { setReaderControlsVisible(true) }
    func hideBars() { setReaderControlsVisible(false) }

    func setReaderControlsVisible(_ visible: Bool, animated: Bool = true) {
        // Swipe-to-hide is requested on every drag end. Reapplying the same state
        // used to rebuild constraints and animate a layout pass during deceleration.
        guard visible != readerControlsVisible else { return }
        readerControlsVisible = visible
        statusBarHidden = !visible
        navigationController?.setNavigationBarHidden(true, animated: false)
        navigationController?.isToolbarHidden = true
        controlsView.isUserInteractionEnabled = visible
        NSLayoutConstraint.deactivate(visible ? accessoryBottomFullscreen : accessoryBottomWithControls)
        NSLayoutConstraint.activate(visible ? accessoryBottomWithControls : accessoryBottomFullscreen)
        if visible {
            controlsView.isHidden = false
            renderCurrentPageControls()
        }
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        NotificationCenter.default.post(name: visible ? .readerShowingBars : .readerHidingBars, object: nil)
        UIView.animate(withDuration: animated ? 0.2 : 0, delay: 0, options: [.beginFromCurrentState]) {
            self.controlsView.alpha = visible ? 1 : 0
            self.view.layoutIfNeeded()
            self.node.backgroundColor = visible ? .systemBackground : {
                switch UserDefaults.standard.string(forKey: "Reader.backgroundColor") {
                case "system": UIColor.systemBackground
                case "white": UIColor.white
                default: UIColor.black
                }
            }()
        } completion: { _ in
            self.controlsView.isHidden = !self.readerControlsVisible
        }
    }
}

// MARK: - UIGestureRecognizerDelegate
extension ReaderViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: pan.view)
        return velocity.y > velocity.x && (abs(velocity.x) < 40 || abs(velocity.y) > abs(velocity.x) * 3)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard
            gestureRecognizer === barDismissNavigationBarTapGesture
                || gestureRecognizer === barToggleTapGesture
                || gestureRecognizer === barToggleSecondaryTapGesture
        else {
            return true
        }

        var view: UIView? = touch.view
        while let currentView = view {
            if currentView is UIControl || currentView === controlsView {
                return false
            }
            view = currentView.superview
        }
        return true
    }
}

// MARK: - Keyboard Shortcuts
extension ReaderViewController {
    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        let commands = [
            UIKeyCommand(
                title: NSLocalizedString("TURN_PAGE_LEFT"),
                action: #selector(moveLeft),
                input: UIKeyCommand.inputLeftArrow
            ),
            UIKeyCommand(
                title: NSLocalizedString("TURN_PAGE_RIGHT"),
                action: #selector(moveRight),
                input: UIKeyCommand.inputRightArrow
            ),
            UIKeyCommand(
                title: NSLocalizedString("TOGGLE_PAGE_OFFSET"),
                action: #selector(toggleOffset),
                input: "o"
            ),
            UIKeyCommand(
                title: NSLocalizedString("CHAPTER_FORWARD"),
                action: #selector(nextChapter),
                input: ","
            ),
            UIKeyCommand(
                title: NSLocalizedString("CHAPTER_BACKWARD"),
                action: #selector(previousChapter),
                input: "."
            ),
            UIKeyCommand(
                title: NSLocalizedString("OPEN_CHAPTER_LIST"),
                action: #selector(openChapterList),
                input: "\t"
            ),
            UIKeyCommand(
                title: NSLocalizedString("TOGGLE_BARS"),
                action: #selector(toggleBarVisibility),
                input: " "
            ),
            UIKeyCommand(
                title: NSLocalizedString("CLOSE_READER"),
                action: #selector(close),
                input: UIKeyCommand.inputEscape
            )
        ]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return commands
    }

    @objc func moveLeft() {
        reader?.moveLeft()
    }

    @objc func moveRight() {
        reader?.moveRight()
    }

    @objc func toggleOffset() {
        reader?.toggleOffset()
    }

    @objc func nextChapter() {
        if let nextChapter = getNextChapter() {
            reader?.setChapter(nextChapter, startPage: 1)
            setChapter(nextChapter)
        }
    }

    @objc func previousChapter() {
        if let previousChaoter = getPreviousChapter() {
            reader?.setChapter(previousChaoter, startPage: 1)
            setChapter(previousChaoter)
        }
    }
}


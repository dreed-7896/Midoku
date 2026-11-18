//
//  NewSourceViewController.swift
//  Midoku
//
//  Created by Skitty on 8/21/23.
//
//  The extension page, laid out like Midoku Web's: no navigation bar, a page head
//  (SourcePageHeader) that scrolls away with the content, and below it either the
//  source's home / listings or its search results.
//

import AidokuRunner
import Combine
import NukeUI
import SafariServices
import SwiftUI

class NewSourceViewController: UIViewController, MDBarlessScreen {
    let source: AidokuRunner.Source
    // if the listings/home should be hidden and the search view shown by default
    private let onlySearch: Bool

    private lazy var searchViewController = SourceSearchViewController(source: source)

    // MARK: State
    private var listings: [AidokuRunner.Listing] = [] {
        didSet { updateHostingControllers() }
    }
    private var headerListingSelection: Int = 0 {
        didSet { updateHostingControllers() }
    }
    private var importing: Bool = false {
        didSet { importHostingController.rootView = importFileView }
    }
    /// The submitted query.
    private var searchText: String
    private var filters: [AidokuRunner.Filter]? {
        didSet { updateHostingControllers() }
    }
    private var enabledFilters: [FilterValue] = [] {
        didSet {
            searchViewController.enabledFilters = enabledFilters
            updateHostingControllers()
            saveEnabledFilters()
        }
    }
    /// Filters picked on this page (or handed in by a Discover shelf) switch to results.
    private var filtersApplied = false

    private var searching: Bool {
        onlySearch || !searchText.isEmpty || filtersApplied
    }
    private var showingSearch = false

    private var filterCount: Int {
        enabledFilters
            .map {
                switch $0 {
                    case .text, .sort, .check, .select, .range: 1
                    case let .multiselect(_, included, excluded): included.count + excluded.count
                }
            }
            .reduce(0, +)
    }

    private var listingsBinding: Binding<[AidokuRunner.Listing]> {
        .init(
            get: { [weak self] in self?.listings ?? [] },
            set: { [weak self] in self?.listings = $0 }
        )
    }
    private var headerListingSelectionBinding: Binding<Int> {
        .init(
            get: { [weak self] in self?.headerListingSelection ?? 0 },
            set: { [weak self] in self?.headerListingSelection = $0 }
        )
    }
    private var importingBinding: Binding<Bool> {
        .init(
            get: { [weak self] in self?.importing ?? false },
            set: { [weak self] in self?.importing = $0 }
        )
    }
    private var enabledFiltersBinding: Binding<[FilterValue]> {
        .init(
            get: { [weak self] in self?.enabledFilters ?? [] },
            set: { [weak self] in
                guard let self else { return }
                self.enabledFilters = $0
                self.filtersApplied = !$0.isEmpty
                self.updateMode()
            }
        )
    }
    private var searchBinding: Binding<String> {
        .init(
            get: { [weak self] in self?.searchText ?? "" },
            set: { [weak self] in self?.submit($0) }
        )
    }

    // MARK: SwiftUI Views
    private var headerView: SourcePageHeader {
        SourcePageHeader(
            source: source,
            topInset: view.safeAreaInsets.top,
            onlySearch: onlySearch,
            query: searchText,
            searching: searching,
            filterCount: filterCount,
            filtersReady: !(filters?.isEmpty ?? true),
            canImport: source.id == LocalSourceRunner.sourceKey,
            listings: listingsBinding,
            selectedListing: headerListingSelectionBinding,
            onBack: { [weak self] in self?.navigationController?.popViewController(animated: true) },
            onSettings: { [weak self] in self?.openSettings() },
            onWebsite: source.urls.first == nil ? nil : { [weak self] in self?.openWebsite() },
            onImport: { [weak self] in self?.importing = true },
            onSubmit: { [weak self] in self?.submit($0) },
            onFilters: { [weak self] in self?.openFilters() },
            onClearFilters: { [weak self] in
                guard let self else { return }
                self.enabledFilters = []
                self.filtersApplied = false
                self.updateMode()
            }
        )
    }

    private var mainView: SourceHomeContentView {
        SourceHomeContentView(
            source: source,
            holdingViewController: self,
            listings: listingsBinding,
            headerListingSelection: headerListingSelectionBinding
        )
    }

    private var filterSheetView: FilterListSheetView {
        FilterListSheetView(
            sourceKey: source.key,
            filters: filters ?? [],
            search: searchBinding,
            enabledFilters: enabledFiltersBinding
        )
    }

    struct ImportFileView: View {
        @Binding var importing: Bool

        var body: some View {
            EmptyView()
                .sheet(isPresented: $importing) {
                    LocalFileImportView()
                }
        }
    }
    private var importFileView: ImportFileView {
        ImportFileView(importing: importingBinding)
    }

    // MARK: Hosting Controllers
    private lazy var headerController = {
        let controller = UIHostingController(rootView: headerView)
        controller.sizingOptions = .intrinsicContentSize
        controller.safeAreaRegions = []
        controller.view.backgroundColor = .clear
        controller.view.clipsToBounds = false
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        return controller
    }()
    private lazy var mainHostingController = UIHostingController(rootView: mainView)
    private lazy var importHostingController = UIHostingController(rootView: importFileView)

    /// Covers the status bar once the header has scrolled away.
    private let statusBarCover = UIView()
    private var headerTop: NSLayoutConstraint?
    private var headerHeight: CGFloat = 0
    private var offsetObservation: NSKeyValueObservation?
    private weak var trackedScrollView: UIScrollView?

    init(
        source: AidokuRunner.Source,
        onlySearch: Bool? = nil,
        searchQuery: String? = nil,
        initialListingIndex: Int? = nil,
        initialFilters: [FilterValue]? = nil
    ) {
        self.source = source
        self.onlySearch = onlySearch ?? source.onlySearch
        self.searchText = searchQuery ?? ""
        if let initialListingIndex {
            self.headerListingSelection = initialListingIndex + (source.features.providesHome ? 1 : 0)
        } else if let saved = UserDefaults.standard.object(forKey: SourceSettingsView.defaultTabKey(source.key)) as? Int, saved > 0 {
            // the tab picked in the extension's settings ("Open on")
            self.headerListingSelection = saved
        }
        super.init(nibName: nil, bundle: nil)

        self.searchViewController.searchText = self.searchText

        // load filters from defaults
        let filtersData: Data? = SettingsStore.shared.get(key: "\(source.key).filters")
        if let filtersData {
            let enabledFilters = try? JSONDecoder().decode([FilterValue].self, from: filtersData)
            self.enabledFilters = enabledFilters ?? []
            self.searchViewController.enabledFilters = self.enabledFilters
        }
        // A Discover search shelf opens with its own filters without replacing the source's saved ones.
        if let initialFilters {
            self.enabledFilters = initialFilters
            self.searchViewController.enabledFilters = initialFilters
            self.filtersApplied = !initialFilters.isEmpty
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configure()
        constrain()
        updateMode(initial: true)
        Task { await loadFilters() }
    }

    func configure() {
        title = source.name
        view.backgroundColor = MDColor.bg

        if !onlySearch {
            addChild(mainHostingController)
            mainHostingController.view.backgroundColor = MDColor.bg
            view.addSubview(mainHostingController.view)
            mainHostingController.didMove(toParent: self)
        }

        addChild(searchViewController)
        view.addSubview(searchViewController.view)
        searchViewController.didMove(toParent: self)
        searchViewController.view.backgroundColor = MDColor.bg
        searchViewController.collectionView.backgroundColor = MDColor.bg

        addChild(headerController)
        view.addSubview(headerController.view)
        headerController.didMove(toParent: self)

        statusBarCover.backgroundColor = MDColor.bg
        statusBarCover.alpha = 0
        view.addSubview(statusBarCover)

        if source.id == LocalSourceRunner.sourceKey {
            addChild(importHostingController)
            view.addSubview(importHostingController.view)
            importHostingController.didMove(toParent: self)
            importHostingController.view.isUserInteractionEnabled = false
            importHostingController.view.backgroundColor = .clear
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshFilters), name: .init("refresh-filters"), object: nil
        )
    }

    private func constrain() {
        var constraints: [NSLayoutConstraint] = []
        for content in [searchViewController.view, onlySearch ? nil : mainHostingController.view].compactMap({ $0 }) {
            content.translatesAutoresizingMaskIntoConstraints = false
            constraints += [
                content.topAnchor.constraint(equalTo: view.topAnchor),
                content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ]
        }
        let top = headerController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        headerTop = top
        statusBarCover.translatesAutoresizingMaskIntoConstraints = false
        constraints += [
            top,
            headerController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBarCover.topAnchor.constraint(equalTo: view.topAnchor),
            statusBarCover.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            statusBarCover.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBarCover.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ]
        NSLayoutConstraint.activate(constraints)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        headerController.rootView = headerView
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let height = headerController.view.frame.height
        if abs(height - headerHeight) > 0.5 {
            headerHeight = height
            let insets = UIEdgeInsets(top: height, left: 0, bottom: 0, right: 0)
            searchViewController.additionalSafeAreaInsets = insets
            if !onlySearch { mainHostingController.additionalSafeAreaInsets = insets }
        }
        trackActiveScrollView()
    }
}

// MARK: - Header scrolling
extension NewSourceViewController {
    /// The header moves up with whichever content is showing, like the web page head.
    private func trackActiveScrollView() {
        let scrollView: UIScrollView? = showingSearch
            ? searchViewController.collectionView
            : findScrollView(in: mainHostingController.view)
        guard scrollView !== trackedScrollView else { return }
        trackedScrollView = scrollView
        offsetObservation = scrollView?.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
            MainActor.assumeIsolated { self?.syncHeader(to: scrollView) }
        }
        if let scrollView { syncHeader(to: scrollView) }
    }

    private func syncHeader(to scrollView: UIScrollView) {
        guard let headerTop else { return }
        let scrolled = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        let translation = -min(max(scrolled, 0), headerHeight)
        if headerTop.constant != translation { headerTop.constant = translation }
        statusBarCover.alpha = translation < 0 ? 1 : 0
    }

    // find a uiscrollview in a view hierarchy
    // useful for finding swiftui scrollviews in a hosting controller
    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = findScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }
}

// MARK: - Search
extension NewSourceViewController {
    private func submit(_ query: String) {
        guard query != searchText else { return }
        searchText = query
        searchViewController.searchText = query
        if searching && showingSearch {
            searchViewController.viewModel.loadManga(searchText: query, filters: enabledFilters, force: true)
        }
        updateMode()
    }

    /// Shows the results when there's a query or filters, the home / listings otherwise.
    private func updateMode(initial: Bool = false) {
        updateHostingControllers()
        if initial || searching != showingSearch { applyMode(searching) }
    }

    private func applyMode(_ search: Bool) {
        let wasShowing = showingSearch
        showingSearch = search
        if search && !wasShowing {
            searchViewController.searchText = searchText
            searchViewController.enabledFilters = enabledFilters
            if searchViewController.viewModel.hasAppeared {
                searchViewController.viewModel.loadManga(searchText: searchText, filters: enabledFilters, force: true)
            } else {
                searchViewController.onAppear()
            }
            searchViewController.scrollToTop(animated: false)
        }
        searchViewController.view.isHidden = !search
        if !onlySearch { mainHostingController.view.isHidden = search }
        trackedScrollView = nil
        view.setNeedsLayout()
    }

    private func openFilters() {
        view.endEditing(true)
        present(UIHostingController(rootView: filterSheetView), animated: true)
    }

    @objc private func refreshFilters() {
        Task { await loadFilters() }
    }

    private func loadFilters() async {
        filters = (try? await source.getSearchFilters()) ?? []
    }

    // refresh views in hosting controllers to update bindings
    // (basically a substitute for swiftui state reactivity)
    private func updateHostingControllers() {
        guard isViewLoaded else { return }
        headerController.rootView = headerView
        if !onlySearch { mainHostingController.rootView = mainView }
    }
}

// MARK: - Actions
extension NewSourceViewController {
    private func openSettings() {
        // there's a bug where navigationlinks in settingview don't work in NavigationView/NavigationStack,
        // so we need to use a uikit navigation controller instead
        let coordinator = NavigationCoordinator(rootViewController: self)
        let hostingController = UIHostingController(
            rootView: SourceSettingsView(source: source)
                .environmentObject(coordinator)
        )
        // The settings screen draws the web sheet head; pushed setting pages show the bar.
        let navigationController = NavigationController(rootViewController: hostingController)
        navigationController.hidesBarAtRoot = true
        coordinator.rootViewController = hostingController
        present(navigationController, animated: true)
    }

    private func openWebsite() {
        Task {
            guard
                let url = (try? await source.getBaseUrl()) ?? source.urls.first,
                let scheme = url.scheme,
                scheme.hasPrefix("http")
            else {
                let alert = UIAlertController(
                    title: NSLocalizedString("INVALID_URL"),
                    message: NSLocalizedString("INVALID_URL_TEXT"),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK"), style: .cancel) { _ in })
                present(alert, animated: true, completion: nil)
                return
            }
            present(SFSafariViewController(url: url), animated: true)
        }
    }

    private func saveEnabledFilters() {
        guard !AppSettings.general.incognitoMode.get() else { return }

        let filtersData = try? JSONEncoder().encode(enabledFilters)
        if let filtersData {
            SettingsStore.shared.set(key: "\(source.id).filters", value: filtersData)
        }
    }
}

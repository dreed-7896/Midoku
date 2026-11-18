//
//  SearchViewController.swift
//  Midoku
//
//  Created by Skitty on 11/14/25.
//

import AidokuRunner
import Combine
import SwiftUI

class SearchViewController: UIViewController {
    private let viewModel = SearchContentView.ViewModel()

    private var hasLoadedSources = false
    private var cancellables = Set<AnyCancellable>()

    private var sources: [AidokuRunner.Source] = [] {
        didSet {
            viewModel.sources = sources
            loadSourceLanguages()
        }
    }
    private var searchText: String = "" {
        didSet {
            updateHostingControllers()
        }
    }
    private var searchCommitToggle: Bool = false {
        didSet {
            updateHostingControllers()
        }
    }
    private var filters: [FilterValue] = [] {
        didSet {
            viewModel.filters = filters
            updateHostingControllers()
            saveFilters()
        }
    }
    private var sourceLanguages: [(title: String, value: String)] = [] {
        didSet {
            updateHostingControllers()
        }
    }

    private var searchTextBinding: Binding<String> {
        .init(
            get: { [weak self] in self?.searchText ?? "" },
            set: { [weak self] in
                self?.searchText = $0
            }
        )
    }
    private var searchCommitToggleBinding: Binding<Bool> {
        .init(
            get: { [weak self] in self?.searchCommitToggle ?? false },
            set: { [weak self] in self?.searchCommitToggle = $0 }
        )
    }
    private var filtersBinding: Binding<[FilterValue]> {
        .init(
            get: { [weak self] in self?.filters ?? [] },
            set: { [weak self] in self?.filters = $0 }
        )
    }

    private var mainView: SearchContentView {
        SearchContentView(
            viewModel: viewModel,
            searchText: searchTextBinding,
            searchCommitToggle: searchCommitToggleBinding,
            filters: filtersBinding,
            openResult: open(result:),
            dismissKeyboard: {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            },
            path: NavigationCoordinator(rootViewController: self),
            filterHeader: headerView
        )
    }
    private var headerView: FilterHeaderView {
        var filters: [AidokuRunner.Filter] = [
            .init(
                id: "contentRating",
                title: NSLocalizedString("CONTENT_RATING"),
                value: .multiselect(.init(
                    canExclude: true,
                    options: SourceContentRating.allCases.map { $0.title },
                    ids: SourceContentRating.allCases.map { $0.toString() }
                ))
            )
        ]
        if !sourceLanguages.isEmpty {
            filters.append(
                .init(
                    id: "languages",
                    title: NSLocalizedString("LANGUAGES"),
                    value: .multiselect(.init(
                        canExclude: true,
                        usesTagStyle: true,
                        options: sourceLanguages.map { $0.title },
                        ids: sourceLanguages.map { $0.value }
                    ))
                )
            )
        }
        if !sources.isEmpty {
            filters.append(
                .init(
                    id: "sources",
                    title: NSLocalizedString("SOURCES"),
                    value: .multiselect(.init(
                        canExclude: true,
                        options: sources.map { $0.name },
                        ids: sources.map { $0.key }
                    ))
                )
            )
        }
        return FilterHeaderView(
            filters: filters,
            enabledFilters: filtersBinding,
            onFilterSheetDismiss: {}
        )
    }

    private lazy var mainHostingController = UIHostingController(rootView: mainView)
    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configure()
        constrain()
        observe()
    }

    func configure() {
        title = NSLocalizedString("SEARCH")
        view.backgroundColor = MDColor.bg

        addChild(mainHostingController)
        view.addSubview(mainHostingController.view)
        mainHostingController.didMove(toParent: self)

        let filtersData = UserDefaults.standard.data(forKey: "Search.filters")
        if let filtersData {
            let enabledFilters = try? JSONDecoder().decode([FilterValue].self, from: filtersData)
            filters = enabledFilters ?? []
        }

        Task {
            await loadSources()
        }
    }

    func constrain() {
        mainHostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            mainHostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            mainHostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mainHostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainHostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    func observe() {
        NotificationCenter.default.publisher(for: .updateSourceList)
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    await self.loadSources()
                }
            }
            .store(in: &cancellables)
    }

    func search(for query: String) {
        loadViewIfNeeded()
        viewModel.isLoading = !query.isEmpty
        searchText = query

        Task {
            if !hasLoadedSources {
                await loadSources()
            }
            guard searchText == query else { return }
            viewModel.search(query: query, delay: false)
        }
    }

    private func updateHostingControllers() {
        mainHostingController.rootView = mainView
    }

    private func loadSources() async {
        sources = await SourceManager.shared.getLoadedSources(sorted: true)
        hasLoadedSources = true

        // ensure filters don't reference removed sources
        filters = filters.compactMap {
            switch $0 {
                case let .multiselect(id, included, excluded):
                    if id == "sources" {
                        let validSourceIds = Set(sources.map { $0.key })
                        let filteredIncluded = included.filter { validSourceIds.contains($0) }
                        let filteredExcluded = excluded.filter { validSourceIds.contains($0) }
                        if filteredIncluded.isEmpty && filteredExcluded.isEmpty {
                            return nil
                        }
                        return .multiselect(
                            id: id,
                            included: filteredIncluded,
                            excluded: filteredExcluded
                        )
                    }
                default:
                    break
            }
            return $0
        }
    }

    private func loadSourceLanguages() {
        var languages: Set<String> = []
        for source in viewModel.sources {
            languages.formUnion(source.getSelectedLanguages())
        }
        let hasMulti = languages.remove("multi") != nil
        var sortedLanguages = languages.sorted()
        if hasMulti {
            sortedLanguages.insert("multi", at: 0)
        }
        sourceLanguages = sortedLanguages.map { code in
            (
                title: SourceLanguage.displayName(for: code),
                value: code
            )
        }

        // ensure filters don't reference removed languages
        filters = filters.compactMap {
            switch $0 {
                case let .multiselect(id, included, excluded):
                    if id == "languages" {
                        let validLanguages = Set(sourceLanguages.map { $0.value })
                        let filteredIncluded = included.filter { validLanguages.contains($0) }
                        let filteredExcluded = excluded.filter { validLanguages.contains($0) }
                        if filteredIncluded.isEmpty && filteredExcluded.isEmpty {
                            return nil
                        }
                        return .multiselect(
                            id: id,
                            included: filteredIncluded,
                            excluded: filteredExcluded
                        )
                    }
                default:
                    break
            }
            return $0
        }
    }

    private func saveFilters() {
        let filtersData = try? JSONEncoder().encode(filters)
        if let filtersData {
            UserDefaults.standard.setValue(filtersData, forKey: "Search.filters")
        }
    }

    private func open(result: SearchContentView.ViewModel.SearchResult) {
        if let legacySource = result.source.legacySource {
            let sourceController = SourceViewController(source: legacySource)
            sourceController.hidesListings = true
            sourceController.navigationItem.searchController?.searchBar.text = searchText
            Task {
                await sourceController.viewModel.setTitleQuery(searchText)
                await sourceController.viewModel.setCurrentPage(1)
                await sourceController.viewModel.setManga(result.result.entries.map { $0.toOld().toInfo() })
                await sourceController.viewModel.setHasMore(result.result.hasNextPage)
                navigationController?.pushViewController(sourceController, animated: true)
            }
        } else {
            let sourceController = NewSourceViewController(source: result.source, onlySearch: true, searchQuery: searchText)
            navigationController?.pushViewController(sourceController, animated: true)
        }
    }
}

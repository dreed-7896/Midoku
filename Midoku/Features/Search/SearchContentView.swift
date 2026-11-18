//
//  SearchContentView.swift
//  Midoku
//
//  Created by Skitty on 11/14/25.
//

import AidokuRunner
import SwiftUI

struct SearchContentView: View {
    @StateObject private var viewModel: ViewModel
    @Binding private var searchText: String
    @Binding var searchCommitToggle: Bool
    @Binding private var filters: [FilterValue]
    let openResult: (ViewModel.SearchResult) -> Void
    let dismissKeyboard: () -> Void
    let path: NavigationCoordinator
    var filterHeader: FilterHeaderView?

    @State private var keyboardOffset: CGFloat = 0
    @Namespace private var animation

    init(
        viewModel: ViewModel,
        searchText: Binding<String>,
        searchCommitToggle: Binding<Bool> = .constant(false),
        filters: Binding<[FilterValue]>,
        openResult: @escaping (ViewModel.SearchResult) -> Void,
        dismissKeyboard: @escaping () -> Void,
        path: NavigationCoordinator,
        filterHeader: FilterHeaderView? = nil
    ) {
        self.filterHeader = filterHeader
        self._viewModel = StateObject(wrappedValue: viewModel)
        self._searchText = searchText
        self._searchCommitToggle = searchCommitToggle
        self._filters = filters
        self.openResult = openResult
        self.dismissKeyboard = dismissKeyboard
        self.path = path
    }

    var body: some View {
        VStack(spacing: 0) {
            MDPageHeader(kicker: "\(viewModel.sources.count) source\(viewModel.sources.count == 1 ? "" : "s") · every language", title: NSLocalizedString("SEARCH"))
            MDSearchField(text: $searchText, prompt: "Search titles everywhere", autofocus: false, onSubmit: {
                searchCommitToggle.toggle()
            }, large: true)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            if let filterHeader {
                filterHeader.padding(.top, 10)
            }
            midokuBody.font(.mdBody)
                .padding(.top, 6)
        }
        .background(Color.mdBg)
    }

    @ViewBuilder private var midokuBody: some View {
        Group {
            if searchText.isEmpty && viewModel.history.isEmpty && viewModel.pinned.isEmpty {
                UnavailableView(
                    NSLocalizedString("NO_RECENT_SEARCHES"),
                    systemImage: "magnifyingglass",
                    description: Text(NSLocalizedString("NO_RECENT_SEARCHES_TEXT"))
                )

            } else if !searchText.isEmpty && viewModel.resultsIsEmpty {
                if viewModel.isLoading {
                    MDLoadingPage(label: "Searching", shape: .rows)
                } else {
                    UnavailableView.search(text: searchText)
                }
            } else {
                List {
                    if searchText.isEmpty {
                        if !viewModel.pinned.isEmpty {
                            pinnedItems
                        }
                        if !recentItems.isEmpty {
                            historyItems
                        }
                    } else {
                        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !term.isEmpty {
                            pinCurrentSearchRow(term)
                        }
                        if viewModel.isLoading {
                            let found = viewModel.results.reduce(0) { $0 + $1.result.entries.count }
                            MDBanner(tone: .busy) {
                                Text("Searching… \(found) found so far")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(.zero)
                        }
                        searchResults
                    }
                }
                .scrollBackgroundHiddenPlease()
                .scrollDismissesKeyboardImmediately()
                .listStyle(.plain)
                .listSectionSeparator(.hidden)
                .environment(\.defaultMinListRowHeight, 10)
            }
        }
        .detectKeyboardOffset($keyboardOffset)
        .animation(.default, value: viewModel.results)
        .navigationTitle(NSLocalizedString("SEARCH"))
        .onChange(of: searchText) { newValue in
            if newValue.isEmpty {
                viewModel.results = []
            }
            viewModel.search(query: newValue, delay: true)
        }
        .onChange(of: searchCommitToggle) { _ in
            viewModel.search(query: searchText, delay: false)
        }
        .onChange(of: filters) { newValue in
            viewModel.updateFilters(newValue)
        }
    }

    private var recentItems: [String] {
        viewModel.history.reversed().filter { !viewModel.isPinned($0) }
    }

    private func termRow(_ item: String, pinned: Bool) -> some View {
        VStack(spacing: 0) {
            Button {
                searchText = item
                dismissKeyboard()
                viewModel.search(query: item, delay: false)
            } label: {
                HStack {
                    let imageName = if pinned {
                        "pin.fill"
                    } else if #available(iOS 18.0, *) {
                        "clock.arrow.trianglehead.counterclockwise.rotate.90"
                    } else {
                        "clock.arrow.circlepath"
                    }
                    Image(systemName: imageName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(pinned ? Color.mdAccent : Color.mdText3)
                        .frame(width: 22)
                    Text(item)
                        .font(.mdSystem(size: 15, weight: .medium))
                        .foregroundStyle(Color.mdText)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "arrow.up.left").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.mdText3)
                }
            }
            .buttonStyle(ListButtonStyle(tint: false))

            Rectangle().fill(Color.mdLine).frame(height: 1).padding(.horizontal, 16)
        }
        .swipeActions(edge: .leading) {
            Button {
                if pinned { viewModel.unpin(item) } else { viewModel.pin(item) }
            } label: {
                Label(pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
        .swipeActions {
            if pinned {
                Button(role: .destructive) {
                    viewModel.unpin(item)
                } label: {
                    Label("Unpin", systemImage: "pin.slash")
                }
            } else {
                Button(role: .destructive) {
                    viewModel.removeHistory(item: item)
                } label: {
                    Label(NSLocalizedString("DELETE"), systemImage: "trash")
                }
            }
        }
        .contextMenu {
            Button(pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.slash" : "pin") {
                if pinned { viewModel.unpin(item) } else { viewModel.pin(item) }
            }
            if !pinned {
                Button(NSLocalizedString("DELETE"), systemImage: "trash", role: .destructive) {
                    viewModel.removeHistory(item: item)
                }
            }
        }
        .foregroundStyle(.primary)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(.zero)
    }

    var pinnedItems: some View {
        Section {
            ForEach(viewModel.pinned, id: \.self) { item in
                termRow(item, pinned: true)
            }
        } header: {
            MDSectionLabel(text: "Pinned").padding(.horizontal, 16).padding(.top, 12)
        }
    }

    private func pinCurrentSearchRow(_ term: String) -> some View {
        let pinned = viewModel.isPinned(term)
        return Button {
            if pinned { viewModel.unpin(term) } else { viewModel.pin(term) }
        } label: {
            Label(pinned ? "Unpin “\(term)”" : "Pin “\(term)”", systemImage: pinned ? "pin.slash" : "pin")
                .font(.mdSubheadline.weight(.medium))
                .lineLimit(1)
        }
        .buttonStyle(MDGhostButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(.zero)
    }

    var historyItems: some View {
        Section {
            ForEach(recentItems, id: \.self) { item in
                termRow(item, pinned: false)
            }
        } header: {
            HStack {
                MDSectionLabel(text: NSLocalizedString("RECENTLY_SEARCHED"))
                Button(NSLocalizedString("CLEAR")) {
                    viewModel.clearHistory()
                }
                .font(.mdSystem(size: 14, weight: .semibold))
                .foregroundStyle(Color.mdAccent)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    var searchResults: some View {
        ForEach(viewModel.results) { searchResult in
            let source = searchResult.source
            let result = searchResult.result
            let id = {
                var hasher = Hasher()
                for entry in result.entries {
                    hasher.combine(entry)
                }
                return hasher.finalize()
            }()
            if !result.entries.isEmpty {
                Section {
                    HomeScrollerView(
                        source: source,
                        component: .init(
                            title: nil,
                            value: .scroller(entries: result.entries.map { $0.intoLink() })
                        )
                    )
                    .id("\(source.key).\(id)") // fixes issue with incorrect entries showing
                    .environmentObject(path)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.zero)
                    .listRowSeparator(.hidden)
                } header: {
                    Button {
                        openResult(searchResult)
                    } label: {
                        HStack(spacing: 10) {
                            SourceIconView(sourceId: source.key, imageUrl: source.imageUrl, iconSize: 28)
                            Text(source.name)
                                .font(.mdDisplay(17, weight: .bold))
                                .foregroundStyle(Color.mdText)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text("\(result.entries.count) result\(result.entries.count == 1 ? "" : "s")")
                                .font(.mdSystem(size: 12))
                                .foregroundStyle(Color.mdText3)
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.mdText3)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 4)
                }
            }
        }
    }
}

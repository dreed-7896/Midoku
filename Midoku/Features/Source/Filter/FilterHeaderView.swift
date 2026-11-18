//
//  FilterHeaderView.swift
//  Midoku
//
//  Created by Skitty on 9/17/23.
//

import AidokuRunner
import SwiftUI

struct FilterHeaderView: View {
    let sourceKey: String?
    let filters: [AidokuRunner.Filter]
    @Binding var search: String
    @Binding var enabledFilters: [FilterValue]
    let onFilterButtonClick: (() -> Void)?
    let onFilterSheetDismiss: (() -> Void)?

    @State private var showingSheet = false

    private var sortedFilters: [AidokuRunner.Filter] {
        let enabledIDs = Set(enabledFilters.map(\.id))

        var enabled: [AidokuRunner.Filter] = []
        var disabled: [AidokuRunner.Filter] = []

        enabled.reserveCapacity(filters.count)
        disabled.reserveCapacity(filters.count)

        for filter in filters {
            if enabledIDs.contains(filter.id) {
                enabled.append(filter)
            } else {
                disabled.append(filter)
            }
        }

        return enabled + disabled
    }

    init(
        sourceKey: String? = nil,
        filters: [AidokuRunner.Filter],
        search: Binding<String> = .constant(""),
        enabledFilters: Binding<[FilterValue]>,
        onFilterButtonClick: (() -> Void)? = nil,
        onFilterSheetDismiss: (() -> Void)? = nil
    ) {
        self.sourceKey = sourceKey
        self.filters = filters
        self._search = search
        self._enabledFilters = enabledFilters
        self.onFilterButtonClick = onFilterButtonClick
        self.onFilterSheetDismiss = onFilterSheetDismiss
    }

    private var filterCount: Int {
        enabledFilters
            .map {
                switch $0 {
                    case .text, .sort, .check, .select, .range: 1
                    case let .multiselect(_, included, excluded):
                        included.count + excluded.count
                }
            }
            .reduce(0, +)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterSheetButton

                ForEach(sortedFilters, id: \.self) { filter in
                    if !(filter.hideFromHeader ?? false) {
                        switch filter.value {
                            case .sort:
                                SortFilterView(filter: filter, enabledFilters: $enabledFilters)
                            case let .check(_, _, defaultValue):
                                // if check filter has a default value then hide it from the list
                                // we don't want it to appear as enabled when the filters are reset
                                if defaultValue == nil {
                                    CheckFilterView(filter: filter, enabledFilters: $enabledFilters)
                                }
                            case .select:
                                SelectFilterView(filter: filter, enabledFilters: $enabledFilters)
                            case .multiselect:
                                MultiSelectFilterView(filter: filter, enabledFilters: $enabledFilters)
                            default:
                                EmptyView()
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .animation(.easeInOut, value: enabledFilters)
        }
        .scrollClipDisabledPlease()
        .animation(.default, value: sortedFilters)
        .sheet(isPresented: $showingSheet, onDismiss: onFilterSheetDismiss) {
            FilterListSheetView(
                sourceKey: sourceKey,
                filters: filters,
                search: $search,
                enabledFilters: $enabledFilters
            )
        }
    }

    var filterSheetButton: some View {
        Button {
            if let onFilterButtonClick {
                onFilterButtonClick()
            } else {
                showingSheet = true
            }
        } label: {
            MDChip(title: "", count: nil, active: !enabledFilters.isEmpty, systemImage: "slider.horizontal.3", large: false)
                .overlay(alignment: .topTrailing) {
                    if !enabledFilters.isEmpty {
                        FilterBadgeView(count: filterCount).offset(x: 6, y: -6)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

@available(iOS 17.0, macOS 14.0, *)
#Preview {
    @Previewable @State var enabledFilters: [FilterValue] = []
    return FilterHeaderView(
        filters: [
            .init(
                id: "text",
                title: "Text",
                value: .text(placeholder: "Placeholder")
            ),
            .init(
                id: "sort",
                title: "Sort",
                value: .sort(
                    canAscend: true,
                    options: ["Latest", "Popular"],
                    defaultValue: nil
                )
            ),
            .init(
                id: "select",
                title: "Select",
                value: .select(
                    .init(
                        usesTagStyle: false,
                        options: ["Option 1", "Option 2"],
                        defaultValue: nil
                    )
                )
            ),
            .init(
                id: "select2",
                title: "Select 2",
                value: .select(
                    .init(
                        usesTagStyle: true,
                        options: ["Option 1", "Option 2"],
                        defaultValue: nil
                    )
                )
            ),
            .init(
                id: "multi-select",
                title: "Multi Select",
                value: .multiselect(.init(
                    canExclude: true,
                    options: ["Option 1", "Option 2"],
                    ids: nil
                ))
            ),
            .init(
                id: "genre",
                title: "Genre",
                hideFromHeader: true,
                value: .multiselect(.init(
                    isGenre: true,
                    canExclude: true,
                    options: ["Option 1", "Option 2"],
                    ids: nil
                ))
            ),
            .init(
                id: "check",
                title: "Check",
                value: .check(
                    name: nil,
                    canExclude: true,
                    defaultValue: nil
                )
            ),
            .init(
                id: "note",
                title: nil,
                value: .note("This is a note.")
            )
        ],
        enabledFilters: $enabledFilters
    )
}

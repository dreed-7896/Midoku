//
//  SourcePageHeader.swift
//  Midoku
//
//  Midoku Web's extension page head (SourceBrowse / RemoteBrowse): glass square back and
//  action buttons over a short backdrop, 68pt icon with the name and languages, a search
//  field with the filter button, then underline tabs for Home, listings or the active search.
//

import AidokuRunner
import SwiftUI

struct SourcePageHeader: View {
    let source: AidokuRunner.Source
    /// Status bar height: the backdrop reaches up behind it.
    var topInset: CGFloat = 0
    var onlySearch = false
    /// The submitted query ("" when not searching by text).
    var query = ""
    var searching = false
    var filterCount = 0
    var filtersReady = false
    var canImport = false
    @Binding var listings: [AidokuRunner.Listing]
    @Binding var selectedListing: Int

    var onBack: () -> Void = {}
    var onSettings: () -> Void = {}
    var onWebsite: (() -> Void)?
    var onImport: () -> Void = {}
    var onSubmit: (String) -> Void = { _ in }
    var onFilters: () -> Void = {}
    var onClearFilters: () -> Void = {}

    @State private var input = ""

    private var meta: String {
        let langs = source.languages.filter { $0 != "multi" }
        let lang = langs.count > 1
            ? "\(langs.count) languages"
            : SourceLanguage.displayName(for: SourceLanguage.primaryCode(for: source.languages))
        return [lang, "v\(source.version)"].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            head.padding(.top, 18)
            searchRow.padding(.top, 14)
            tabs.padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) { backdrop }
        .onAppear { input = query }
        .onChange(of: query) { _, value in input = value }
        .onChange(of: input) { _, value in
            // Clearing the field leaves the search, like tapping the × on its tab.
            if value.isEmpty, !query.isEmpty { onSubmit("") }
        }
    }

    // `.entry__top`
    private var topBar: some View {
        HStack(spacing: 8) {
            MDIconButton(systemImage: "chevron.left", label: "Back", glass: true, action: onBack)
            Spacer(minLength: 0)
            if canImport {
                MDIconButton(systemImage: "plus", label: NSLocalizedString("UPLOAD_FILE"), glass: true, action: onImport)
            }
            if let onWebsite {
                MDIconButton(systemImage: "globe", label: NSLocalizedString("OPEN_WEBSITE"), glass: true, action: onWebsite)
            }
            MDIconButton(systemImage: "gearshape", label: NSLocalizedString("SETTINGS"), glass: true, action: onSettings)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    // `.source-head`
    private var head: some View {
        HStack(spacing: 14) {
            SourceIconView(sourceId: source.key, imageUrl: source.imageUrl, iconSize: 68)
                .shadow(color: .black.opacity(0.4), radius: 15, y: 12)
            VStack(alignment: .leading, spacing: 6) {
                Text(source.name)
                    .font(.mdDisplay(31))
                    .tracking(-0.9)
                    .foregroundStyle(Color.mdText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(meta)
                    .font(.mdSystem(size: 14))
                    .foregroundStyle(Color.mdText2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            MDSearchField(text: $input, prompt: "Search \(source.name)", autofocus: false, onSubmit: {
                onSubmit(input.trimmingCharacters(in: .whitespacesAndNewlines))
            })
            if filtersReady {
                Button(action: onFilters) {
                    MDIconBox(systemImage: "slider.horizontal.3", active: filterCount > 0, badge: filterCount > 0 ? filterCount : nil, size: 46)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Source filters")
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var tabs: some View {
        if searching {
            MDUnderlineTabs {
                if !query.isEmpty {
                    MDUnderlineTab(title: "“\(query)”", on: true, clears: true) { onSubmit("") }
                }
                if filterCount > 0 {
                    MDUnderlineTab(title: "Filtered · \(filterCount)", on: true, clears: true, action: onClearFilters)
                }
                if query.isEmpty && filterCount == 0 {
                    MDUnderlineTab(title: onlySearch ? "All titles" : "Results", on: true) {}
                }
            }
        } else if source.hasListings || source.features.providesHome {
            ListingsHeaderView(source: source, listings: $listings, selectedListing: $selectedListing)
        }
    }

    // `.entry__backdrop--short`: dark tint with a blurred coral glow, fading into the page.
    private var backdrop: some View {
        ZStack(alignment: .topTrailing) {
            Color(red: 26 / 255, green: 26 / 255, blue: 34 / 255)
            Circle()
                .fill(Color.mdAccent)
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .opacity(0.45)
                .offset(x: 90, y: -60)
            LinearGradient(colors: [Color.mdBg.opacity(0), Color.mdBg], startPoint: .center, endPoint: .bottom)
        }
        .frame(height: 300)
        .clipped()
        .padding(.top, -topInset)
        .allowsHitTesting(false)
    }
}

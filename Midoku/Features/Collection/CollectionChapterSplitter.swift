import AidokuRunner
import Nuke
import SwiftUI

/// Splits one physical chapter into parts by picking pages from a thumbnail grid.
/// Tapping a page marks where a new part starts; the exclude mode drops pages from every part.
/// Saves through `setChapterPages`, so existing part identities and their edits are kept.
struct MCChapterSplitter: View {
    let entryID: UUID
    let slotID: UUID

    private enum Mode: String, CaseIterable, Identifiable {
        case split = "Mark part starts"
        case exclude = "Exclude pages"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var pages: [AidokuRunner.Page] = []
    @State private var sourceKey: String?
    @State private var loading = true
    @State private var loadError: String?
    @State private var mode = Mode.split
    /// Pages (1-based, > 1) where a new part begins. Page 1 always begins part 1.
    @State private var starts: Set<Int> = []
    @State private var excluded: Set<Int> = []
    /// Exclusions past the current page count, kept as they were.
    @State private var trailingExcluded: [MCPageRange] = []
    @State private var confirmClear = false

    private var variant: MCChapterVariant? { store.library.entry(entryID)?.slots.first { $0.id == slotID }?.preferred }
    private var sortedStarts: [Int] { [1] + starts.filter { $0 > 1 && $0 <= pages.count }.sorted() }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Split chapter").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(loading || pages.isEmpty) }
                }
                .confirmationDialog("Remove all splits?", isPresented: $confirmClear) {
                    Button("Rejoin chapter", role: .destructive) { starts = []; excluded = []; trailingExcluded = [] }
                } message: { Text("Clears every split point and excluded page. Nothing changes until you save.") }
                .task { await load() }
                .mcErrors(store)
        }
    }

    @ViewBuilder private var content: some View {
        if loading {
            ProgressView("Loading pages…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            ContentUnavailableView {
                Label("Couldn’t load pages", systemImage: "exclamationmark.triangle")
            } description: { Text(loadError) } actions: {
                Button("Retry") { Task { await load() } }
            }
        } else if pages.isEmpty {
            ContentUnavailableView("No pages", systemImage: "doc", description: Text("The source returned no pages for this chapter."))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        controls(proxy)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                            ForEach(1...pages.count, id: \.self) { page in
                                pageCell(page).id(page)
                            }
                        }
                        Text("The last part also gets any pages the source adds later. Each part can be renamed with Edit chapter.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding()
                }
            }
        }
    }

    private func controls(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            Text(mode == .split
                 ? "Tap the first page of each new part. Tap it again to remove the split."
                 : "Tap pages to leave them out of every part.")
                .font(.footnote).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(partRanges.enumerated()), id: \.offset) { index, range in
                        Button {
                            withAnimation { proxy.scrollTo(range.lowerBound, anchor: .top) }
                        } label: {
                            Text("Part \(index + 1) · \(range.lowerBound == range.upperBound ? "p\(range.lowerBound)" : "p\(range.lowerBound)–\(range.upperBound)")")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(partColor(index).opacity(0.25), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                    if !starts.isEmpty || !excluded.isEmpty {
                        Button("Clear", systemImage: "arrow.uturn.backward", role: .destructive) { confirmClear = true }
                            .font(.caption).buttonStyle(.bordered)
                    }
                }
            }
            if !excluded.isEmpty {
                Text("\(excluded.count) page\(excluded.count == 1 ? "" : "s") excluded").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var partRanges: [ClosedRange<Int>] {
        let s = sortedStarts
        return s.enumerated().map { i, start in start...((i + 1 < s.count ? s[i + 1] : pages.count + 1) - 1) }
    }

    private func partIndex(_ page: Int) -> Int { sortedStarts.lastIndex { $0 <= page } ?? 0 }

    private func partColor(_ index: Int) -> Color {
        [Color.accentColor, .teal, .orange, .purple, .pink, .green][index % 6]
    }

    private func pageCell(_ page: Int) -> some View {
        let part = partIndex(page)
        let isStart = page == 1 || starts.contains(page)
        let isExcluded = excluded.contains(page)
        let color = partColor(part)
        return Button { tap(page) } label: {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    MCSplitPageThumbnail(page: pages[page - 1], sourceKey: sourceKey)
                        .opacity(isExcluded ? 0.3 : 1)
                    if isExcluded {
                        Image(systemName: "xmark.circle.fill").font(.title2)
                            .foregroundStyle(.white, .red)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    Text("\(page)").font(.caption2.monospacedDigit().weight(.bold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.black.opacity(0.65), in: Capsule())
                        .foregroundStyle(.white).padding(4)
                }
                Text(isStart ? "Part \(part + 1) starts" : "Part \(part + 1)")
                    .font(.caption2.weight(isStart ? .bold : .regular))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .background(color.opacity(isStart ? 0.9 : 0.18))
                    .foregroundStyle(isStart ? Color.white : Color.primary)
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: isStart ? 3 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Page \(page), part \(part + 1)\(isStart ? ", part start" : "")\(isExcluded ? ", excluded" : "")")
        .contextMenu {
            Button(page == 1 ? "Page 1 always starts part 1" : (starts.contains(page) ? "Remove split here" : "Start new part here"),
                   systemImage: "scissors") { toggle(&starts, page) }.disabled(page == 1)
            Button(isExcluded ? "Include page" : "Exclude page", systemImage: isExcluded ? "plus.circle" : "minus.circle") { toggle(&excluded, page) }
        }
    }

    private func tap(_ page: Int) {
        switch mode {
        case .split: if page > 1 { toggle(&starts, page) }
        case .exclude: toggle(&excluded, page)
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func toggle(_ set: inout Set<Int>, _ page: Int) {
        if set.contains(page) { set.remove(page) } else { set.insert(page) }
    }

    private func load() async {
        loading = true; loadError = nil
        defer { loading = false }
        guard let variant, let chapter = store.library.chapter(variant.chapterID), let physical = store.physical(chapter.identity) else {
            loadError = "This chapter is no longer in the collection."; return
        }
        sourceKey = physical.manga.sourceKey
        do {
            let identifier = ChapterIdentifier(sourceKey: physical.manga.sourceKey, mangaKey: physical.manga.key, chapterKey: physical.chapter.key)
            if DownloadManager.shared.isChapterDownloaded(chapter: identifier) {
                pages = await DownloadManager.shared.getDownloadedPages(for: identifier)
            } else if let source = store.source(chapter.identity.listing.connectionID) {
                pages = try await source.getPageList(manga: physical.manga, chapter: physical.chapter)
            } else {
                loadError = "The source for this chapter isn’t installed."; return
            }
        } catch {
            loadError = error.localizedDescription; return
        }
        applySelection(variant.pageSelection)
    }

    /// Turns saved ranges into split points and excluded pages. Pages outside every range become exclusions.
    private func applySelection(_ selection: MCChapterPageSelection?) {
        let count = pages.count
        starts = []; excluded = []; trailingExcluded = []
        guard let selection else { return }
        for range in selection.excluded {
            let end = range.end ?? Int.max
            if range.start <= count { excluded.formUnion(range.start...min(end, count)) }
            if end > count { trailingExcluded.append(MCPageRange(start: max(range.start, count + 1), end: range.end)) }
        }
        guard !selection.ranges.isEmpty else { return }
        for range in selection.ranges where range.start > 1 { starts.insert(range.start) }
        // Pages a split left out (before the first part, between parts, after a closed last part).
        for page in 1...max(1, count) where count > 0 && !selection.ranges.contains(where: { $0.contains(page) }) {
            excluded.insert(page)
        }
        if let last = selection.ranges.last?.end, last < Int.max {
            trailingExcluded.append(MCPageRange(start: max(last + 1, count + 1), end: nil))
        }
    }

    private func save() {
        let s = sortedStarts
        let ranges: [MCPageRange] = s.count < 2 ? [] : s.enumerated().map { i, start in
            MCPageRange(start: start, end: i + 1 < s.count ? s[i + 1] - 1 : nil)
        }
        var excludedRanges: [MCPageRange] = []
        for page in excluded.filter({ $0 <= pages.count }).sorted() {
            if let last = excludedRanges.last, last.end == page - 1 { excludedRanges[excludedRanges.count - 1].end = page }
            else { excludedRanges.append(MCPageRange(start: page, end: page)) }
        }
        excludedRanges += trailingExcluded
        if store.perform({ state in
            try state.library.setChapterPages(entryID: entryID, slotID: slotID, ranges: ranges, excluded: excludedRanges)
        }) { dismiss() }
    }
}

/// One downscaled page image for the split grid.
private struct MCSplitPageThumbnail: View {
    let page: AidokuRunner.Page
    let sourceKey: String?
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        // A fixed 2:3 box sized by the grid column; the image fits inside it, so wide spreads
        // shrink to the cell width instead of widening the cell.
        Color(uiColor: .tertiarySystemFill)
            .aspectRatio(2 / 3, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else if failed {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .clipped()
            .task(id: page) { await load() }
    }

    private func load() async {
        guard image == nil else { return }
        do {
            switch page.content {
            case .image(let value):
                image = value.image
            case .url(let url, let context):
                var request = await ReaderPageView.imageRequest(url: page.thumbnail ?? url, context: context, sourceKey: sourceKey)
                request.processors.append(ImageProcessors.Resize(width: 200))
                image = try await ImagePipeline.shared.image(for: request)
            default:
                if let thumbnail = page.thumbnail {
                    let request = ImageRequest(url: thumbnail, processors: [ImageProcessors.Resize(width: 200)])
                    image = try await ImagePipeline.shared.image(for: request)
                } else { failed = true }
            }
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

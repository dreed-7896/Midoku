import SwiftUI
import Translation

struct ReaderAppleTranslationRequest {
    let token: UUID
    let regions: [TranslationRegion]
}

/// Keeps Apple's translation session in the actual reader's view hierarchy across page turns.
struct ReaderTranslationSessionView: View {
    @ObservedObject var coordinator: ReaderTranslationCoordinator

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .translationTask(coordinator.appleConfiguration) { session in
                guard let request = coordinator.appleRequest else { return }
                do {
                    let results = try await session.translations(from: request.regions.map {
                        TranslationSession.Request(sourceText: $0.sourceText, clientIdentifier: String($0.id))
                    })
                    guard !Task.isCancelled else { return }
                    let expectedIDs = Set(request.regions.map(\.id))
                    var mapped: [Int: String] = [:]
                    for result in results {
                        guard let string = result.clientIdentifier, let id = Int(string), expectedIDs.contains(id),
                              mapped[id] == nil, !result.targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            throw TranslationError.message("Some dialogues could not be matched. Tap Retry.")
                        }
                        mapped[id] = result.targetText
                    }
                    guard mapped.count == expectedIDs.count else {
                        throw TranslationError.message("Some dialogues could not be translated. Tap Retry.")
                    }
                    coordinator.appleFinished(token: request.token, translations: mapped, error: nil)
                } catch {
                    guard !Task.isCancelled else { return }
                    coordinator.appleFinished(token: request.token, translations: [:], error: error.localizedDescription)
                }
            }
    }
}

struct ReaderTranslationListItem: Identifiable {
    let key: String
    let region: TranslationRegion
    let pageLabel: String
    let translation: String
    var id: String { "\(key):\(region.id)" }
}

struct ReaderTranslationListView: View {
    let items: [ReaderTranslationListItem]
    let selected: String?
    let select: (ReaderTranslationListItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(items) { item in
                    Button {
                        select(item)
                        dismiss()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(item.region.id + 1)").font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.accentColor, in: Circle())
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.pageLabel).font(.caption.bold()).foregroundStyle(.secondary)
                                Text(item.translation).foregroundStyle(.primary)
                                Text(item.region.sourceText).font(.caption).foregroundStyle(.secondary)
                                Text("Show on page").font(.caption).foregroundStyle(Color.accentColor)
                            }
                            Spacer(minLength: 0)
                            if item.id == selected { Image(systemName: "checkmark.circle.fill") }
                        }.padding(.vertical, 6)
                    }.id(item.id)
                }
                .onAppear { if let selected { proxy.scrollTo(selected, anchor: .center) } }
            }
            .navigationTitle("Visible page dialogue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Translation options shown from the reader: pages to translate, and how translations look.
struct ReaderTranslationOptionsView: View {
    let pageCount: Int
    let currentPage: Int
    let translatePages: ([Int]) -> Void
    let translateNextPages: () -> Void
    @AppStorage(TranslationSettings.pagesPerRequestKey) private var pagesPerRequest = TranslationSettings.defaultPagesPerRequest
    @AppStorage("Translation.overlayFontSize") private var fontSize = 14.0
    @AppStorage("Translation.overlayOpacity") private var opacity = 0.94
    @State private var input = ""
    @Environment(\.dismiss) private var dismiss

    private var trimmed: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var pages: [Int]? { Self.pages(from: trimmed, pageCount: pageCount) }
    private var nextCount: Int { max(0, min(pagesPerRequest, pageCount - currentPage + 1)) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Next \(nextCount) pages", text: $input)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit(translate)
                    Button(action: translate) {
                        Label(buttonTitle, systemImage: "translate")
                    }
                    .disabled(trimmed.isEmpty ? nextCount == 0 : pages?.isEmpty != false)
                } header: {
                    Text("Pages")
                } footer: {
                    if !trimmed.isEmpty, pages == nil {
                        Text("Enter page numbers between 1 and \(pageCount), like 1-10, 12, 15-30, 31-").foregroundStyle(.red)
                    } else {
                        Text("For example 1-10, 12, 15-30, 31- (31 to the last page). Leave empty to translate \(nextCount) pages from page \(currentPage); change the default in Settings › Translation. This chapter has \(pageCount) pages. Pages already translated are skipped.")
                    }
                }

                Section("Appearance") {
                    Slider(value: $fontSize, in: 10...24, step: 1).accessibilityLabel("Translation text size")
                    Text("Translation preview").font(.system(size: fontSize))
                    Slider(value: $opacity, in: 0.5...1).accessibilityLabel("Translation background opacity")
                }
            }
            .navigationTitle("Translation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var buttonTitle: String {
        guard !trimmed.isEmpty else { return nextCount == 1 ? "Translate Page \(currentPage)" : "Translate Next \(nextCount) Pages" }
        guard let pages, !pages.isEmpty else { return "Translate Pages" }
        return pages.count == 1 ? "Translate Page \(pages[0])" : "Translate \(pages.count) Pages"
    }

    private func translate() {
        if trimmed.isEmpty {
            guard nextCount > 0 else { return }
            translateNextPages()
        } else {
            guard let pages, !pages.isEmpty else { return }
            translatePages(pages)
        }
        dismiss()
    }

    /// Page numbers from a list like "1-10, 12, 15-30, 31-", where "31-" runs to the last page and
    /// "-5" starts at the first. Returns nil when a part is not a page or range within the chapter.
    static func pages(from text: String, pageCount: Int) -> [Int]? {
        var pages: [Int] = []
        var seen = Set<Int>()
        for part in text.replacingOccurrences(of: "–", with: "-").split(separator: ",") {
            let part = part.trimmingCharacters(in: .whitespaces)
            guard !part.isEmpty else { continue }
            let bounds = part.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let lower: Int?
            let upper: Int?
            if bounds.count == 1 {
                lower = Int(bounds[0]); upper = lower
            } else {
                lower = bounds[0].isEmpty ? 1 : Int(bounds[0])
                upper = bounds[1].isEmpty ? pageCount : Int(bounds[1])
            }
            guard let lower, let upper, lower >= 1, upper <= pageCount, lower <= upper else { return nil }
            for page in lower...upper where seen.insert(page).inserted { pages.append(page) }
        }
        return pages.sorted()
    }
}

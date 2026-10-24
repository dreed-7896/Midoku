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

/// Translation options shown from the reader: which pages to translate, how, and how translations look.
struct ReaderTranslationOptionsView: View {
    let pageCount: Int
    let translateCurrentPage: () -> Void
    let translatePages: (ClosedRange<Int>) -> Void
    let automaticChanged: () -> Void
    @AppStorage(TranslationSettings.automaticKey) private var automatic = true
    @AppStorage(TranslationSettings.pagesPerRequestKey) private var pagesPerRequest = TranslationSettings.defaultPagesPerRequest
    @AppStorage("Translation.overlayFontSize") private var fontSize = 14.0
    @AppStorage("Translation.overlayOpacity") private var opacity = 0.94
    @State private var from: Int
    @State private var to: Int
    @Environment(\.dismiss) private var dismiss

    init(pageCount: Int, currentPage: Int, translateCurrentPage: @escaping () -> Void,
         translatePages: @escaping (ClosedRange<Int>) -> Void, automaticChanged: @escaping () -> Void) {
        self.pageCount = max(1, pageCount)
        self.translateCurrentPage = translateCurrentPage
        self.translatePages = translatePages
        self.automaticChanged = automaticChanged
        let start = min(max(1, currentPage), self.pageCount)
        _from = State(initialValue: start)
        _to = State(initialValue: min(self.pageCount, start + 9))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        translateCurrentPage()
                        dismiss()
                    } label: {
                        Label("Translate This Page", systemImage: "doc.text")
                    }
                }

                Section {
                    Picker("From", selection: $from) {
                        ForEach(1...pageCount, id: \.self) { Text("Page \($0)").tag($0) }
                    }
                    Picker("To", selection: $to) {
                        ForEach(1...pageCount, id: \.self) { Text("Page \($0)").tag($0) }
                    }
                    Button {
                        translatePages(from...to)
                        dismiss()
                    } label: {
                        Label(from == to ? "Translate Page \(from)" : "Translate Pages \(from)–\(to)", systemImage: "doc.on.doc")
                    }
                } header: {
                    Text("Page range")
                } footer: {
                    Text("Pages are sent \(pagesPerRequest == 1 ? "one page" : "\(pagesPerRequest) pages") at a time. Pages already translated are skipped.")
                }
                .onChange(of: from) { if to < $0 { to = $0 } }
                .onChange(of: to) { if from > $0 { from = $0 } }

                Section {
                    Toggle("Translate as I read", isOn: $automatic)
                        .onChange(of: automatic) { _ in automaticChanged() }
                    Picker("Pages at a time", selection: $pagesPerRequest) {
                        ForEach(TranslationSettings.pagesPerRequestOptions, id: \.self) { count in
                            Text(count == 1 ? "1 page" : "\(count) pages").tag(count)
                        }
                    }
                } footer: {
                    Text(automatic
                         ? "The page on screen and the pages ahead are translated while you read."
                         : "Only pages you choose are translated. Saved translations still show.")
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
}

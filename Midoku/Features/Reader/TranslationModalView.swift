import SwiftUI
import Translation

@available(iOS 18.0, *)
struct TranslationModalView: View {
    let images: [UIImage]
    let webtoon: Bool

    @Environment(\.dismiss) private var dismiss
    @AppStorage("Translation.overlayFontSize") private var fontSize = 14.0
    @AppStorage("Translation.overlayOpacity") private var backgroundOpacity = 0.94
    @State private var regions: [TranslationRegion] = []
    @State private var translations: [Int: String] = [:]
    @State private var selectedID: Int?
    @State private var imageIndex = 0
    @State private var focusRequest = 0
    @State private var showAll = false
    @State private var showOriginal = false
    @State private var showList = false
    @State private var showAppearance = false
    @State private var errorMessage: String?
    @State private var isWorking = true
    @State private var retryID = 0
    @State private var runID = UUID()
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                if images.indices.contains(imageIndex) {
                    TranslationPageCanvas(
                        image: images[imageIndex], regions: regions.filter { $0.imageIndex == imageIndex },
                        translations: translations, fallbackText: isWorking ? "Translating…" : "Translation unavailable. Tap Retry.",
                        selectedID: selectedID, focusRequest: focusRequest,
                        webtoon: webtoon, showAll: showAll, showOriginal: showOriginal,
                        fontSize: fontSize, backgroundOpacity: backgroundOpacity,
                        onSelect: { selectedID = $0 }
                    )
                } else {
                    ContentUnavailableView("No page image", systemImage: "photo")
                }
                if isWorking {
                    ProgressView(regions.isEmpty ? "Finding dialogue…" : "Translating dialogue…")
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding()
                        .allowsHitTesting(false)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Text("Translation unavailable").font(.headline)
                        Text(errorMessage).font(.callout)
                        Button("Retry") { retryID += 1 }
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding()
                } else if regions.isEmpty {
                    Text("No Japanese dialogue found")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding()
                }
            }
            .background(.black)
            .safeAreaInset(edge: .bottom, spacing: 0) { readerControls }
            .navigationTitle("Translation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(showAll ? "Tap mode" : "Show all", systemImage: showAll ? "hand.tap" : "text.bubble") {
                        showAll.toggle()
                    }
                    .disabled(translations.isEmpty)
                    Button("Dialogue list", systemImage: "list.number") { showList = true }
                        .disabled(regions.isEmpty)
                    Button("Appearance", systemImage: "slider.horizontal.3") { showAppearance = true }
                }
            }
            .sheet(isPresented: $showList) { dialogueList }
            .sheet(isPresented: $showAppearance) { appearanceSettings }
        }
        .task(id: retryID) { await start() }
        .onDisappear { showOriginal = false }
        .translationTask(configuration) { session in
            let currentRun = runID
            let currentRegions = regions
            guard !currentRegions.isEmpty else { return }
            do {
                let requests = currentRegions.map {
                    TranslationSession.Request(sourceText: $0.sourceText, clientIdentifier: String($0.id))
                }
                let results = try await session.translations(from: requests)
                guard !Task.isCancelled, currentRun == runID else { return }
                var mapped: [Int: String] = [:]
                let validIDs = Set(currentRegions.map(\.id))
                for result in results {
                    // Never fall back to response order: a reordered or incomplete batch must not
                    // silently attach a translation to the wrong text area.
                    guard let identifier = result.clientIdentifier, let id = Int(identifier),
                          validIDs.contains(id), mapped[id] == nil,
                          !result.targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw TranslationError.message("Some dialogues could not be matched. Please try again.")
                    }
                    mapped[id] = result.targetText
                }
                guard mapped.count == currentRegions.count else {
                    throw TranslationError.message("Some dialogues could not be translated. Please try again.")
                }
                translations = mapped
                isWorking = false
            } catch {
                guard !Task.isCancelled, currentRun == runID else { return }
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }

    private var readerControls: some View {
        HStack(spacing: 16) {
            Button("Previous dialogue", systemImage: "chevron.left") { moveSelection(by: -1) }
                .labelStyle(.iconOnly)
                .disabled(regions.isEmpty || selectedID == regions.first?.id)
            Text(selectedID.map { "Dialogue \($0 + 1) of \(regions.count)" } ?? (showAll ? "Tap for full translation" : "Tap a marked text area"))
                .font(.caption)
                .frame(maxWidth: .infinity)
            Button("Next dialogue", systemImage: "chevron.right") { moveSelection(by: 1) }
                .labelStyle(.iconOnly)
                .disabled(regions.isEmpty || selectedID == regions.last?.id)
            Text("Hold original")
                .font(.caption)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(showOriginal ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12), in: Capsule())
                .onLongPressGesture(minimumDuration: 0.1, pressing: { showOriginal = $0 }, perform: {})
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(showOriginal ? "Show translations" : "Show original page")
                .accessibilityAction { showOriginal.toggle() }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var dialogueList: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(regions) { region in
                    Button {
                        select(region)
                        showList = false
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(region.id + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.accentColor, in: Circle())
                            VStack(alignment: .leading, spacing: 8) {
                                Text(translations[region.id] ?? "Translating…")
                                    .foregroundStyle(.primary)
                                Text(region.sourceText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Show on page")
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                            }
                            Spacer(minLength: 0)
                            if selectedID == region.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .id(region.id)
                }
                .onAppear {
                    if let selectedID { proxy.scrollTo(selectedID, anchor: .center) }
                }
            }
            .navigationTitle("Dialogue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showList = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var appearanceSettings: some View {
        NavigationStack {
            Form {
                Section("Text size") {
                    Slider(value: $fontSize, in: 10...24, step: 1)
                        .accessibilityLabel("Translation text size")
                    Text("Translation preview").font(.system(size: fontSize))
                }
                Section("Overlay background") {
                    Slider(value: $backgroundOpacity, in: 0.5...1)
                        .accessibilityLabel("Translation background opacity")
                }
            }
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showAppearance = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func select(_ region: TranslationRegion) {
        showOriginal = false
        imageIndex = region.imageIndex
        selectedID = region.id
        focusRequest += 1
    }

    private func moveSelection(by offset: Int) {
        guard !regions.isEmpty else { return }
        guard let selectedID, let index = regions.firstIndex(where: { $0.id == selectedID }) else {
            select(offset < 0 ? regions[regions.count - 1] : regions[0])
            return
        }
        let next = index + offset
        if regions.indices.contains(next) { select(regions[next]) }
    }

    @MainActor
    private func start() async {
        let currentRun = UUID()
        runID = currentRun
        isWorking = true
        errorMessage = nil
        regions = []
        translations = [:]
        selectedID = nil
        configuration = nil
        let recognized = await PageTranslator.recognize(images, webtoon: webtoon)
        guard !Task.isCancelled, runID == currentRun else { return }
        regions = recognized
        guard !regions.isEmpty else {
            isWorking = false
            return
        }
        if TranslationSettings.usesOpenAI {
            do {
                let results = try await PageTranslator.translateWithAPI(regions)
                guard !Task.isCancelled, runID == currentRun else { return }
                translations = results
            } catch {
                guard !Task.isCancelled, runID == currentRun else { return }
                errorMessage = error.localizedDescription
            }
            isWorking = false
        } else {
            configuration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "ja"),
                target: Locale.Language(identifier: "en")
            )
        }
    }
}

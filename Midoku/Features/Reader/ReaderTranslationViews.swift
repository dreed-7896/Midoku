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

/// Translation options shown from the reader: translating the chapter, and how translations look.
struct ReaderTranslationOptionsView: View {
    let pageCount: Int
    let translateChapter: () -> Void
    @AppStorage("Translation.overlayFontSize") private var fontSize = 14.0
    @AppStorage("Translation.overlayOpacity") private var opacity = 0.94
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        translateChapter()
                        dismiss()
                    } label: {
                        Label(pageCount == 1 ? "Translate Chapter (1 page)" : "Translate Chapter (\(pageCount) pages)",
                              systemImage: "translate")
                    }
                    .disabled(pageCount == 0)
                } footer: {
                    Text("Translates every page of this chapter in one go, replacing saved translations. To translate a single page, use the translate button in the translation bar.")
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

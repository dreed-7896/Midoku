import SwiftUI
import Translation

@available(iOS 18.0, *)
struct TranslationModalView: View {
    let images: [UIImage]
    let webtoon: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var dialogues: [String] = []
    @State private var translations: [String] = []
    @State private var errorMessage: String?
    @State private var isWorking = true
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        NavigationStack {
            Group {
                if isWorking {
                    ProgressView("Translating page…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView("Translation unavailable", systemImage: "character.book.closed", description: Text(errorMessage))
                } else if translations.isEmpty {
                    ContentUnavailableView("No Japanese dialogue found", systemImage: "text.viewfinder")
                } else {
                    List(Array(translations.enumerated()), id: \.offset) { index, translation in
                        Text("Dialogue \(index + 1): \(translation)")
                            .font(.body)
                            .textSelection(.enabled)
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Translation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                if errorMessage != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Retry") {
                            Task { await start() }
                        }
                    }
                }
            }
        }
        .task { await start() }
        .translationTask(configuration) { session in
            guard !dialogues.isEmpty else { return }
            do {
                let requests = dialogues.enumerated().map {
                    TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
                }
                let results = try await session.translations(from: requests)
                guard !Task.isCancelled else { return }
                var ordered = Array(repeating: "", count: dialogues.count)
                for (index, result) in results.enumerated() {
                    let position = result.clientIdentifier.flatMap(Int.init) ?? index
                    if ordered.indices.contains(position) { ordered[position] = result.targetText }
                }
                guard ordered.allSatisfy({ !$0.isEmpty }) else {
                    throw TranslationError.message("Some dialogues could not be translated. Please try again.")
                }
                translations = ordered
                isWorking = false
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }

    private func start() async {
        isWorking = true
        errorMessage = nil
        translations = []
        configuration = nil
        dialogues = await PageTranslator.recognize(images, webtoon: webtoon)
        guard !Task.isCancelled else { return }
        guard !dialogues.isEmpty else {
            isWorking = false
            return
        }
        if TranslationSettings.usesOpenAI {
            do {
                translations = try await PageTranslator.translateWithAPI(dialogues)
            } catch {
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

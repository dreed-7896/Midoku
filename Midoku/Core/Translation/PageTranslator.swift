import Foundation
import UIKit

enum PageTranslator {
    @available(iOS 18.0, *)
    static func recognize(_ images: [UIImage], webtoon: Bool) async -> [String] {
        var dialogues: [String] = []
        for image in images {
            guard !Task.isCancelled else { return [] }
            let recognizer = TextRecognizer()
            await recognizer.analyze(image, language: "ja", forceLanguage: true)

            let clusters = recognizer.cachedClusters.sorted { lhs, rhs in
                let left = lhs.map { recognizer.observations[$0].boundingRect }.reduce(CGRect.null) { $0.union($1) }
                let right = rhs.map { recognizer.observations[$0].boundingRect }.reduce(CGRect.null) { $0.union($1) }
                if webtoon || abs(left.midY - right.midY) > 0.28 {
                    return left.midY > right.midY // Vision coordinates start at the bottom.
                }
                return left.midX > right.midX // Japanese manga reads right to left.
            }

            for cluster in clusters {
                let observations = cluster.map { recognizer.observations[$0] }
                let vertical = observations.filter {
                    $0.direction == .topToBottom || $0.boundingRect.height > $0.boundingRect.width * 1.1
                }.count > observations.count / 2
                let ordered = observations.sorted { lhs, rhs in
                    if vertical {
                        if abs(lhs.boundingRect.midX - rhs.boundingRect.midX) > 0.025 {
                            return lhs.boundingRect.midX > rhs.boundingRect.midX
                        }
                        return lhs.boundingRect.midY > rhs.boundingRect.midY
                    }
                    if abs(lhs.boundingRect.midY - rhs.boundingRect.midY) > 0.025 {
                        return lhs.boundingRect.midY > rhs.boundingRect.midY
                    }
                    return lhs.boundingRect.midX < rhs.boundingRect.midX
                }
                let text = ordered.map(\.text).joined(separator: vertical ? "" : " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Skip page numbers, English credits, and other non-Japanese text.
                if text.range(of: "[\\p{Han}\\p{Hiragana}\\p{Katakana}]", options: .regularExpression) != nil {
                    dialogues.append(text)
                }
            }
        }
        return dialogues
    }

    static func translateWithAPI(_ dialogues: [String]) async throws -> [String] {
        let endpoint = TranslationSettings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = TranslationSettings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: endpoint), let host = url.host,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(host)),
              !model.isEmpty else {
            throw TranslationError.message("Set a valid HTTPS chat completions URL and model in Translation settings.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !TranslationSettings.apiKey.isEmpty {
            request.setValue("Bearer \(TranslationSettings.apiKey)", forHTTPHeaderField: "Authorization")
        }
        let numbered = dialogues.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "Translate each numbered Japanese manga dialogue into natural English. Return ONLY a JSON array of English strings, one for each input dialogue, in the same order. Keep sound effects if present. Do not merge or omit items."],
                ["role": "user", "content": numbered]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw TranslationError.message("The translation server did not respond.")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw TranslationError.message("Translation server returned HTTP \(response.statusCode). Check its URL, API key, and model.")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranslationError.message("The server returned an unexpected chat completions response.")
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "["), let end = trimmed.lastIndex(of: "]"),
              let array = try? JSONDecoder().decode([String].self, from: Data(trimmed[start...end].utf8)),
              array.count == dialogues.count else {
            throw TranslationError.message("The model did not return one translation per dialogue. Try again or choose another model.")
        }
        return array
    }
}

enum TranslationError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        if case let .message(message) = self { return message }
        return nil
    }
}

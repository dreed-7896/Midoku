import Foundation
import Security

enum TranslationSettings {
    static let providerKey = "Translation.provider"
    static let endpointKey = "Translation.endpoint"
    static let modelKey = "Translation.model"
    static let mistralModelKey = "Translation.mistralModel"

    static let defaultEndpoint = "https://api.openai.com/v1/chat/completions"
    static let defaultModel = "gpt-4.1-mini"
    static let mistralEndpoint = "https://api.mistral.ai/v1/chat/completions"
    static let defaultMistralModel = "mistral-small-latest"

    enum Provider: String {
        case builtIn = "built-in"
        /// Any OpenAI-compatible chat completions server, with a user-entered URL.
        case openAI = "openai"
        case mistral
    }

    static var provider: Provider {
        UserDefaults.standard.string(forKey: providerKey).flatMap(Provider.init(rawValue:)) ?? .builtIn
    }

    /// Whether dialogue is sent to a chat completions API rather than translated on device.
    static var usesAPI: Bool { provider != .builtIn }

    static var endpoint: String {
        provider == .mistral ? mistralEndpoint : UserDefaults.standard.string(forKey: endpointKey) ?? defaultEndpoint
    }

    static var model: String {
        provider == .mistral
            ? UserDefaults.standard.string(forKey: mistralModelKey) ?? defaultMistralModel
            : UserDefaults.standard.string(forKey: modelKey) ?? defaultModel
    }

    private static let service = "com.raahat.Midoku.translation"

    /// Each API provider keeps its own key, so switching providers does not lose either one.
    private static func account(for provider: Provider) -> String {
        provider == .mistral ? "apiKey.mistral" : "apiKey"
    }

    static var apiKey: String { apiKey(for: provider) }

    static func apiKey(for provider: Provider) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func saveAPIKey(_ value: String, for provider: Provider) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider)
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

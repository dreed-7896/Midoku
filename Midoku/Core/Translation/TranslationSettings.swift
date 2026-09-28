import Foundation
import Security

enum TranslationSettings {
    static let providerKey = "Translation.provider"
    static let endpointKey = "Translation.endpoint"
    static let modelKey = "Translation.model"

    static var usesOpenAI: Bool {
        UserDefaults.standard.string(forKey: providerKey) == "openai"
    }

    static var endpoint: String {
        UserDefaults.standard.string(forKey: endpointKey) ?? "https://api.openai.com/v1/chat/completions"
    }

    static var model: String {
        UserDefaults.standard.string(forKey: modelKey) ?? "gpt-4.1-mini"
    }

    private static let service = "com.raahat.Midoku.translation"
    private static let account = "apiKey"

    static var apiKey: String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func saveAPIKey(_ value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

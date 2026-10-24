import SwiftUI

struct TranslationSettingsView: View {
    @AppStorage(TranslationSettings.providerKey) private var provider = TranslationSettings.Provider.builtIn.rawValue
    @AppStorage(TranslationSettings.endpointKey) private var endpoint = TranslationSettings.defaultEndpoint
    @AppStorage(TranslationSettings.modelKey) private var model = TranslationSettings.defaultModel
    @AppStorage(TranslationSettings.mistralModelKey) private var mistralModel = TranslationSettings.defaultMistralModel
    @State private var apiKey = TranslationSettings.apiKey

    private var selected: TranslationSettings.Provider { .init(rawValue: provider) ?? .builtIn }

    var body: some View {
        Form {
            Section {
                Picker("Model provider", selection: $provider) {
                    Text("Built-in (on device)").tag(TranslationSettings.Provider.builtIn.rawValue)
                    Text("Mistral AI").tag(TranslationSettings.Provider.mistral.rawValue)
                    Text("OpenAI compatible").tag(TranslationSettings.Provider.openAI.rawValue)
                }
            } footer: {
                Text("Translate Japanese dialogue into English. Pages are only translated when you ask, from the reader's translation bar: one page, or the whole chapter in its options. Built-in translation may download language models the first time you use it.")
            }

            switch selected {
            case .builtIn:
                EmptyView()
            case .mistral:
                Section {
                    TextField("Model name", text: $mistralModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    apiKeyField("API key")
                } header: {
                    Text("Mistral AI")
                } footer: {
                    Text("Create a key at console.mistral.ai. \(TranslationSettings.defaultMistralModel) is fast and inexpensive; mistral-large-latest gives more natural translations. The key is stored in this device's Keychain. Japanese OCR text is sent to Mistral when you translate a page.")
                }
            case .openAI:
                Section {
                    TextField("Chat completions URL", text: $endpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Model name", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    apiKeyField("API key (optional for local servers)")
                } header: {
                    Text("OpenAI compatible API")
                } footer: {
                    Text("Enter the full /v1/chat/completions URL. The key is stored in this device's Keychain. Japanese OCR text is sent to this server when you translate a page.")
                }
            }
        }
        .navigationTitle("Translation")
        // Each provider has its own key; show the one for the selected provider.
        .onChange(of: provider) { _ in apiKey = TranslationSettings.apiKey(for: selected) }
    }

    private func apiKeyField(_ title: String) -> some View {
        SecureField(title, text: $apiKey)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onChange(of: apiKey) { TranslationSettings.saveAPIKey($0, for: selected) }
    }
}

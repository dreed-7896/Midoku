import SwiftUI

struct TranslationSettingsView: View {
    @AppStorage(TranslationSettings.providerKey) private var provider = "built-in"
    @AppStorage(TranslationSettings.endpointKey) private var endpoint = "https://api.openai.com/v1/chat/completions"
    @AppStorage(TranslationSettings.modelKey) private var model = "gpt-4.1-mini"
    @State private var apiKey = TranslationSettings.apiKey

    var body: some View {
        Form {
            Section {
                Picker("Model provider", selection: $provider) {
                    Text("Built-in (on device)").tag("built-in")
                    Text("OpenAI compatible").tag("openai")
                }
            } footer: {
                Text("Translate Japanese dialogue into English. Built-in translation may download language models the first time you use it.")
            }

            if provider == "openai" {
                Section("OpenAI compatible API") {
                    TextField("Chat completions URL", text: $endpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Model name", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API key (optional for local servers)", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: apiKey) { TranslationSettings.saveAPIKey($0) }
                } footer: {
                    Text("Enter the full /v1/chat/completions URL. The key is stored in this device's Keychain. Japanese OCR text is sent to this server when you translate a page.")
                }
            }
        }
        .navigationTitle("Translation")
    }
}

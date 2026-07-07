import SwiftUI

struct SettingsView: View {
    @AppStorage(FolioStorageKey.baseURL) private var baseURL = ""
    @State private var apiKey = KeychainService.read(key: FolioStorageKey.apiKey) ?? ""
    @State private var showKeySaved = false

    var body: some View {
        Form {
            Section("Server") {
                TextField("Base URL", text: $baseURL, prompt: Text("https://example.com"))
                    .textContentType(.URL)
                    #if !os(macOS)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif

                HStack {
                    Button("Dev") {
                        baseURL = Secrets.portfolioUrl.isEmpty
                            ? "http://localhost:3001"
                            : Secrets.portfolioUrl
                    }
                    .buttonStyle(.bordered)
                    Button("Prod") {
                        let prod = Bundle.main.infoDictionary?["PORTFOLIO_URL"] as? String ?? ""
                        if !prod.isEmpty { baseURL = prod }
                    }
                    .buttonStyle(.bordered)
                }
            }

            Section("API Key") {
                SecureField("Bearer token", text: $apiKey, prompt: Text("Paste your API key"))
                Button("Save Key") {
                    try? KeychainService.save(apiKey, key: FolioStorageKey.apiKey)
                    showKeySaved = true
                }
                .disabled(apiKey.isEmpty)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .alert("API key saved.", isPresented: $showKeySaved) {
            Button("OK", role: .cancel) {}
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}

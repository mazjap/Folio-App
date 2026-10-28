import SwiftUI

struct SettingsView: View {
    @AppStorage(FolioStorageKey.activeEnvironment) private var activeEnvironment = "dev"
    @State private var devURL = UserDefaults.standard.string(forKey: FolioStorageKey.devBaseURL) ?? ""
    @State private var prodURL = UserDefaults.standard.string(forKey: FolioStorageKey.prodBaseURL) ?? ""
    @State private var devApiKey = KeychainService.read(key: FolioStorageKey.devApiKey) ?? ""
    @State private var prodApiKey = KeychainService.read(key: FolioStorageKey.prodApiKey) ?? ""
    @State private var showKeySaved = false
    
    private var isDev: Bool { activeEnvironment == "dev" }
    
    var body: some View {
        Form {
            Picker("Environment", selection: $activeEnvironment) {
                Text("Dev").tag("dev")
                Text("Prod").tag("prod")
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            
            Section("Server") {
                if isDev {
                    TextField("Base URL", text: $devURL, prompt: Text("http://localhost:3001"))
                        .textContentType(.URL)
                        #if !os(macOS)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        #endif
                        .onChange(of: devURL) {
                            UserDefaults.standard.set(devURL, forKey: FolioStorageKey.devBaseURL)
                        }
                } else {
                    TextField("Base URL", text: $prodURL, prompt: Text("https://example.com"))
                        .textContentType(.URL)
                        #if !os(macOS)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        #endif
                        .onChange(of: prodURL) {
                            UserDefaults.standard.set(prodURL, forKey: FolioStorageKey.prodBaseURL)
                        }
                }
            }
            
            Section("API Key") {
                if isDev {
                    SecureField("Bearer token", text: $devApiKey, prompt: Text("Paste your API key"))
                } else {
                    SecureField("Bearer token", text: $prodApiKey, prompt: Text("Paste your API key"))
                }
                Button("Save Key") {
                    if isDev {
                        try? KeychainService.save(devApiKey, key: FolioStorageKey.devApiKey)
                    } else {
                        try? KeychainService.save(prodApiKey, key: FolioStorageKey.prodApiKey)
                    }
                    showKeySaved = true
                }
                .disabled(isDev ? devApiKey.isEmpty : prodApiKey.isEmpty)
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

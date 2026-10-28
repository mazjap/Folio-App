import SwiftUI

@Observable
class SettingsViewModel {
    var devBaseURL: String { didSet { userDefaults.set(devBaseURL, forKey: FolioStorageKey.devBaseURL) } }
    var prodBaseURL: String { didSet { userDefaults.set(prodBaseURL, forKey: FolioStorageKey.prodBaseURL) } }
    var devAPIKey: String
    var prodAPIKey: String
    
    var error: KeychainService.KeychainError?
    var showsKeySaved = false
    
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let keychain: any KeychainStoring
    
    init(userDefaults: UserDefaults = .standard, keychain: any KeychainStoring = KeychainService()) {
        self.userDefaults = userDefaults
        self.keychain = keychain
        self.devBaseURL = userDefaults.string(forKey: FolioStorageKey.devBaseURL) ?? ""
        self.prodBaseURL = userDefaults.string(forKey: FolioStorageKey.prodBaseURL) ?? ""
        self.devAPIKey = keychain.read(key: FolioStorageKey.devApiKey) ?? ""
        self.prodAPIKey = keychain.read(key: FolioStorageKey.prodApiKey) ?? ""
    }
    
    // MARK: - Functions
    
    /// Saves the environment's API key to the Keychain, and reports whether it worked.
    func saveAPIKey(for environment: FolioEnvironment) {
        let key = switch environment {
        case .dev: devAPIKey
        case .prod: prodAPIKey
        }
        
        do {
            try keychain.save(key, key: environment.apiKeyKey)
            showsKeySaved = true
        } catch {
            self.error = error
        }
    }
}

struct SettingsView: View {
    @AppStorage(FolioStorageKey.activeEnvironment) private var environment = FolioEnvironment.dev
    @State private var vm: SettingsViewModel
    
    init(vm: SettingsViewModel = SettingsViewModel()) {
        self._vm = State(initialValue: vm)
    }
    
    var body: some View {
        Form {
            Picker("Environment", selection: $environment) {
                ForEach(FolioEnvironment.allCases) { environment in
                    Text(environment.title).tag(environment)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            
            Section("Server") {
                switch environment {
                case .dev: baseURLField(text: $vm.devBaseURL, prompt: "http://localhost:3001")
                case .prod: baseURLField(text: $vm.prodBaseURL, prompt: "https://example.com")
                }
            }
            
            Section("API Key") {
                let apiKey = switch environment {
                case .dev: $vm.devAPIKey
                case .prod: $vm.prodAPIKey
                }
                
                SecureField("Bearer token", text: apiKey, prompt: Text("Paste your API key"))
                Button("Save Key") {
                    vm.saveAPIKey(for: environment)
                }
                .disabled(apiKey.wrappedValue.isEmpty)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .alert("API key saved.", isPresented: $vm.showsKeySaved) {
            Button("OK", role: .cancel) {}
        }
        .errorAlert($vm.error)
    }
    
    private func baseURLField(text: Binding<String>, prompt: String) -> some View {
        TextField("Base URL", text: text, prompt: Text(prompt))
            .textContentType(.URL)
            #if !os(macOS)
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            #endif
    }
}

#Preview {
    NavigationStack {
        SettingsView(vm: SettingsViewModel(userDefaults: UserDefaults(suiteName: "FolioPreview") ?? .standard, keychain: TestKeychain()))
    }
}

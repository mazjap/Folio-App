import SwiftUI

@Observable
class SettingsViewModel {
    var devBaseURL: String { didSet { showsSaved = false } }
    var prodBaseURL: String { didSet { showsSaved = false } }
    var devAPIKey: String { didSet { showsSaved = false } }
    var prodAPIKey: String { didSet { showsSaved = false } }
    
    var error: KeychainService.KeychainError?
    
    /// Whether the shown environment's server settings were just saved.
    var showsSaved = false
    
    /// What's saved for each environment, to tell whether the fields have unsaved changes.
    private(set) var savedBaseURLs: [FolioEnvironment: String] = [:]
    private(set) var savedAPIKeys: [FolioEnvironment: String] = [:]
    
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let keychain: any KeychainStoring
    
    init(userDefaults: UserDefaults = .standard, keychain: any KeychainStoring = KeychainService()) {
        self.userDefaults = userDefaults
        self.keychain = keychain
        self.devBaseURL = userDefaults.string(forKey: FolioStorageKey.devBaseURL) ?? ""
        self.prodBaseURL = userDefaults.string(forKey: FolioStorageKey.prodBaseURL) ?? ""
        self.devAPIKey = ""
        self.prodAPIKey = ""
        
        for environment in FolioEnvironment.allCases {
            savedBaseURLs[environment] = userDefaults.string(forKey: environment.baseURLKey) ?? ""
            do {
                let key = try keychain.read(key: environment.apiKeyKey) ?? ""
                savedAPIKeys[environment] = key
                setAPIKey(key, for: environment)
            } catch {
                self.error = error
            }
        }
    }
    
    // MARK: - Functions
    
    func baseURL(for environment: FolioEnvironment) -> String {
        switch environment {
        case .dev: devBaseURL
        case .prod: prodBaseURL
        }
    }
    
    func apiKey(for environment: FolioEnvironment) -> String {
        switch environment {
        case .dev: devAPIKey
        case .prod: prodAPIKey
        }
    }
    
    /// Why the environment's base URL can't be saved, or `nil` if it can. An empty URL can be saved (it turns the environment off).
    func baseURLIssue(for environment: FolioEnvironment) -> ServerURL.Issue? {
        let text = baseURL(for: environment)
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, case let .failure(issue) = ServerURL.normalize(text) else { return nil }
        
        return issue
    }
    
    func hasChanges(for environment: FolioEnvironment) -> Bool {
        baseURL(for: environment) != savedBaseURLs[environment] || apiKey(for: environment) != savedAPIKeys[environment]
    }
    
    /// Saves the environment's base URL and API key together, so a half-typed address never becomes the server Folio talks to. An empty API key removes the saved one.
    func save(for environment: FolioEnvironment) {
        guard baseURLIssue(for: environment) == nil else { return }
        
        let url = (try? ServerURL.normalize(baseURL(for: environment)).get()) ?? ""
        userDefaults.set(url, forKey: environment.baseURLKey)
        savedBaseURLs[environment] = url
        setBaseURL(url, for: environment)
        
        let key = apiKey(for: environment).trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if key != savedAPIKeys[environment] {
                if key.isEmpty {
                    try keychain.delete(key: environment.apiKeyKey)
                } else {
                    try keychain.save(key, key: environment.apiKeyKey)
                }
                savedAPIKeys[environment] = key
            }
            setAPIKey(key, for: environment)
            showsSaved = true
        } catch {
            self.error = error
        }
    }
    
    private func setBaseURL(_ url: String, for environment: FolioEnvironment) {
        switch environment {
        case .dev: devBaseURL = url
        case .prod: prodBaseURL = url
        }
    }
    
    private func setAPIKey(_ key: String, for environment: FolioEnvironment) {
        switch environment {
        case .dev: devAPIKey = key
        case .prod: prodAPIKey = key
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
            Section {
                Picker("Environment", selection: $environment) {
                    ForEach(FolioEnvironment.allCases) { environment in
                        Text(environment.longTitle).tag(environment)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Environment")
            } footer: {
                switch environment {
                case .dev:
                    Text("Folio reads and writes content on your development server.")
                case .prod:
                    Label("Changes you save publish to your live site.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            
            Section {
                switch environment {
                case .dev: baseURLField(text: $vm.devBaseURL, prompt: "http://localhost:3001")
                case .prod: baseURLField(text: $vm.prodBaseURL, prompt: "https://example.com")
                }
                
                if let issue = vm.baseURLIssue(for: environment) {
                    Label(issue.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                
                let apiKey = switch environment {
                case .dev: $vm.devAPIKey
                case .prod: $vm.prodAPIKey
                }
                
                LabeledContent {
                    SecureField("API Key", text: apiKey, prompt: Text("Paste your API key"))
                        .labelsHidden()
                } label: {
                    Text("API Key")
                }
                
                Button("Save \(environment.title) Settings") {
                    vm.save(for: environment)
                }
                .disabled(!vm.hasChanges(for: environment) || vm.baseURLIssue(for: environment) != nil)
                .keyboardShortcut("s", modifiers: .command)
            } header: {
                Text("\(environment.longTitle) Server")
            } footer: {
                if vm.showsSaved {
                    Label("Saved. The key is in the Keychain.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("Nothing changes until you save. The key is kept in this device's Keychain and sent with every change; saving an empty key removes it.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: environment) { vm.showsSaved = false }
        .errorAlert($vm.error)
    }
    
    private func baseURLField(text: Binding<String>, prompt: String) -> some View {
        LabeledContent("Base URL") {
            TextField("Base URL", text: text, prompt: Text(prompt))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
        }
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

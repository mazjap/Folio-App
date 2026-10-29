import SwiftUI

struct ContentView: View {
    private let postRepo: any PostRepositoryProtocol
    private let projectRepo: any ProjectRepositoryProtocol
    private let mediaRepo: any MediaRepositoryProtocol
    private let appsRepo: any AppsRepositoryProtocol
    private let drafts: DraftStore
    private let userDefaults: UserDefaults
    private let keychain: any KeychainStoring
    
    init(
        postRepo: any PostRepositoryProtocol = PostRepository(),
        projectRepo: any ProjectRepositoryProtocol = ProjectRepository(),
        mediaRepo: any MediaRepositoryProtocol = MediaRepository(),
        appsRepo: any AppsRepositoryProtocol = AppsRepository(),
        drafts: DraftStore = .live,
        userDefaults: UserDefaults = .standard,
        keychain: any KeychainStoring = KeychainService()
    ) {
        self.postRepo = postRepo
        self.projectRepo = projectRepo
        self.mediaRepo = mediaRepo
        self.appsRepo = appsRepo
        self.drafts = drafts
        self.userDefaults = userDefaults
        self.keychain = keychain
    }
    
    var body: some View {
        TabView {
            Tab("Projects", systemImage: "folder") {
                ProjectsView(repo: projectRepo, mediaRepo: mediaRepo, drafts: drafts)
            }
            Tab("Posts", systemImage: "doc.text") {
                PostsView(repo: postRepo, mediaRepo: mediaRepo, drafts: drafts)
            }
            Tab("Apps", systemImage: "square.grid.2x2") {
                AppsView(vm: AppsViewModel(userDefaults: userDefaults), repo: appsRepo)
            }
            // NOTE: - macOS has a Settings window (⌘,) instead. Two settings views would each keep their own copy of the fields and could save stale values over each other.
            #if !os(macOS)
            Tab("Settings", systemImage: "gear") {
                NavigationStack {
                    SettingsView(vm: SettingsViewModel(userDefaults: userDefaults, keychain: keychain))
                }
            }
            #endif
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

#Preview {
    ContentView(
        postRepo: TestPostRepository(),
        projectRepo: TestProjectRepository(),
        mediaRepo: TestMediaRepository(),
        appsRepo: TestAppsRepository(),
        drafts: .temporary(),
        userDefaults: UserDefaults(suiteName: "FolioPreview") ?? .standard,
        keychain: TestKeychain()
    )
}

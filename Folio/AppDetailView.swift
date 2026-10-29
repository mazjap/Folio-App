import SwiftUI

@Observable
class AppDetailViewModel {
    var privacyPolicy: AppPrivacyPolicy?
    var support: AppSupport?
    var privacyPolicyMissing = false
    var supportMissing = false
    /// Why the privacy policy couldn't be loaded, other than not existing.
    var privacyPolicyError: APIError?
    /// Why the support page couldn't be loaded, other than not existing.
    var supportError: APIError?
    var isLoading = false
    
    let appId: String
    @ObservationIgnored private let repo: any AppsRepositoryProtocol
    
    init(appId: String, repo: any AppsRepositoryProtocol = AppsRepository()) {
        self.appId = appId
        self.repo = repo
    }
    
    func load() async {
        isLoading = true
        privacyPolicyMissing = false
        supportMissing = false
        privacyPolicyError = nil
        supportError = nil
        defer { isLoading = false }
        
        do {
            privacyPolicy = try await repo.fetchPrivacyPolicy(appId: appId)
        } catch {
            privacyPolicy = nil
            if case .notFound = error {
                privacyPolicyMissing = true
            } else if !error.isCancellation {
                privacyPolicyError = error
            }
        }
        
        do {
            support = try await repo.fetchSupport(appId: appId)
        } catch {
            support = nil
            if case .notFound = error {
                supportMissing = true
            } else if !error.isCancellation {
                supportError = error
            }
        }
    }
}

struct AppDetailView: View {
    @AppStorage(FolioStorageKey.activeEnvironment) private var environment = FolioEnvironment.dev
    @State private var vm: AppDetailViewModel
    private let appId: String
    private let repo: any AppsRepositoryProtocol
    
    init(appId: String, repo: any AppsRepositoryProtocol = AppsRepository()) {
        self._vm = State(initialValue: AppDetailViewModel(appId: appId, repo: repo))
        self.appId = appId
        self.repo = repo
    }
    
    var body: some View {
        List {
            Section("Privacy Policy") {
                if vm.isLoading {
                    ProgressView()
                } else if let policy = vm.privacyPolicy {
                    NavigationLink {
                        AppPrivacyPolicyEditorView(
                            appId: appId,
                            repo: repo,
                            existing: policy,
                            onSave: { vm.privacyPolicy = $0 },
                            onDelete: { vm.privacyPolicy = nil; vm.privacyPolicyMissing = true }
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(policy.appName)
                            Text("Last updated \(policy.lastUpdated)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if vm.privacyPolicyMissing {
                    NavigationLink {
                        AppPrivacyPolicyEditorView(
                            appId: appId,
                            repo: repo,
                            existing: nil,
                            onSave: { vm.privacyPolicy = $0; vm.privacyPolicyMissing = false },
                            onDelete: {}
                        )
                    } label: {
                        Label("Add Privacy Policy", systemImage: "plus.circle")
                            .foregroundStyle(.secondary)
                    }
                } else if let error = vm.privacyPolicyError {
                    LoadFailedRow(error: error) { Task { await vm.load() } }
                }
            }
            
            Section("Support") {
                if vm.isLoading {
                    ProgressView()
                } else if let support = vm.support {
                    NavigationLink {
                        AppSupportEditorView(
                            appId: appId,
                            repo: repo,
                            existing: support,
                            onSave: { vm.support = $0 },
                            onDelete: { vm.support = nil; vm.supportMissing = true }
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(support.appName)
                            Text("v\(support.version)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if vm.supportMissing {
                    NavigationLink {
                        AppSupportEditorView(
                            appId: appId,
                            repo: repo,
                            existing: nil,
                            onSave: { vm.support = $0; vm.supportMissing = false },
                            onDelete: {}
                        )
                    } label: {
                        Label("Add Support Page", systemImage: "plus.circle")
                            .foregroundStyle(.secondary)
                    }
                } else if let error = vm.supportError {
                    LoadFailedRow(error: error) { Task { await vm.load() } }
                }
            }
        }
        .navigationTitle(appId)
        .navigationSubtitle(environment.longTitle)
        .task { await vm.load() }
        // NOTE: - The pages shown are the environment's, so another server's pages are never edited from here.
        .onChange(of: environment) {
            Task { await vm.load() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await vm.load() }
                }
                .disabled(vm.isLoading)
            }
        }
    }
}

// MARK: - Load failure row

/// Why a page couldn't be loaded, with a way to try again.
private struct LoadFailedRow: View {
    private let error: APIError
    private let onRetry: () -> Void
    
    init(error: APIError, onRetry: @escaping () -> Void) {
        self.error = error
        self.onRetry = onRetry
    }
    
    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Couldn't load")
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button("Try Again", action: onRetry)
        }
    }
}

#Preview {
    NavigationStack {
        AppDetailView(appId: AppPrivacyPolicy.sample.id, repo: TestAppsRepository())
    }
}

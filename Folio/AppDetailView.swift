import SwiftUI

@Observable
class AppDetailViewModel {
    var privacyPolicy: AppPrivacyPolicy?
    var support: AppSupport?
    var privacyPolicyMissing = false
    var supportMissing = false
    var privacyPolicyFailed = false
    var supportFailed = false
    var isLoading = false

    let appId: String
    private let repo = AppsRepository()

    init(appId: String) { self.appId = appId }

    func load() async {
        isLoading = true
        privacyPolicyMissing = false; supportMissing = false
        privacyPolicyFailed = false; supportFailed = false
        defer { isLoading = false }

        do {
            privacyPolicy = try await repo.fetchPrivacyPolicy(appId: appId)
        } catch {
            privacyPolicy = nil
            if case .notFound = error { privacyPolicyMissing = true }
            else if !error.isCancellation { privacyPolicyFailed = true }
        }

        do {
            support = try await repo.fetchSupport(appId: appId)
        } catch {
            support = nil
            if case .notFound = error { supportMissing = true }
            else if !error.isCancellation { supportFailed = true }
        }
    }
}

struct AppDetailView: View {
    let appId: String
    @State private var vm: AppDetailViewModel

    init(appId: String) {
        self.appId = appId
        self._vm = State(initialValue: AppDetailViewModel(appId: appId))
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
                            existing: nil,
                            onSave: { vm.privacyPolicy = $0; vm.privacyPolicyMissing = false },
                            onDelete: {}
                        )
                    } label: {
                        Label("Add Privacy Policy", systemImage: "plus.circle")
                            .foregroundStyle(.secondary)
                    }
                } else if vm.privacyPolicyFailed {
                    Label("Failed to load", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section("Support") {
                if vm.isLoading {
                    ProgressView()
                } else if let support = vm.support {
                    NavigationLink {
                        AppSupportEditorView(
                            appId: appId,
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
                            existing: nil,
                            onSave: { vm.support = $0; vm.supportMissing = false },
                            onDelete: {}
                        )
                    } label: {
                        Label("Add Support Page", systemImage: "plus.circle")
                            .foregroundStyle(.secondary)
                    }
                } else if vm.supportFailed {
                    Label("Failed to load", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle(appId)
        .task { await vm.load() }
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

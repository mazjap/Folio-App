import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Projects", systemImage: "folder") {
                ProjectsView()
            }
            Tab("Posts", systemImage: "doc.text") {
                PostsView()
            }
            Tab("Settings", systemImage: "gear") {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

#Preview {
    ContentView()
}

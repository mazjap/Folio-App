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
            Tab("Apps", systemImage: "square.grid.2x2") {
                AppsView()
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

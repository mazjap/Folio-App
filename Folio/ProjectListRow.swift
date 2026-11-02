import SwiftUI

struct ProjectListRow: View {
    private let project: ProjectPreview
    
    init(project: ProjectPreview) {
        self.project = project
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MediaThumbnail(path: project.heroImage, placeholderSystemImage: "folder")
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(project.title)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if project.featured {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Featured")
                    }
                }
                
                Text(project.tagline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                
                HStack(spacing: 6) {
                    ProjectStatusBadge(status: project.status)
                    
                    if let category = project.category {
                        Text(category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ProjectStatusBadge: View {
    private let status: ProjectStatus
    
    init(status: ProjectStatus) {
        self.status = status
    }
    
    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
    
    private var label: String {
        switch status {
        case .active: "Active"
        case .inProgress: "In Progress"
        case .archived: "Archived"
        }
    }
    
    private var color: Color {
        switch status {
        case .active: .green
        case .inProgress: .orange
        case .archived: .secondary
        }
    }
}

#Preview {
    List {
        ProjectListRow(project: ProjectDetail.sample.preview)
    }
}

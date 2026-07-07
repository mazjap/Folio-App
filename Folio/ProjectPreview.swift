import SwiftUI

struct ProjectListRow: View {
    let project: ProjectPreview

    var body: some View {
        HStack(spacing: 12) {
            if let url = mediaURL(for: project.heroImage) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15))
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(project.title)
                    .font(.headline)
                Text(project.tagline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let category = project.category {
                    Text(category)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                ProjectStatusBadge(status: project.status)
                if project.featured {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct ProjectStatusBadge: View {
    let status: ProjectStatus

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        switch status {
        case .active: return "Active"
        case .inProgress: return "In Progress"
        case .archived: return "Archived"
        }
    }

    private var color: Color {
        switch status {
        case .active: return .green
        case .inProgress: return .orange
        case .archived: return .secondary
        }
    }
}

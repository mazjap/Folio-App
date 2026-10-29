import SwiftUI

/// Why an editor can't save yet, listed where its fields are.
struct ValidationIssuesView: View {
    private let issues: [String]
    
    init(issues: [String]) {
        self.issues = issues
    }
    
    var body: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(issues, id: \.self) { issue in
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Can't save yet: \(issues.joined(separator: " "))")
        }
    }
}

#Preview {
    ValidationIssuesView(issues: ["Enter a title.", "Enter a tagline."])
        .padding()
}

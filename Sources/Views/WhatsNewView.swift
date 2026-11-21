import SwiftUI

/// "Yang baru" untuk versi yang terpasang, dari CHANGELOG.md.
struct WhatsNewView: View {
    private let notes = Changelog.notes(for: UpdateService.currentVersion)

    private func md(_ s: String) -> Text {
        if let a = try? AttributedString(markdown: s) { return Text(a) }
        return Text(s)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("What's new in {0}", UpdateService.currentVersion)).font(.title2).bold()
                if let n = notes {
                    ForEach(Array(n.lines.enumerated()), id: \.offset) { _, line in
                        if line.hasPrefix("### ") {
                            md(String(line.dropFirst(4))).font(.headline).padding(.top, 8)
                        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                md(String(line.dropFirst(2))).fixedSize(horizontal: false, vertical: true)
                            }
                        } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                            md(line).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Text(tr("No release notes for this version.")).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(tr("What's new"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI

struct IndexingOptionsView: View {
    @Binding var options: IndexOptions
    var folderCount: Int
    var onStart: () -> Void
    var onSkip: () -> Void
    var onBack: () -> Void

    var body: some View {
        CenteredScrollContainer(maxContentWidth: 560) {
            VStack(spacing: 24) {
                Text(folderCount == 1 ? "Index this folder?" : "Index these folders?")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.themeText)
                Text("Choose which local analysis passes Mandoline should run before slicing. Phase 1 uses on-device Apple Vision embeddings; CLIP is scaffolded for a future model asset.")
                    .font(.system(size: 14))
                    .foregroundColor(.themeSecondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Visual similarity clusters", isOn: $options.semanticClusters)
                        .help("Groups visually similar media locally so you can review one cluster at a time. CLIP-powered semantic labels are planned for a later model asset.")
                    ComingSoonToggle(title: "Auto-categories", isOn: $options.autoCategories)
                        .help("Phase 2: labels clusters with on-device AI prompts such as screenshots, documents, receipts, people, and scenery.")
                    ComingSoonToggle(title: "Near-duplicates", isOn: $options.nearDuplicates)
                        .help("Phase 3: finds repeated or very similar shots so you can keep one and remove the rest.")
                    ComingSoonToggle(title: "Blur and quality scores", isOn: $options.blurScores)
                        .help("Phase 3: flags blurry, low-detail, or hard-to-read images using local computer-vision metrics.")
                }
                .padding(20)
                .cardSurface(cornerRadius: 18, fill: .themeCard)

                HStack(spacing: 12) {
                    Button("Back", action: onBack)
                    Spacer()
                    Button("Skip Indexing", action: onSkip)
                    Button("Start Indexing", action: onStart)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .background(Color.themeBackground)
    }
}

private struct ComingSoonToggle: View {
    var title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle(title, isOn: Binding(get: { false }, set: { _ in isOn = false }))
                .disabled(true)
            Text("Coming soon")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.themeSecondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.themeSubtleBackground, in: Capsule())
        }
        .opacity(0.65)
    }
}

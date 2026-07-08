import SwiftUI

struct IndexingOptionsView: View {
    @Binding var options: IndexOptions
    var folderCount: Int
    var onStart: () -> Void
    var onSkip: () -> Void
    var onBack: () -> Void

    private var semanticClustersBinding: Binding<Bool> {
        Binding(
            get: { options.semanticClusters },
            set: { newValue in
                options.semanticClusters = newValue
                if !newValue {
                    options.autoCategories = false
                }
            }
        )
    }

    private var autoCategoriesBinding: Binding<Bool> {
        Binding(
            get: { options.autoCategories },
            set: { newValue in
                options.autoCategories = newValue
                if newValue {
                    options.semanticClusters = true
                }
            }
        )
    }

    var body: some View {
        CenteredScrollContainer(maxContentWidth: 560) {
            VStack(spacing: 24) {
                Text(folderCount == 1 ? "Index this folder?" : "Index these folders?")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.themeText)
                Text("Choose which local analysis passes Mandoline should run before slicing. Visual clusters use Apple Vision; Auto-categories run the local CLIP Python helper offline by default.")
                    .font(.system(size: 14))
                    .foregroundColor(.themeSecondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Visual similarity clusters", isOn: semanticClustersBinding)
                        .help("Groups visually similar media locally with Apple Vision so you can review one cluster at a time.")
                    Toggle("Auto-categories (requires cached CLIP)", isOn: autoCategoriesBinding)
                        .help("Runs the local CLIP helper offline to label clusters with categories such as screenshots, documents, receipts, people, and scenery. Set MANDOLINE_CLIP_INDEXER_PATH if the helper is outside a development checkout.")
                    Text("Auto-categories are offline/private from the app and require the Hugging Face/open_clip model to be pre-cached. Run the first setup/download from Terminal using the CLIP README; if setup is unavailable, use Back to Options or Slice Full Folder to recover.")
                        .font(.system(size: 12))
                        .foregroundColor(.themeSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
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

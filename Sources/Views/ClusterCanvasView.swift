import SwiftUI

struct ClusterCanvasView: View {
    var clusters: [MediaCluster]
    var indexService: IndexService
    var onSlice: (MediaCluster) -> Void
    var onSliceFullFolder: () -> Void
    var onBackToOptions: () -> Void
    var onCloseFolder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Indexed Clusters")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.themeText)
                    Text("Open a cluster to slice it with the current keep/delete shortcuts.")
                        .font(.system(size: 13))
                        .foregroundColor(.themeSecondaryText)
                }
                Spacer()
                Button("Close Folder", action: onCloseFolder)
            }
            .padding(.horizontal, 24)
            .padding(.top, 44)
            .padding(.bottom, 16)

            if clusters.isEmpty {
                Spacer()
                VStack(spacing: 14) {
                    Text("No clusters were found.")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.themeText)
                    Text("You can still review the folder directly or adjust indexing options.")
                        .font(.system(size: 13))
                        .foregroundColor(.themeSecondaryText)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 12) {
                        Button("Slice Full Folder", action: onSliceFullFolder)
                            .buttonStyle(.borderedProminent)
                        Button("Back to Options", action: onBackToOptions)
                        Button("Close Folder", role: .destructive, action: onCloseFolder)
                    }
                }
                .padding(24)
                .cardSurface(cornerRadius: 18, fill: .themeCard)
                Spacer()
            } else {
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        ForEach(clusters) { cluster in
                            ClusterCard(cluster: cluster) { onSlice(cluster) }
                                .position(x: 80 + cluster.position.x * 980, y: 80 + cluster.position.y * 620)
                        }
                    }
                    .frame(width: 1160, height: 760)
                    .padding(24)
                }
            }
        }
        .background(Color.themeBackground)
    }
}

private struct ClusterCard: View {
    var cluster: MediaCluster
    var onSlice: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ThumbnailMosaic(urls: cluster.previewURLs)
                .frame(height: 82)

            VStack(alignment: .leading, spacing: 3) {
                Text(cluster.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.themeText)
                    .lineLimit(1)

                Text("\(cluster.fileURLs.count) items · \(byteString(cluster.totalBytes))")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundColor(.themeSecondaryText)
                    .lineLimit(1)
            }

            if let first = cluster.fileURLs.first {
                Text(first.lastPathComponent)
                    .font(.system(size: 11))
                    .foregroundColor(.themeSecondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Button("Slice", action: onSlice)
                .controlSize(.small)
        }
        .padding(12)
        .frame(width: 176, alignment: .leading)
        .cardSurface(cornerRadius: 16, fill: .themeCard)
    }

    private func byteString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

private struct ThumbnailMosaic: View {
    var urls: [URL]

    private let columns = [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(Array(urls.prefix(4).enumerated()), id: \.element.path) { _, url in
                ThumbnailView(url: url)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            ForEach(0..<max(0, 4 - urls.prefix(4).count), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.themeSubtleBackground)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

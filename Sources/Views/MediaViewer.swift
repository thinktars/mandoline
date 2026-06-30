import SwiftUI
import AVKit

struct MediaViewer: View {
    var url: URL

    @State private var player: AVPlayer?
    @State private var isVideo = false
    @State private var endObserver: NSObjectProtocol?
    @State private var playbackError: String?

    var body: some View {
        ZStack {
            if isVideo {
                if let player {
                    // Use AppKit's AVPlayerView via NSViewRepresentable instead of
                    // SwiftUI's VideoPlayer: the latter crashes on instantiation
                    // through _AVKit_SwiftUI on this macOS/SDK combination.
                    PlayerView(player: player)
                }

                if let playbackError {
                    Text(playbackError)
                        .foregroundColor(.themeDanger)
                        .font(.system(size: 13, weight: .medium))
                        .padding(10)
                        .background(Color.themeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.themeBorder, lineWidth: 1))
                        .padding()
                }
            } else {
                if let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    Text("Unsupported format.")
                        .foregroundColor(.themeDanger)
                        .font(.system(size: 14, weight: .regular))
                }
            }
        }
        .task(id: url) {
            configureMedia()
        }
        .onDisappear {
            player?.pause()
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
                self.endObserver = nil
            }
        }
    }

    private func configureMedia() {
        playbackError = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        let ext = url.pathExtension.lowercased()
        if ["mp4", "mov", "avi", "mkv", "webm", "m4v"].contains(ext) {
            isVideo = true
            let item = AVPlayerItem(url: url)
            let newPlayer = AVPlayer(playerItem: item)
            player = newPlayer

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak newPlayer] _ in
                newPlayer?.seek(to: .zero)
                newPlayer?.play()
            }

            if item.asset.isPlayable {
                newPlayer.play()
            } else {
                playbackError = "This video can’t be played on macOS."
            }
        } else {
            isVideo = false
            player = nil
        }
    }
}

/// AppKit-backed video view. Avoids SwiftUI's `VideoPlayer`, which crashes
/// during view instantiation via `_AVKit_SwiftUI`.
private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

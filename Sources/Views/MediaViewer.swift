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
                if let player = player {
                    VideoPlayer(player: player)
                        .onAppear {
                            player.play()
                        }
                        .onDisappear {
                            player.pause()
                        }
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
                    Text("Unsupported Media Format")
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
                playbackError = "This video format is not playable on macOS."
            }
        } else {
            isVideo = false
            player = nil
        }
    }
}

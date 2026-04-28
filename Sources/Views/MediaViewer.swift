import SwiftUI
import AVKit

struct MediaViewer: View {
    var url: URL

    @State private var player: AVPlayer?
    @State private var isVideo = false
    @State private var endObserver: NSObjectProtocol?

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
            } else {
                if let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    Text("Unsupported Media Format")
                        .foregroundColor(.red)
                        .font(.system(size: 14, weight: .regular))
                }
            }
        }
        .onAppear {
            let ext = url.pathExtension.lowercased()
            if ["mp4", "mov", "avi", "mkv", "webm", "m4v"].contains(ext) {
                isVideo = true
                let newPlayer = AVPlayer(url: url)
                player = newPlayer

                // Loop video (ensure we don't leak observers across media changes)
                endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: newPlayer.currentItem,
                    queue: .main
                ) { [weak newPlayer] _ in
                    newPlayer?.seek(to: .zero)
                    newPlayer?.play()
                }
            } else {
                isVideo = false
            }
        }
        .onDisappear {
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
                self.endObserver = nil
            }
        }
    }
}

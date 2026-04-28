import SwiftUI
import SwiftData

@main
struct MandolineApp: App {
    var body: some Scene {
        WindowGroup {
            GalleryView()
                .modelContainer(for: [ProcessedFile.self], isUndoEnabled: false)
                .preferredColorScheme(.light)
        }
        .windowResizability(.contentMinSize)
    }
}

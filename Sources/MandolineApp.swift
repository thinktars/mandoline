import SwiftUI
import SwiftData

@main
struct MandolineApp: App {
    init() {
        FontLoader.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            GalleryView()
                .modelContainer(for: [ProcessedFile.self], isUndoEnabled: false)
                .preferredColorScheme(.light)
        }
        .windowResizability(.contentMinSize)
    }
}

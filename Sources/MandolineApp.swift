import SwiftUI
import SwiftData

@main
struct MandolineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        FontLoader.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            GalleryView()
                .modelContainer(for: [ProcessedFile.self], isUndoEnabled: false)
                .preferredColorScheme(.light)
                .frame(minWidth: 720, minHeight: 640)
        }
        .defaultSize(width: 1040, height: 860)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }
}

/// Purges any files Mandoline staged for deletion when the app quits, moving
/// them to the system Trash (Option B: session-scoped undo, commit on exit).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        ActionService.current?.purgeStaged()
    }
}

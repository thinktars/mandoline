import SwiftUI
import SwiftData
import Combine
import Sparkle

@main
struct MandolineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var folderManager = FolderManager()

    /// Sparkle updater. Only starts once a real EdDSA public key is configured
    /// (until then, starting it would fail its config check and alert on launch).
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: MandolineApp.isUpdaterConfigured,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    /// True once `SUPublicEDKey` in Info.plist is set to a real key.
    private static var isUpdaterConfigured: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return false
        }
        return !key.isEmpty && key != "REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY"
    }

    init() {
        FontLoader.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            GalleryView(folderManager: folderManager)
                .modelContainer(for: [ProcessedFile.self], isUndoEnabled: false)
                .preferredColorScheme(.light)
                .frame(minWidth: 720, minHeight: 640)
        }
        .defaultSize(width: 1040, height: 860)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandMenu("Go to Recent") {
                if folderManager.recentFolders.isEmpty {
                    Button("No recent folders") {}
                        .disabled(true)
                } else {
                    ForEach(folderManager.recentFolders, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            folderManager.openRecent(url)
                        }
                    }
                }
            }
        }
    }
}

/// Tracks whether Sparkle can currently check for updates so the menu item is
/// correctly enabled/disabled.
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

/// The "Check for Updates…" menu command.
struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
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

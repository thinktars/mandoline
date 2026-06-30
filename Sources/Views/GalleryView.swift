import SwiftUI
import SwiftData
import AVKit

struct GalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var folderManager = FolderManager()
    @State private var scannerService = ScannerService()
    @State private var actionService = ActionService()
    
    @Query private var processedFiles: [ProcessedFile]
    
    @State private var hasAcceptedOnboarding = UserDefaults.standard.bool(forKey: "HasAcceptedOnboarding")
    
    /// The titlebar shows the path to the current folder (plain text, centered,
    /// inline with the window controls) only when media is open — terminal-style.
    private var windowTitle: String {
        guard hasAcceptedOnboarding,
              !folderManager.selectedFolders.isEmpty,
              let url = scannerService.selectedURL else { return "" }
        return Self.abbreviatedPath(url.deletingLastPathComponent())
    }

    /// Abbreviates a `/Users/<name>/…` path to `~/…`, like a shell prompt.
    private static func abbreviatedPath(_ url: URL) -> String {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if parts.count >= 2, parts[0] == "Users" {
            let rest = parts.dropFirst(2)
            return rest.isEmpty ? "~" : "~/" + rest.joined(separator: "/")
        }
        return url.path
    }
    
    var body: some View {
        ZStack {
            Color.themeBackground.edgesIgnoringSafeArea(.all)
            
            if !hasAcceptedOnboarding {
                OnboardingView {
                    UserDefaults.standard.set(true, forKey: "HasAcceptedOnboarding")
                    hasAcceptedOnboarding = true
                }
            } else if folderManager.selectedFolders.isEmpty {
                FolderSelectionView(folderManager: folderManager)
            } else {
                MainContentView(
                    folderManager: folderManager,
                    scannerService: scannerService,
                    actionService: actionService,
                    processedFiles: processedFiles
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    if let window = NSApp.windows.first {
                        window.center()
                    }
                }
            }
        }
        .background(WindowConfigurator())
        .overlay(alignment: .top) {
            if !windowTitle.isEmpty {
                Text(windowTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.themeSecondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 90) // keep clear of the traffic lights
                    .frame(height: 28)
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}

struct FolderSelectionView: View {
    var folderManager: FolderManager
    
    var body: some View {
        CenteredScrollContainer(maxContentWidth: 520) {
            VStack(spacing: 24) {
                Text("Welcome to Mandoline")
                    .font(.custom("Merriweather-Bold", size: 34))
                    .foregroundColor(.themeText)
                    .multilineTextAlignment(.center)
                    .staggeredReveal(0)
                    
                Text("Choose the directory you want to scan for media. This app will find any subfolders by default too.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.themeText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .staggeredReveal(1)
                
                Button(action: {
                    folderManager.selectFolder()
                }) {
                    Text("Choose Folders...")
                }
                .buttonStyle(PillButtonStyle())
                .padding(.top, 4)
                .staggeredReveal(2)
                
                Text("Thanks for using Mandoline - an app for Superhuman-style keyboard shortcuts to delete, keep or navigate through large folders.\n\n- Rowan (The Applied Research Studio)")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.themeSecondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .staggeredReveal(3)
            }
        }
        .background(Color.themeBackground)
    }
}

struct HoverLinkButtonStyle: ButtonStyle {
    @State private var isHovered = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isHovered ? .themeText : .themeSecondaryText)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .onHover { hover in
                isHovered = hover
            }
    }
}

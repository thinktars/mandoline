import SwiftUI
import SwiftData
import AVKit

struct GalleryView: View {
    @Environment(\.modelContext) private var modelContext
    var folderManager: FolderManager
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
        return url.deletingLastPathComponent().abbreviatedTildePath
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
                    
                Text("Pick a folder to scan. Subfolders are included automatically.")
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

                if !folderManager.displayRecents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recently Sliced")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.themeSecondaryText)
                            .textCase(.uppercase)
                            .kerning(0.5)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(folderManager.displayRecents, id: \.self) { url in
                            Button {
                                folderManager.openRecent(url)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 14))
                                        .foregroundColor(.themeSecondaryText)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(url.lastPathComponent)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.themeText)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Text(url.abbreviatedTildePath)
                                            .font(.system(size: 11, weight: .regular))
                                            .foregroundColor(.themeSecondaryText)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.themeSecondaryText)
                                }
                            }
                            .buttonStyle(RecentRowButtonStyle())
                            .contextMenu {
                                Button("Remove from Recents", role: .destructive) {
                                    folderManager.removeRecent(url)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 360)
                    .padding(.top, 4)
                    .staggeredReveal(3)
                }
            }
        }

            StudioCreditLink()
                .padding(.bottom, 20)
                .staggeredReveal(4)
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

/// Footer credit: "Made for everyone by The Applied Research Studio ↗".
/// On hover the studio name darkens and the link-out icon grows with a
/// smooth, bounce-free spring.
struct StudioCreditLink: View {
    @Environment(\.openURL) private var openURL
    @State private var isHovered = false

    private let url = URL(string: "https://thinktars.com")!

    var body: some View {
        HStack(spacing: 5) {
            Text("Made for everyone by")
                .foregroundColor(.themeSecondaryText)

            Button {
                openURL(url)
            } label: {
                HStack(spacing: 3) {
                    Text("The Applied Research Studio")
                        .foregroundColor(isHovered ? .themeText : .themeSecondaryText)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isHovered ? .themeText : .themeSecondaryText)
                        .scaleEffect(isHovered ? 1.2 : 1.0)
                        .offset(x: isHovered ? 1 : 0, y: isHovered ? -1 : 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .onHover { hovering in
                withAnimation(.spring(duration: 0.3, bounce: 0)) {
                    isHovered = hovering
                }
            }
        }
        .font(.system(size: 13, weight: .regular))
    }
}

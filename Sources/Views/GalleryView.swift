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
                .frame(minWidth: 1000, idealWidth: 1200, maxWidth: .infinity, minHeight: 700, idealHeight: 800, maxHeight: .infinity)
                .onAppear {
                    if let window = NSApp.windows.first {
                        window.center()
                    }
                }
            }
        }
    }
}

struct FolderSelectionView: View {
    var folderManager: FolderManager
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 12, y: 6)
                .padding(.bottom, 8)
                
            Text("Mandoline")
                .font(.custom("Merriweather-Bold", size: 36))
                .foregroundColor(.themeText)
                .padding(.bottom, 4)
                
            Text("Choose the directory you want to scan for media. This app will find any subfolders by default too.")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.themeText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: {
                folderManager.selectFolder()
            }) {
                Text("Choose Folders...")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 24)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 10)
            .background(Color.themeContainer, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.themeBorder, lineWidth: 1)
            )
            .foregroundColor(.themeText)
            .controlSize(.regular)
            .padding(.top, 4)
            .padding(.bottom, 24)
            
                Text("Thanks for using Mandoline - an app for Superhuman-style keyboard shortcuts to delete, keep or navigate through large folders.\n\n- Rowan (The Applied Research Studio)")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.themeBorder)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                
                Spacer()
            }
            .padding(60)
            .frame(minWidth: 700, idealWidth: 800, maxWidth: .infinity, minHeight: 600, idealHeight: 700, maxHeight: .infinity)
            .background(Color.themeBackground)
    }
}

struct HoverLinkButtonStyle: ButtonStyle {
    @State private var isHovered = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isHovered ? .themeText : .themeBorder)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .onHover { hover in
                isHovered = hover
            }
    }
}

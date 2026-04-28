import SwiftUI

struct OnboardingView: View {
    var onAccept: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 12, y: 6)
                .padding(.bottom, 8)
            
            Text("Mandoline")
                .font(.custom("Merriweather-Bold", size: 36))
                .foregroundColor(.themeText)
            
            Text("Slice down your bulky folders.")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(.themeBorder)
            
            VStack(spacing: 16) {
                Text("Mandoline can move your folder items to trash at your discretion. It does not monitor, log, or use any of your personal materials and runs fully offline. Any deletions made are at your own risk and will. This software is offered 'as-is' and free of any charge.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.themeText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: 600)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.themeBorder.opacity(0.3), lineWidth: 1)
                    )
            }
            .padding(.vertical, 20)
            
            Button(action: onAccept) {
                Text("I Understand & Agree")
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 20)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 12)
            .background(Color.themeContainer, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.themeBorder, lineWidth: 1)
            )
            .foregroundColor(.themeText)
            .controlSize(.large)
            
            Spacer()
            
            Spacer()
            
            VStack(spacing: 8) {
                Link(destination: URL(string: "https://github.com/thinktars/mandoline")!) {
                    Image("github-circle", bundle: .main)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .foregroundColor(.themeBorder)
                }
                .buttonStyle(HoverLinkButtonStyle())
                
                Text("Open-sourced under the MIT Licence.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.themeBorder)
            }
            .padding(.bottom, 20)
        }
        .padding(60)
        .frame(minWidth: 700, idealWidth: 800, maxWidth: .infinity, minHeight: 600, idealHeight: 700, maxHeight: .infinity)
        .background(Color.themeBackground)
    }
}

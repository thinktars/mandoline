import SwiftUI

struct OnboardingView: View {
    var onAccept: () -> Void

    var body: some View {
        CenteredScrollContainer(maxContentWidth: 560) {
            VStack(spacing: 20) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .staggeredReveal(0)

                VStack(spacing: 8) {
                    Text("Mandoline")
                        .font(.custom("Merriweather-Bold", size: 34))
                        .foregroundColor(.themeText)

                    Text("Slice down your bulky folders.")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(.themeSecondaryText)
                }
                .staggeredReveal(1)

                Text("Mandoline moves files you choose to the Trash. It runs fully offline and never logs or uses your data. Deletions are at your own risk. Free and provided as-is.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.themeText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                    .cardSurface(cornerRadius: 14)
                    .padding(.top, 4)
                    .staggeredReveal(2)

                Button(action: onAccept) {
                    Text("I Understand")
                }
                .buttonStyle(PillButtonStyle(fontSize: 15))
                .padding(.top, 4)
                .staggeredReveal(3)

                VStack(spacing: 8) {
                    Link(destination: URL(string: "https://github.com/thinktars/mandoline")!) {
                        Image("github-circle", bundle: .main)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                            .foregroundColor(.themeSecondaryText)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HoverLinkButtonStyle())

                    Text("Open source under the MIT licence.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.themeSecondaryText)
                }
                .padding(.top, 8)
                .staggeredReveal(4)
            }
        }
        .background(Color.themeBackground)
    }
}

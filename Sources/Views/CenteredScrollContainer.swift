import SwiftUI

/// A reusable container that keeps content centered both horizontally and
/// vertically, constrains it to a comfortable max width, and falls back to
/// scrolling when the window becomes too small so nothing is ever clipped.
struct CenteredScrollContainer<Content: View>: View {
    var maxContentWidth: CGFloat = 560
    var padding: CGFloat = 40
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                content()
                    .frame(maxWidth: maxContentWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, padding)
                    .padding(.vertical, padding)
                    // Fill the available height so the content can center
                    // vertically, but only down to its natural size so it
                    // scrolls instead of clipping when space is tight.
                    .frame(minHeight: proxy.size.height)
            }
        }
    }
}

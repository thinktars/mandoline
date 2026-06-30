import SwiftUI

extension Color {
    static let themeBackground = Color(red: 0.976, green: 0.976, blue: 0.980) // #F9F9FA Background (Main) — neutral grey, faint cool cast
    static let themeSubtleBackground = Color(red: 0.933, green: 0.941, blue: 0.949) // #EEF0F2 Surface (Subtle) — cool grey, not blue
    static let themePrimaryAction = Color(red: 0.533, green: 0.690, blue: 0.800) // #88B0CC Accent — soft blue hue (selection only)
    static let themeText = Color(red: 0.176, green: 0.176, blue: 0.176) // #2D2D2D Text (Primary)
    static let themeSecondaryText = Color(red: 0.431, green: 0.431, blue: 0.443) // #6E6E71 Text (Secondary)
    static let themeButtonSurface = Color(red: 0.894, green: 0.898, blue: 0.910) // #E4E5E8 Button Surface — cool grey
    static let themeBorder = Color(red: 0.839, green: 0.847, blue: 0.863) // #D6D8DC Border / Divider — cool grey
    static let themeSuccess = Color(red: 0.298, green: 0.686, blue: 0.314) // #4CAF50 Success
    static let themeDanger = Color(red: 0.898, green: 0.451, blue: 0.451) // #E57373 Error/Danger
}

extension View {
    func standardCornerRadius() -> some View {
        self.cornerRadius(12)
    }
    
    func buttonCornerRadius() -> some View {
        self.cornerRadius(8)
    }
}

// MARK: - Paths

extension URL {
    /// Abbreviates a `/Users/<name>/…` path to `~/…`, like a shell prompt.
    var abbreviatedTildePath: String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if parts.count >= 2, parts[0] == "Users" {
            let rest = parts.dropFirst(2)
            return rest.isEmpty ? "~" : "~/" + rest.joined(separator: "/")
        }
        return path
    }
}

// MARK: - Surfaces

extension View {
    /// Elevated card surface: a hairline ring plus two soft, layered shadows for
    /// natural depth (shadows adapt to any background; solid borders don't).
    func cardSurface(cornerRadius: CGFloat = 12, fill: Color = .white) -> some View {
        self
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
            .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
    }

    /// Subtle neutral 1px outline for images. Pure black at low opacity so it
    /// never picks up the surface color underneath and reads as a dirty edge.
    func imageOutline(cornerRadius: CGFloat) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Button Styles

/// Standard pill action button. Includes its own surface so the tactile
/// press-scale wraps the whole control, and keeps every CTA visually consistent.
struct PillButtonStyle: ButtonStyle {
    var fontSize: CGFloat = 14
    var cornerRadius: CGFloat = 10

    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .medium))
            .foregroundColor(.themeText)
            .padding(.vertical, 11)
            .padding(.horizontal, 24)
            .background(
                Color.themeButtonSurface.opacity(isHovered ? 0.85 : 1.0),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
            .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { isHovered = $0 }
    }
}

/// Circular icon button with a guaranteed 40×40 hit area and press feedback.
struct CircleIconButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 20, height: 20)
            .padding(10)
            .background(
                Color.themeSubtleBackground.opacity(isHovered ? 0.85 : 1.0),
                in: Circle()
            )
            .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(Circle())
            .onHover { isHovered = $0 }
    }
}

/// Row-style button for list entries (e.g. recent folders): subtle hover fill,
/// hairline ring, and a gentle press-scale.
struct RecentRowButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                Color.themeSubtleBackground.opacity(isHovered ? 1.0 : 0.55),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onHover { isHovered = $0 }
    }
}

// MARK: - Staggered Enter Animation

/// Splits an enter animation into staggered chunks: each element fades, lifts,
/// and unblurs with a small per-index delay so content arrives in sequence.
struct StaggeredReveal: ViewModifier {
    let index: Int
    var baseDelay: Double = 0.04
    var step: Double = 0.08
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .blur(radius: shown ? 0 : 4)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4).delay(baseDelay + Double(index) * step)) {
                    shown = true
                }
            }
    }
}

extension View {
    func staggeredReveal(_ index: Int) -> some View {
        modifier(StaggeredReveal(index: index))
    }
}


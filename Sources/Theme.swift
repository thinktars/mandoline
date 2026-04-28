import SwiftUI

extension Color {
    static let themeBackground = Color(red: 0.976, green: 0.976, blue: 0.976) // #F9F9F9 Background (Main)
    static let themeSubtleBackground = Color(red: 0.910, green: 0.945, blue: 0.973) // #E8F1F8 Background (Subtle)
    static let themePrimaryAction = Color(red: 0.478, green: 0.706, blue: 0.882) // #7AB4E1 Primary Action
    static let themeText = Color(red: 0.176, green: 0.176, blue: 0.176) // #2D2D2D Text (Primary)
    static let themeSecondaryText = Color(red: 0.431, green: 0.431, blue: 0.431) // #6E6E6E Text (Secondary)
    static let themeButtonSurface = Color(red: 0.878, green: 0.878, blue: 0.878) // #E0E0E0 Button Surface
    static let themeBorder = Color(red: 0.820, green: 0.820, blue: 0.820) // #D1D1D1 Border / Divider
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


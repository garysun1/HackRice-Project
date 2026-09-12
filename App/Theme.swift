import SwiftUI

// Clinical-calm palette: soft backgrounds, one teal accent, SF rounded type.
extension Color {
    static let brandTeal = Color(red: 0.0, green: 0.55, blue: 0.55)
    static let appBackground = Color(uiColor: .systemGroupedBackground)

    /// Severity 1–10 → color ramp used by badges and charts.
    static func severity(_ value: Int) -> Color {
        switch value {
        case ..<4: return .brandTeal
        case ..<7: return .orange
        default: return .red
        }
    }
}

extension Font {
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded).weight(weight)
    }
}

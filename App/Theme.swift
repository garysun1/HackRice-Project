import SwiftUI
import HealthCore

// Clinical-calm palette: soft backgrounds, one teal accent, SF rounded type.
extension Color {
    static let brandTeal = Color(red: 0.0, green: 0.55, blue: 0.55)
    static let appBackground = Color(uiColor: .systemGroupedBackground)

    /// Severity 1–10 → color ramp used by badges and charts.
    static func severity(_ value: Int?) -> Color {
        switch value {
        case nil: return .gray
        case .some(..<4): return .brandTeal
        case .some(..<7): return .orange
        default: return .red
        }
    }

    /// Higher-chroma/contrast severity steps for chart marks, where colour has to survive at 6–10pt sizes.
    /// nil (patient hasn't rated it yet) → neutral gray, matching `severity(_:)`.
    static func chartSeverity(_ value: Int?) -> Color {
        switch value {
        case nil: Color(.systemGray)
        case .some(..<4): Color(red: 0.00, green: 0.42, blue: 0.55)
        case .some(..<7): Color(red: 0.80, green: 0.36, blue: 0.00)
        default: Color(red: 0.80, green: 0.10, blue: 0.10)
        }
    }

    static func strength(_ strength: Correlation.Strength) -> Color {
        switch strength {
        case .strong: chartSeverity(1)
        case .moderate: chartSeverity(5)
        case .weak, .insufficient: Color(.systemGray)
        }
    }
}

extension Font {
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded).weight(weight)
    }
}

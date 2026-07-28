import SwiftUI

/// Semantic color tokens for the app. The app renders in light appearance only
/// (`UIUserInterfaceStyle = Light` in `Config/Rentivo-Info.plist`), so each token is a
/// single fixed sRGB value. Accent hues (`emerald`, `amber`, `coral`, `blue`, `lilac`) are
/// tuned so that, used as-is, they meet WCAG AA (>=4.5:1) as foreground text/icon color
/// against both `paper` and `surface`, AND against their own 14%-opacity tint (the pattern
/// `StatusBadge` uses).
enum RentivoColors {
  static let paper = Color(red: 0.97, green: 0.95, blue: 0.90)
  static let surface = Color(red: 1.00, green: 0.99, blue: 0.96)
  static let ink = Color(red: 0.12, green: 0.12, blue: 0.18)
  static let secondaryInk = Color(red: 0.34, green: 0.34, blue: 0.40)

  static let emerald = Color(red: 0.026, green: 0.456, blue: 0.318)
  static let emeraldLight = Color(red: 0.87, green: 0.96, blue: 0.93)
  static let amber = Color(red: 0.539, green: 0.36, blue: 0.093)
  static let coral = Color(red: 0.681, green: 0.254, blue: 0.205)
  static let blue = Color(red: 0.16, green: 0.395, blue: 0.714)
  static let lilac = Color(red: 0.446, green: 0.346, blue: 0.655)
}

enum RentivoSpacing {
  static let tiny: CGFloat = 4
  static let small: CGFloat = 8
  static let medium: CGFloat = 12
  static let large: CGFloat = 20
  static let page: CGFloat = 24
  static let section: CGFloat = 32
}

enum RentivoTypography {
  static let display = Font.system(.largeTitle, design: .rounded, weight: .black)
  static let title = Font.system(.title2, design: .rounded, weight: .bold)
  static let cardTitle = Font.system(.headline, design: .rounded, weight: .bold)
  static let metadata = Font.system(.caption, design: .rounded, weight: .semibold)
  static let money = Font.system(.title3, design: .monospaced, weight: .bold)
}

extension View {
  func rentivoPage() -> some View {
    frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(RentivoColors.paper)
  }
}

/// Formats a PT-BR count string with correct singular/plural noun agreement, e.g.
/// `ptBRCount(1, singular: "fatura", plural: "faturas")` -> "1 fatura" and
/// `ptBRCount(3, singular: "fatura", plural: "faturas")` -> "3 faturas".
func ptBRCount(_ count: Int, singular: String, plural: String) -> String {
  "\(count) \(count == 1 ? singular : plural)"
}

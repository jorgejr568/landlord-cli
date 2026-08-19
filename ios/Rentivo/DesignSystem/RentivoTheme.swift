import SwiftUI

/// Semantic color tokens for the app. The app renders in light appearance only
/// (`UIUserInterfaceStyle = Light` in `Config/Rentivo-Info.plist`), so each token is a
/// single fixed sRGB value. The cream/ink/emerald/amber/coral palette is tuned so that its
/// semantic foreground colors meet WCAG AA (>=4.5:1) against both `paper` and `surface`, and
/// against their own 14%-opacity tint (the pattern status and identity badges use).
enum RentivoColors {
  // Keep RentivoLaunchBackground.colorset at these exact sRGB values. The static launch screen
  // renders before SwiftUI can read this runtime token.
  static let paper = Color(red: 0.97, green: 0.95, blue: 0.90)
  static let surface = Color(red: 1.00, green: 0.99, blue: 0.96)
  static let ink = Color(red: 0.12, green: 0.12, blue: 0.18)
  static let secondaryInk = Color(red: 0.34, green: 0.34, blue: 0.40)

  static let emerald = Color(red: 0.026, green: 0.456, blue: 0.318)
  static let emeraldLight = Color(red: 0.87, green: 0.96, blue: 0.93)
  static let amber = Color(red: 0.539, green: 0.36, blue: 0.093)
  static let coral = Color(red: 0.681, green: 0.254, blue: 0.205)

  // Semantic aliases keep component intent independent from the underlying palette.
  static let primaryAction = emerald
  static let link = ink
  static let disabledControlFill = paper
  static let disabledControlForeground = secondaryInk
  static let error = coral
}

enum RentivoSemanticTone: Equatable, Sendable {
  case neutral
  case positive
  case warning
  case negative

  var color: Color {
    switch self {
    case .neutral: RentivoColors.ink
    case .positive: RentivoColors.emerald
    case .warning: RentivoColors.amber
    case .negative: RentivoColors.coral
    }
  }
}

enum AppChromeSemanticPresentation {
  static let informationTone = RentivoSemanticTone.neutral
  static let currentUserIdentityTone = RentivoSemanticTone.neutral
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
  static let code = Font.system(.title2, design: .monospaced, weight: .bold)
}

extension View {
  func rentivoPage() -> some View {
    frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(RentivoColors.paper)
  }

  /// The native container contributes the real tab-bar safe area. Add only the product's
  /// breathing room so this remains correct across devices, orientations, text sizes, and OSes.
  func rentivoTabContent() -> some View {
    contentMargins(.bottom, RentivoSpacing.large, for: .scrollContent)
  }

  func rentivoTabBarAppearance() -> some View {
    toolbarBackground(RentivoColors.surface, for: .tabBar)
      .toolbarBackground(.visible, for: .tabBar)
  }

  func noticeArea(_ area: NoticeArea) -> some View {
    modifier(NoticeAreaModifier(area: area))
  }
}

private struct NoticeAreaModifier: ViewModifier {
  @Environment(AppModel.self) private var app
  let area: NoticeArea

  func body(content: Content) -> some View {
    content.onAppear { app.activateNoticeArea(area) }
  }
}

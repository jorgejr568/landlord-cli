import SwiftUI

/// Semantic color tokens for the app. The app renders in light appearance only
/// (`RentivoMacApp` forces `.preferredColorScheme(.light)` on its window, mirroring the iOS
/// app's `UIUserInterfaceStyle = Light`), so each token is a single fixed sRGB value. Accent
/// hues (`emerald`, `amber`, `coral`, `blue`, `lilac`) are tuned so that, used as-is, they meet
/// WCAG AA (>=4.5:1) as foreground text/icon color against both `paper` and `surface`, AND
/// against their own 14%-opacity tint (the pattern `StatusBadge` uses).
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

/// Desktop type scale.
///
/// The sizes are explicit rather than derived from `Font.TextStyle` on purpose. macOS resolves
/// the system text styles several points smaller than iOS does — `.body` is 13pt against iOS's
/// 17, `.caption` 10 against 12, `.largeTitle` 26 against 34 — so the iOS scale this app was
/// ported from lands unreadably small on a desktop display viewed at arm's length. Scaling the
/// text styles back up through `.dynamicTypeSize` is not an option either: applying it anywhere
/// above this app's content stops SwiftUI rendering the window contents at all on the macOS 14
/// SDK, verified by window capture.
///
/// Every screen draws from these tokens, so the hierarchy holds across features:
/// `display` > `title` > `cardTitle` > `body` > `caption`/`metadata`.
enum RentivoTypography {
  /// Screen-level greeting and the wordmark — one per screen at most.
  static let display = Font.system(size: 36, weight: .black, design: .rounded)
  /// Section headings and sheet titles.
  static let title = Font.system(size: 21, weight: .bold, design: .rounded)
  /// Card titles and list-row titles.
  static let cardTitle = Font.system(size: 17, weight: .bold, design: .rounded)
  /// Default running text. Also the app-wide default, applied once at the root.
  static let body = Font.system(size: 15, weight: .regular)
  /// Running text carrying emphasis: field labels, row leads.
  static let bodyStrong = Font.system(size: 15, weight: .semibold)
  /// Supporting text under a title.
  static let caption = Font.system(size: 13, weight: .regular)
  /// Supporting text carrying emphasis.
  static let captionStrong = Font.system(size: 13, weight: .semibold)
  /// Small rounded labels: status badges, pills, stat-card captions.
  static let metadata = Font.system(size: 13, weight: .semibold, design: .rounded)
  /// Primary monetary figures.
  static let money = Font.system(size: 21, weight: .bold, design: .monospaced)
  /// Monetary figures in the compact summary cards, which sit four to a row.
  static let moneyCompact = Font.system(size: 17, weight: .bold, design: .monospaced)
  /// Machine-readable strings: keys, hex colours, recovery codes.
  static let mono = Font.system(size: 14, weight: .regular, design: .monospaced)
  static let monoStrong = Font.system(size: 16, weight: .bold, design: .monospaced)
  static let monoSmall = Font.system(size: 13, weight: .regular, design: .monospaced)
  /// Labels inside `RentivoButtonStyle`.
  static let button = Font.system(size: 16, weight: .bold, design: .rounded)
  /// Glyph size for the symbol that heads a card.
  static let icon = Font.system(size: 22, weight: .semibold)
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

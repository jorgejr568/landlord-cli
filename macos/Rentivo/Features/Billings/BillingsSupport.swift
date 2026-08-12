import SwiftUI

/// Section heading shared by the Cobranças and Faturas screens.
///
/// iOS spells this as `SectionTitle`, declared in `HomeView.swift` and reused across features. On
/// macOS the Início port owns that name, so this feature-scoped twin renders identically without
/// colliding with it. Both should collapse into one design-system declaration once the macOS port
/// is complete.
struct BillingSectionTitle: View {
  let title: String
  let symbol: String

  var body: some View {
    Label(title, systemImage: symbol)
      .font(RentivoTypography.title)
      .foregroundStyle(RentivoColors.ink)
  }
}

/// Places `leading` beside `trailing` when the window is wide enough for both, and stacks them
/// otherwise.
///
/// iPhone screens have one usable column, so the iOS detail screens stack every section. A macOS
/// window is freely resizable and usually far wider, so the layout is chosen from the width
/// actually offered rather than from a size class: the side-by-side branch declares `breakpoint`
/// as its minimum width, which is exactly the condition `ViewThatFits` rejects it on.
struct BillingAdaptiveColumns<Leading: View, Trailing: View>: View {
  var breakpoint: CGFloat = 880
  var spacing: CGFloat = RentivoSpacing.section
  @ViewBuilder var leading: () -> Leading
  @ViewBuilder var trailing: () -> Trailing

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: spacing) {
        VStack(alignment: .leading, spacing: RentivoSpacing.section) { leading() }
          .frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .leading, spacing: RentivoSpacing.section) { trailing() }
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(minWidth: breakpoint)

      VStack(alignment: .leading, spacing: spacing) {
        leading()
        trailing()
      }
    }
  }
}

/// Motion shared by the Cobranças and Faturas screens. Both values are deliberately short: they
/// exist to make a load or a hover feel connected to the action that caused it, not to be noticed.
enum BillingsMotion {
  /// Applied around the state assignment that publishes freshly loaded content, so rows settle in
  /// instead of popping into place.
  static let load: Animation = .spring(response: 0.34, dampingFraction: 0.86)

  /// Paired with `load` on individual rows. Computed rather than stored: `AnyTransition` is not
  /// `Sendable`, so a stored static would be shared mutable state under strict concurrency.
  static var row: AnyTransition { .opacity.combined(with: .offset(y: 8)) }
}

/// Pointer-hover affordance for a card that acts as a row in a list. A macOS list has no touch
/// feedback, so the row has to answer the pointer to read as clickable at all.
private struct BillingRowHover: ViewModifier {
  @State private var isHovering = false

  func body(content: Content) -> some View {
    content
      .scaleEffect(isHovering ? 1.01 : 1)
      .shadow(color: RentivoColors.emerald.opacity(isHovering ? 0.35 : 0), radius: 10, x: 0, y: 4)
      .animation(.easeOut(duration: 0.12), value: isHovering)
      .onHover { isHovering = $0 }
  }
}

extension View {
  func billingRowHover() -> some View {
    modifier(BillingRowHover())
  }

  /// Explicit sizing every sheet in this feature adopts. macOS sheets have no natural size of
  /// their own: without this a `Form` sheet opens as a narrow sliver of its content.
  func billingSheetFrame() -> some View {
    frame(minWidth: 640, idealWidth: 720, minHeight: 520)
  }
}

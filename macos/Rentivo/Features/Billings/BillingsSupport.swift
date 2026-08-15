import SwiftUI

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

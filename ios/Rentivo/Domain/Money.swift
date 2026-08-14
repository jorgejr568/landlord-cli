import Foundation

public struct Money: Hashable, Codable, Sendable, Comparable {
  public let centavos: Int

  public init(centavos: Int) {
    self.centavos = centavos
  }

  public static let zero = Money(centavos: 0)

  public static func + (lhs: Money, rhs: Money) -> Money {
    Money(centavos: lhs.centavos + rhs.centavos)
  }

  public static func - (lhs: Money, rhs: Money) -> Money {
    Money(centavos: lhs.centavos - rhs.centavos)
  }

  public static func < (lhs: Money, rhs: Money) -> Bool {
    lhs.centavos < rhs.centavos
  }

  private static let brazilianLocale = Locale(identifier: "pt_BR")

  /// Presentation for the default pt-BR/BRL path, shared by every rendered amount.
  /// `Decimal.FormatStyle.Currency` is a `Sendable` value type, so it can be held as
  /// static state on this `Sendable` struct — a `NumberFormatter` (a class) could not,
  /// which is why this used to build one per call, during SwiftUI body evaluation for
  /// every amount on screen. The formatted output is unchanged, including the
  /// non-breaking space after "R$".
  private static let brazilianStyle = Decimal.FormatStyle.Currency(
    code: "BRL", locale: Money.brazilianLocale)

  public func formatted(locale: Locale = Locale(identifier: "pt_BR")) -> String {
    let amount = Decimal(centavos) / 100
    // Locales other than the pt-BR default are rare, so they build a style per call
    // rather than growing a cache keyed by locale.
    guard locale == Money.brazilianLocale else {
      return amount.formatted(Decimal.FormatStyle.Currency(code: "BRL", locale: locale))
    }
    return amount.formatted(Money.brazilianStyle)
  }
}

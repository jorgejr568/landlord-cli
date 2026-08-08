import Foundation

// Parsing for the date and timestamp shapes the server puts on the wire, shared by every
// `APIRentivoStore` decoder. The formatters keep the `APIRentivoStore` main-actor isolation they
// had as static members of that class, which is also what makes these shared instances safe.
@MainActor
enum WireDate {
  // A present but malformed date string surfaces as a decode error via `DateOnly`'s failable
  // wire initializer instead of reaching the precondition-enforcing
  // `DateOnly.init(year:month:day:)` and trapping the process on out-of-range components.
  static func dateOnly(_ value: String) throws -> DateOnly {
    guard let parsed = DateOnly(iso8601String: value) else { throw LiveAPIError.invalidResponse }
    return parsed
  }

  // `due_date` is nullable on the wire. A `null` means the bill genuinely has no due date yet,
  // so it stays `nil` rather than collapsing to an epoch sentinel that would surface in the UI
  // as "Vence 01/01/1970".
  static func optionalDateOnly(_ value: String?) throws -> DateOnly? {
    guard let value else { return nil }
    return try dateOnly(value)
  }

  // The backend emits fractional-second timestamps (microseconds); try that format first and
  // fall back to the plain internet-date-time form. A total parse failure surfaces as a decode
  // error instead of silently defaulting to `.distantPast`.
  private static let isoDateTimeFormatterWithFraction: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
  private static let isoDateTimeFormatter = ISO8601DateFormatter()

  // Timestamps read straight out of a naive `DATETIME` column reach us without a timezone
  // designator (e.g. `2026-07-28T13:28:55`). `.withInternetDateTime` requires one, so both
  // formatters above reject those outright and a display-only date takes down the whole
  // screen. They are São Paulo wall clock on the wire, so parse them in that zone.
  //
  // These are strictly a fallback: lacking `.withTimeZone`, they happily parse an
  // offset-bearing string while *ignoring* its offset, which would silently shift a `Z`
  // timestamp. `isoDate` therefore only reaches them once the strict formatters have failed.
  private static func localDateTimeFormatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    var options: ISO8601DateFormatter.Options = [.withFullDate, .withTime, .withColonSeparatorInTime]
    if fractionalSeconds { options.insert(.withFractionalSeconds) }
    formatter.formatOptions = options
    formatter.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current
    return formatter
  }
  private static let localDateTimeFormatterWithFraction = localDateTimeFormatter(fractionalSeconds: true)
  private static let localDateTimeFormatterWithoutFraction = localDateTimeFormatter(fractionalSeconds: false)

  static func isoDate(_ value: String) throws -> Date {
    if let date = Self.isoDateTimeFormatterWithFraction.date(from: value) { return date }
    if let date = Self.isoDateTimeFormatter.date(from: value) { return date }
    if let date = Self.localDateTimeFormatterWithFraction.date(from: value) { return date }
    if let date = Self.localDateTimeFormatterWithoutFraction.date(from: value) { return date }
    throw LiveAPIError.invalidResponse
  }
}

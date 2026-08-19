import Foundation

/// Deterministic Brazilian Portuguese presentation for customer-facing values.
public enum BrazilianLocaleFormatting {
  public static let locale = Locale(identifier: "pt_BR")

  public static func integer(_ value: Int) -> String {
    value.formatted(.number.locale(locale).grouping(.automatic))
  }

  /// Calendar years are identifiers rather than quantities, so grouping is never appropriate.
  public static func year(_ value: Int) -> String {
    String(value)
  }

  public static func calendarDate(_ date: DateOnly) -> String {
    String(format: "%02d/%02d/%04d", date.day, date.month, date.year)
  }

  public static func monthName(_ month: Int, standalone: Bool = false) -> String {
    precondition((1...12).contains(month), "Month must be between 1 and 12")
    let names = [
      "janeiro", "fevereiro", "março", "abril", "maio", "junho",
      "julho", "agosto", "setembro", "outubro", "novembro", "dezembro",
    ]
    let name = names[month - 1]
    guard standalone, let first = name.first else { return name }
    return String(first).uppercased(with: locale) + name.dropFirst()
  }

  public static func referenceMonth(_ value: ReferenceMonth) -> String {
    "\(monthName(value.month)) de \(year(value.year))"
  }

  public static func standaloneReferenceMonth(_ value: ReferenceMonth) -> String {
    "\(monthName(value.month, standalone: true)) de \(year(value.year))"
  }

  public static func documentReferenceMonth(_ value: ReferenceMonth) -> String {
    "\(monthName(value.month)) \(year(value.year))"
  }

  public static func fileSize(_ byteCount: Int) -> String {
    Int64(max(0, byteCount)).formatted(
      .byteCount(style: .file, allowedUnits: .all, spellsOutZero: false)
        .locale(locale)
    )
  }

  public static func date(
    _ value: Date,
    date dateStyle: Date.FormatStyle.DateStyle = .abbreviated,
    time timeStyle: Date.FormatStyle.TimeStyle = .omitted,
    timeZone: TimeZone = .current
  ) -> String {
    value.formatted(
      Date.FormatStyle(
        date: dateStyle,
        time: timeStyle,
        locale: locale,
        calendar: Calendar(identifier: .gregorian),
        timeZone: timeZone
      )
    )
  }
}

/// Formats a PT-BR count with Brazilian grouping and singular only for exactly one.
public func ptBRCount(_ count: Int, singular: String, plural: String) -> String {
  "\(BrazilianLocaleFormatting.integer(count)) \(count == 1 ? singular : plural)"
}

extension Date {
  /// Retains the existing shared call surface while pinning locale and allowing deterministic tests.
  public func formattedPTBR(
    date dateStyle: Date.FormatStyle.DateStyle = .abbreviated,
    time timeStyle: Date.FormatStyle.TimeStyle = .omitted,
    timeZone: TimeZone = .current
  ) -> String {
    BrazilianLocaleFormatting.date(
      self, date: dateStyle, time: timeStyle, timeZone: timeZone)
  }
}

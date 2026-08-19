import Foundation

public enum LoadState<Value: Sendable>: Sendable {
  case idle
  case loading
  case loaded(Value)
  case empty
  case failed(DemoError)

  public var value: Value? {
    guard case .loaded(let value) = self else { return nil }
    return value
  }
}

public struct DemoError: Error, Equatable, LocalizedError, Sendable {
  public let message: String

  public init(message: String) {
    self.message = message
  }

  public init(_ error: any Error) {
    if let demoError = error as? DemoError {
      self = demoError
    } else if let localizedError = error as? LocalizedError,
      let message = localizedError.errorDescription
    {
      self.init(message: message)
    } else {
      self.init(message: "Não foi possível concluir esta ação. Tente novamente.")
    }
  }

  public var errorDescription: String? { message }

  public static let operationFailed = DemoError(
    message: "Não foi possível concluir esta ação de demonstração."
  )
  public static let invalidBillTransition = DemoError(
    message: "Esta mudança de status não é permitida."
  )
  public static let staleBillStatus = DemoError(
    message: "O status da fatura foi alterado. Atualize a página e tente novamente."
  )
  public static let resourceNotFound = DemoError(
    message: "O item solicitado não foi encontrado."
  )
  public static let permissionDenied = DemoError(
    message: "Seu perfil de demonstração não permite esta ação."
  )
  public static let invalidAmount = DemoError(
    message: "O valor informado deve ser maior que zero."
  )
  public static let invalidDescription = DemoError(
    message: "Informe uma descrição com no máximo 2000 caracteres."
  )
}

public enum StableID {
  public static let userAna = 1
  public static let organizationHorizonte = OrganizationID(rawValue: "00000000-0000-0000-0000-000000000010")
  public static let billingAurora101 = BillingID(rawValue: "00000000-0000-0000-0000-000000000101")
  public static let billingAurora202 = BillingID(rawValue: "00000000-0000-0000-0000-000000000102")
  public static let billingSolNascente303 = BillingID(rawValue: "00000000-0000-0000-0000-000000000103")
  public static let billingVilaFlores1 = BillingID(rawValue: "00000000-0000-0000-0000-000000000104")
  public static let billingTorreNorte501 = BillingID(rawValue: "00000000-0000-0000-0000-000000000105")
  public static let billingCentro12 = BillingID(rawValue: "00000000-0000-0000-0000-000000000106")
  public static let billDraft = BillID(rawValue: "00000000-0000-0000-0000-000000001001")
  public static let billPublished = BillID(rawValue: "00000000-0000-0000-0000-000000001002")
  public static let billSent = BillID(rawValue: "00000000-0000-0000-0000-000000001003")
  public static let billPaid = BillID(rawValue: "00000000-0000-0000-0000-000000001004")
  public static let billCancelled = BillID(rawValue: "00000000-0000-0000-0000-000000001005")
  public static let billDelayed = BillID(rawValue: "00000000-0000-0000-0000-000000001006")
  public static let invitationHorizonte = InvitationID(rawValue: "00000000-0000-0000-0000-000000003001")
  public static let apiKeyDashboard = APIKeyID(rawValue: "00000000-0000-0000-0000-000000004001")
}

public struct DateOnly: Hashable, Codable, Sendable, Comparable {
  public let year: Int
  public let month: Int
  public let day: Int

  public init(year: Int, month: Int, day: Int) {
    precondition((1...12).contains(month), "Month must be between 1 and 12")
    precondition((1...31).contains(day), "Day must be between 1 and 31")
    self.year = year
    self.month = month
    self.day = day
  }

  /// Failable parsing initializer intended for the wire boundary: malformed
  /// server data (or user input) returns `nil` instead of trapping.
  public init?(iso8601String: String) {
    let parts = iso8601String.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3,
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      let day = Int(parts[2]),
      (1...12).contains(month),
      (1...31).contains(day)
    else { return nil }
    self.year = year
    self.month = month
    self.day = day
  }

  public var iso8601: String {
    String(format: "%04d-%02d-%02d", year, month, day)
  }

  /// PT-BR display representation, e.g. "10/08/2026". The dd/MM/yyyy
  /// ordering is the Brazilian convention regardless of the device's current
  /// locale, so this is built directly from the stored components rather
  /// than through a cached `DateFormatter` (a non-`Sendable` class that would
  /// be unsafe to share as static state on a `Sendable` type).
  public var displayFormatted: String {
    String(format: "%02d/%02d/%04d", day, month, year)
  }

  public static func < (lhs: DateOnly, rhs: DateOnly) -> Bool {
    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
  }
}

public struct ReferenceMonth: Hashable, Codable, Sendable, Comparable {
  public let year: Int
  public let month: Int

  public init(year: Int, month: Int) {
    precondition((1...12).contains(month), "Month must be between 1 and 12")
    self.year = year
    self.month = month
  }

  /// Failable parsing initializer intended for the wire boundary: malformed
  /// server data returns `nil` instead of trapping.
  public init?(apiValue: String) {
    let parts = apiValue.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 2,
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      (1...12).contains(month)
    else { return nil }
    self.year = year
    self.month = month
  }

  public var apiValue: String {
    String(format: "%04d-%02d", year, month)
  }

  public var label: String {
    let monthNames = [
      "janeiro", "fevereiro", "março", "abril", "maio", "junho",
      "julho", "agosto", "setembro", "outubro", "novembro", "dezembro",
    ]
    return "\(monthNames[month - 1]) de \(year)"
  }

  /// PT-BR display representation, e.g. "agosto de 2026".
  public var displayFormatted: String { label }

  public static func < (lhs: ReferenceMonth, rhs: ReferenceMonth) -> Bool {
    (lhs.year, lhs.month) < (rhs.year, rhs.month)
  }
}

extension DateOnly {
  /// Bridges a SwiftUI `DatePicker` selection into the calendar-agnostic domain
  /// representation. Components extracted from a real `Date` are always in range, so this
  /// cannot trip `init(year:month:day:)`'s preconditions.
  public init(from date: Date, calendar: Calendar = .current) {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    self.init(
      year: components.year ?? 1970,
      month: components.month ?? 1,
      day: components.day ?? 1
    )
  }

  /// The reverse bridge, for seeding a `DatePicker`. `init(iso8601String:)` only range-checks
  /// the day as 1...31 without consulting the month's length, so a wire value like "2026-02-31"
  /// can reach here; `Calendar` normalizes such components rather than rejecting them, and the
  /// epoch is a defensive fallback for the `Optional` it nonetheless returns.
  public func resolvedDate(in calendar: Calendar = .current) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))
      ?? Date(timeIntervalSince1970: 0)
  }
}

extension ReferenceMonth {
  /// The due date a new bill starts from: day 10 of the month *after* the reference month.
  /// The reference month says which period the bill covers; the due date says when the money
  /// is owed, and in practice that lands in the following month.
  public var defaultDueDate: DateOnly {
    let rollsOver = month == 12
    return DateOnly(
      year: rollsOver ? year + 1 : year,
      month: rollsOver ? 1 : month + 1,
      day: 10
    )
  }
}

public struct UserProfile: Hashable, Codable, Sendable {
  public let id: Int
  public var email: String
  public var pix: PixConfiguration?

  public init(id: Int, email: String, pix: PixConfiguration? = nil) {
    self.id = id
    self.email = email
    self.pix = pix
  }
}

public struct ProfilePIXForm: Equatable, Sendable {
  public var keyType: PixKeyType
  public var key: String
  public var merchantName: String
  public var merchantCity: String
  public var preservesUnclassifiedLegacyKey: Bool

  public init(profile: UserProfile? = nil) {
    let keyInput = PixKeyInput(persistedKey: profile?.pix?.key ?? "")
    keyType = keyInput.type
    key = keyInput.value
    merchantName = profile?.pix?.merchantName ?? ""
    merchantCity = profile?.pix?.merchantCity ?? ""
    preservesUnclassifiedLegacyKey = keyInput.preservesUnclassifiedLegacyValue
  }

  public var validationResult: PixFormResult {
    PixFormRules.result(
      type: keyType,
      key: key,
      merchantName: merchantName,
      merchantCity: merchantCity,
      preservesUnclassifiedLegacyValue: preservesUnclassifiedLegacyKey
    )
  }

  public var configuration: PixConfiguration? {
    if case .custom(let configuration) = validationResult { return configuration }
    return nil
  }

  public var validationMessage: String? {
    if case .invalid(let message) = validationResult { return message }
    return nil
  }

  public var isSavable: Bool {
    configuration != nil
  }
}

public enum ActivityKind: String, Codable, Sendable {
  case billing
  case bill
  case expense
  case organization
  case invitation
  case security
  case apiKey = "api_key"
  case theme
}

public struct RecentActivity: Identifiable, Hashable, Codable, Sendable {
  public let id: UUID
  public let kind: ActivityKind
  public let title: String
  public let detail: String
  public let occurredAt: Date

  public init(id: UUID, kind: ActivityKind, title: String, detail: String, occurredAt: Date) {
    self.id = id
    self.kind = kind
    self.title = title
    self.detail = detail
    self.occurredAt = occurredAt
  }
}

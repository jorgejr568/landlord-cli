import Foundation

public enum PixFormResult: Hashable, Sendable {
  case inherit
  case custom(PixConfiguration)
  case invalid(String)
}

public enum PixFormRules {
  public static func result(
    key: String, merchantName: String, merchantCity: String
  ) -> PixFormResult {
    let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    let city = merchantCity.trimmingCharacters(in: .whitespacesAndNewlines)
    if key.isEmpty, name.isEmpty, city.isEmpty { return .inherit }
    guard !key.isEmpty, !name.isEmpty, !city.isEmpty else {
      return .invalid(
        "Preencha a chave, o nome e a cidade do recebedor para usar PIX personalizado."
      )
    }
    guard name.unicodeScalars.count <= 25, city.unicodeScalars.count <= 15 else {
      return .invalid("O nome deve ter até 25 caracteres e a cidade até 15 caracteres.")
    }
    return .custom(PixConfiguration(key: key, merchantName: name, merchantCity: city))
  }
}

public enum CommunicationFormRules {
  public static let maximumBodyByteCount = 4_096
  public static let maximumSubjectCount = 998

  public static func issues(subject: String, body: String) -> [ValidationIssue] {
    var issues: [ValidationIssue] = []
    if subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(ValidationIssue(field: .subject, message: "Informe o assunto."))
    } else if subject.unicodeScalars.count > maximumSubjectCount {
      issues.append(
        ValidationIssue(field: .subject, message: "O assunto deve ter no máximo 998 caracteres.")
      )
    }
    if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(ValidationIssue(field: .body, message: "Informe a mensagem."))
    } else if body.lengthOfBytes(using: .utf8) > maximumBodyByteCount {
      issues.append(
        ValidationIssue(field: .body, message: "A mensagem deve ter no máximo 4096 bytes.")
      )
    }
    return issues
  }
}

public enum NativeFormTextLimits {
  public static let name = 255
  public static let description = 2_000
  public static let itemDescription = 255
  public static let email = 320
}

public enum MoneyInputRules {
  /// Both native clients store centavos in a 32-bit-compatible wire value. Capping significant
  /// values keeps pasted overflow from being interpreted as zero by integer conversion while
  /// preserving the backend's full signed 32-bit positive range.
  public static let maximumCentavos = Money.maximumPersistedCentavos

  public static func centavos(from text: String) -> Int {
    let asciiDigits = text.filter { "0123456789".contains($0) }
    let significant = asciiDigits.drop { $0 == "0" }
    guard !significant.isEmpty else { return 0 }
    guard significant.count <= 10, let value = Int(significant) else { return maximumCentavos }
    return min(value, maximumCentavos)
  }
}

/// Authentication accepts the backend's deliberately permissive credential address contract.
/// Billing contacts use the stricter `EmailAddress` validator instead.
public enum AuthEmailAddress {
  public static func isValid(_ email: String) -> Bool {
    let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard value.filter({ $0 == "@" }).count == 1, !value.contains(where: \.isWhitespace) else {
      return false
    }
    let parts = value.split(separator: "@", omittingEmptySubsequences: false)
    return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
  }
}

public enum BcryptPasswordRules {
  public static let maximumByteCount = 72

  public static func isAccepted(_ password: String) -> Bool {
    !password.isEmpty && password.lengthOfBytes(using: .utf8) <= maximumByteCount
  }

  public static var limitMessage: String {
    "A senha deve ter no máximo 72 bytes."
  }
}

public struct NativeOrganizationDraftState: Equatable, Sendable {
  public let name: String
  public let pixKey: String
  public let merchantName: String
  public let city: String
  public let usesCustomPix: Bool

  public init(
    name: String, pixKey: String, merchantName: String, city: String,
    usesCustomPix: Bool
  ) {
    self.name = name
    self.pixKey = pixKey
    self.merchantName = merchantName
    self.city = city
    self.usesCustomPix = usesCustomPix
  }

  public func hasChanges(from original: Self) -> Bool { self != original }
}

public struct NativeAPIKeyDraftState: Equatable, Sendable {
  public let name: String
  public let scopes: Set<APIKeyScope>
  public let resourceIDs: Set<WorkspaceID>

  public init(name: String, scopes: Set<APIKeyScope>, resourceIDs: Set<WorkspaceID>) {
    self.name = name
    self.scopes = scopes
    self.resourceIDs = resourceIDs
  }

  public func hasChanges(from original: Self, expirationEdited: Bool) -> Bool {
    expirationEdited || self != original
  }
}

public struct NativeCommunicationDraftState: Equatable, Sendable {
  public let commType: CommunicationType
  public let selectedRecipients: Set<RecipientID>
  public let subject: String
  public let message: String
  public let saveScope: CommunicationSaveScope?

  public init(
    commType: CommunicationType, selectedRecipients: Set<RecipientID>, subject: String,
    message: String, saveScope: CommunicationSaveScope?
  ) {
    self.commType = commType
    self.selectedRecipients = selectedRecipients
    self.subject = subject
    self.message = message
    self.saveScope = saveScope
  }

  public func hasChanges(from original: Self) -> Bool { self != original }
}

public enum ThemeFormRules {
  public static func isHexColor(_ value: String) -> Bool {
    guard value.count == 7, value.first == "#" else { return false }
    return value.dropFirst().unicodeScalars.allSatisfy {
      CharacterSet(charactersIn: "0123456789ABCDEFabcdef").contains($0)
    }
  }

  public static func invalidColorNames(in values: ThemeValues) -> [String] {
    [
      ("Primária", values.primary), ("Primária clara", values.primaryLight),
      ("Secundária", values.secondary), ("Secundária escura", values.secondaryDark),
      ("Texto", values.textColor), ("Texto de contraste", values.textContrast),
    ].compactMap { isHexColor($0.1) ? nil : $0.0 }
  }

  public static func contrastWarnings(for values: ThemeValues) -> [String] {
    guard invalidColorNames(in: values).isEmpty else { return [] }
    var warnings: [String] = []
    if contrastRatio(values.textContrast, values.primary) < 4.5 {
      warnings.append("O texto de contraste pode ficar difícil de ler sobre a cor primária.")
    }
    if contrastRatio(values.textColor, values.primaryLight) < 4.5 {
      warnings.append("O texto pode ficar difícil de ler sobre a cor primária clara.")
    }
    return warnings
  }

  private static func contrastRatio(_ foreground: String, _ background: String) -> Double {
    let first = luminance(foreground)
    let second = luminance(background)
    return (max(first, second) + 0.05) / (min(first, second) + 0.05)
  }

  private static func luminance(_ value: String) -> Double {
    let raw = UInt64(value.dropFirst(), radix: 16) ?? 0
    let channels = [raw >> 16, (raw >> 8) & 0xFF, raw & 0xFF].map { channel -> Double in
      let normalized = Double(channel) / 255
      return normalized <= 0.03928
        ? normalized / 12.92 : pow((normalized + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
  }
}

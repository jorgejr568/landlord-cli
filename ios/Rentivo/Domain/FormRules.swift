import Foundation

public enum PixKeyType: String, CaseIterable, Codable, Hashable, Sendable {
  case cpf
  case cnpj
  case email
  case phone
  case random

  public var label: String {
    switch self {
    case .cpf: "CPF"
    case .cnpj: "CNPJ"
    case .email: "E-mail"
    case .phone: "Telefone"
    case .random: "Aleatória"
    }
  }

  public var hint: String? {
    switch self {
    case .cpf: "Digite os 11 dígitos do CPF."
    case .cnpj: "Digite os 14 dígitos do CNPJ."
    case .email: nil
    case .phone: "Informe DDD e número. O +55 será adicionado ao salvar."
    case .random: "Cole a chave aleatória no formato UUID."
    }
  }

  public var invalidMessage: String {
    switch self {
    case .cpf: "Informe um CPF com 11 dígitos."
    case .cnpj: "Informe um CNPJ com 14 dígitos."
    case .email: "Informe um e-mail válido."
    case .phone: "Informe um telefone com DDD."
    case .random: "Informe uma chave aleatória válida no formato UUID."
    }
  }
}

public struct PixKeyInput: Equatable, Hashable, Sendable {
  public var type: PixKeyType
  public var value: String
  public var preservesUnclassifiedLegacyValue: Bool

  public init(
    type: PixKeyType = .cpf,
    value: String = "",
    preservesUnclassifiedLegacyValue: Bool = false
  ) {
    self.type = type
    self.value = value
    self.preservesUnclassifiedLegacyValue = preservesUnclassifiedLegacyValue
  }

  public init(persistedKey: String) {
    if let inferredType = Self.inferType(from: persistedKey) {
      type = inferredType
      value = Self.formatted(persistedKey, as: inferredType)
      preservesUnclassifiedLegacyValue = false
    } else {
      type = .random
      value = persistedKey
      preservesUnclassifiedLegacyValue = !persistedKey.isEmpty
    }
  }

  public var formattedValue: String { Self.formatted(value, as: type) }

  public var normalizedValue: String? {
    guard !preservesUnclassifiedLegacyValue else { return nil }
    return Self.normalized(value, as: type)
  }

  public var validationMessage: String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "Informe a chave PIX." }
    if preservesUnclassifiedLegacyValue {
      return "Esta chave não corresponde ao tipo selecionado."
    }
    return normalizedValue == nil ? type.invalidMessage : nil
  }

  public var maskedValue: String {
    guard let normalizedValue else { return "••••" }
    switch type {
    case .cpf:
      return "***.***.***-\(normalizedValue.suffix(2))"
    case .cnpj:
      return "**.***.***/****-\(normalizedValue.suffix(2))"
    case .email:
      let parts = normalizedValue.split(separator: "@", maxSplits: 1).map(String.init)
      guard parts.count == 2 else { return "••••" }
      let local = parts[0]
      let visibleLocal: String
      if local.count <= 1 {
        visibleLocal = local
      } else {
        visibleLocal = "\(local.prefix(1))••••\(local.suffix(1))"
      }
      return "\(visibleLocal)@\(parts[1])"
    case .phone:
      let national = String(normalizedValue.dropFirst(3))
      let middle = national.count == 11 ? "*****" : "****"
      return "+55 (**) \(middle)-\(national.suffix(4))"
    case .random:
      return "••••\(normalizedValue.suffix(4))"
    }
  }

  public var hiddenAccessibilityValue: String {
    let suffix = normalizedValue.map { String($0.suffix(4)) }
      ?? String(value.suffix(4))
    return "Chave PIX oculta, final \(suffix)"
  }

  public func requiresConfirmation(to newType: PixKeyType) -> Bool {
    newType != type && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  public static func inferType(from persistedKey: String) -> PixKeyType? {
    let trimmed = persistedKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let digits = asciiDigits(in: trimmed)
    if digits.count == 11, digits == trimmed.filter({ $0.isNumber }) { return .cpf }
    if digits.count == 14, digits == trimmed.filter({ $0.isNumber }) { return .cnpj }
    if normalized(trimmed, as: .email) != nil { return .email }
    if trimmed.hasPrefix("+55"), normalized(trimmed, as: .phone) != nil { return .phone }
    if normalized(trimmed, as: .random) != nil { return .random }
    return nil
  }

  public static func formatted(_ input: String, as type: PixKeyType) -> String {
    switch type {
    case .cpf:
      return applyGroups(Array(asciiDigits(in: input).prefix(11)), groups: [3, 3, 3, 2], separators: [".", ".", "-"])
    case .cnpj:
      return applyGroups(Array(asciiDigits(in: input).prefix(14)), groups: [2, 3, 3, 4, 2], separators: [".", ".", "/", "-"])
    case .email:
      return input
    case .phone:
      var digits = asciiDigits(in: input)
      if (input.trimmingCharacters(in: .whitespaces).hasPrefix("+55") || digits.count > 11),
        digits.hasPrefix("55")
      {
        digits.removeFirst(2)
      }
      digits = String(digits.prefix(11))
      guard !digits.isEmpty else { return "" }
      let area = String(digits.prefix(2))
      let number = String(digits.dropFirst(2))
      guard digits.count > 2 else { return "+55 (\(area)" }
      if number.count <= 4 { return "+55 (\(area)) \(number)" }
      let split = number.count > 8 ? 5 : 4
      return "+55 (\(area)) \(number.prefix(split))-\(number.dropFirst(split))"
    case .random:
      let characters = input.lowercased().filter { character in
        character.isASCII && (character.isNumber || ("a"..."f").contains(character))
      }
      return applyGroups(Array(characters.prefix(32)), groups: [8, 4, 4, 4, 12], separators: ["-", "-", "-", "-"])
    }
  }

  public static func normalized(_ input: String, as type: PixKeyType) -> String? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    switch type {
    case .cpf:
      let digits = asciiDigits(in: trimmed)
      return digits.count == 11 ? digits : nil
    case .cnpj:
      let digits = asciiDigits(in: trimmed)
      return digits.count == 14 ? digits : nil
    case .email:
      let value = trimmed.lowercased()
      guard value.filter({ $0 == "@" }).count == 1,
        !value.contains(where: \.isWhitespace)
      else { return nil }
      let parts = value.split(separator: "@", omittingEmptySubsequences: false)
      guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
        parts[1].contains("."), !parts[1].hasPrefix("."), !parts[1].hasSuffix(".")
      else { return nil }
      return value
    case .phone:
      var digits = asciiDigits(in: trimmed)
      if digits.hasPrefix("55"), digits.count == 12 || digits.count == 13 {
        digits.removeFirst(2)
      }
      guard digits.count == 10 || digits.count == 11 else { return nil }
      return "+55\(digits)"
    case .random:
      let hex = trimmed.lowercased().filter { $0 != "-" }
      guard hex.count == 32, hex.allSatisfy({ character in
        character.isASCII && (character.isNumber || ("a"..."f").contains(character))
      }) else { return nil }
      return applyGroups(Array(hex), groups: [8, 4, 4, 4, 12], separators: ["-", "-", "-", "-"])
    }
  }

  private static func asciiDigits(in value: String) -> String {
    String(value.filter { character in character.isASCII && ("0"..."9").contains(character) })
  }

  private static func applyGroups(
    _ characters: [Character], groups: [Int], separators: [String]
  ) -> String {
    var result = ""
    var offset = 0
    for (index, groupLength) in groups.enumerated() where offset < characters.count {
      let end = min(offset + groupLength, characters.count)
      result += String(characters[offset..<end])
      offset = end
      if offset < characters.count, index < separators.count { result += separators[index] }
    }
    return result
  }
}

public enum PixFormResult: Hashable, Sendable {
  case inherit
  case custom(PixConfiguration)
  case invalid(String)
}

public enum PixFormRules {
  public static func result(
    type: PixKeyType,
    key: String,
    merchantName: String,
    merchantCity: String,
    preservesUnclassifiedLegacyValue: Bool = false
  ) -> PixFormResult {
    let input = PixKeyInput(
      type: type,
      value: key,
      preservesUnclassifiedLegacyValue: preservesUnclassifiedLegacyValue
    )
    let name = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    let city = merchantCity.trimmingCharacters(in: .whitespacesAndNewlines)
    if key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.isEmpty, city.isEmpty {
      return .inherit
    }
    if let message = input.validationMessage { return .invalid(message) }
    guard !name.isEmpty else { return .invalid("Informe o nome do recebedor.") }
    guard name.unicodeScalars.count <= 25 else {
      return .invalid("O nome do recebedor deve ter até 25 caracteres.")
    }
    guard !city.isEmpty else { return .invalid("Informe a cidade do recebedor.") }
    guard city.unicodeScalars.count <= 15 else {
      return .invalid("A cidade do recebedor deve ter até 15 caracteres.")
    }
    guard let normalizedKey = input.normalizedValue else {
      return .invalid("Esta chave não corresponde ao tipo selecionado.")
    }
    return .custom(
      PixConfiguration(key: normalizedKey, merchantName: name, merchantCity: city)
    )
  }

  public static func result(
    key: String, merchantName: String, merchantCity: String
  ) -> PixFormResult {
    let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    let city = merchantCity.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedKey.isEmpty, name.isEmpty, city.isEmpty { return .inherit }
    guard let type = PixKeyInput.inferType(from: trimmedKey) else {
      return .invalid("Esta chave não corresponde ao tipo selecionado.")
    }
    return result(type: type, key: trimmedKey, merchantName: name, merchantCity: city)
  }
}

public enum CommunicationFormRules {
  public static let maximumBodyCharacterCount = 4_096
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
    } else if body.count > maximumBodyCharacterCount {
      issues.append(
        ValidationIssue(field: .body, message: "A mensagem deve ter no máximo 4.096 caracteres.")
      )
    }
    if let token = CommunicationVariables.firstUnknownToken(in: subject) {
      issues.append(
        ValidationIssue(field: .subject, message: "Revise a variável não reconhecida: \(token).")
      )
    }
    if let token = CommunicationVariables.firstUnknownToken(in: body) {
      issues.append(
        ValidationIssue(field: .body, message: "Revise a variável não reconhecida: \(token).")
      )
    }
    return issues
  }
}

public enum CommunicationVariable: String, CaseIterable, Sendable {
  case tenantName = "nome_inquilino"
  case unit = "unidade"
  case referenceMonth = "mes"
  case dueDate = "vencimento"
  case total = "total"

  public var label: String {
    switch self {
    case .tenantName: "Nome do inquilino"
    case .unit: "Unidade"
    case .referenceMonth: "Mês de referência"
    case .dueDate: "Vencimento"
    case .total: "Valor total"
    }
  }

  public var token: String { "{{\(rawValue)}}" }
}

public enum CommunicationVariables {
  private static let tokenExpression = try! NSRegularExpression(
    pattern: #"\{\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}\}"#
  )

  public static func firstUnknownToken(in text: String) -> String? {
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    for match in tokenExpression.matches(in: text, range: range) {
      guard
        let identifierRange = Range(match.range(at: 1), in: text),
        CommunicationVariable(rawValue: String(text[identifierRange])) == nil,
        let tokenRange = Range(match.range(at: 0), in: text)
      else { continue }
      return String(text[tokenRange])
    }
    return nil
  }

  public static func replacingTokens(in text: String, values: [CommunicationVariable: String]) -> String {
    let mutable = NSMutableString(string: text)
    let range = NSRange(location: 0, length: mutable.length)
    for match in tokenExpression.matches(in: text, range: range).reversed() {
      guard
        let identifierRange = Range(match.range(at: 1), in: text),
        let variable = CommunicationVariable(rawValue: String(text[identifierRange])),
        let value = values[variable]
      else { continue }
      mutable.replaceCharacters(in: match.range(at: 0), with: value)
    }
    return mutable as String
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

public enum NativeAPIKeyWizardRules {
  public static let stepTitles = [
    "Identificação", "Escopos e validade", "Acessos", "Revisão",
  ]
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

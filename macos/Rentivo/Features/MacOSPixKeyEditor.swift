import Foundation
import RentivoCore

/// Editing state shared by the native macOS PIX forms.
///
/// Persisted free-text keys from older Rentivo versions remain untouched until the key field is
/// actually edited. From that first edit onward, the selected key type owns formatting,
/// normalization, and validation through `PixKeyInput`.
struct MacOSPixKeyEditor: Equatable {
  var keyType: PixKeyType
  private(set) var key: String
  private(set) var preservesUnclassifiedLegacyKey: Bool

  init(persistedKey: String = "") {
    let input = PixKeyInput(persistedKey: persistedKey)
    keyType = input.type
    key = input.value
    preservesUnclassifiedLegacyKey = input.preservesUnclassifiedLegacyValue
  }

  var input: PixKeyInput {
    PixKeyInput(
      type: keyType,
      value: key,
      preservesUnclassifiedLegacyValue: preservesUnclassifiedLegacyKey
    )
  }

  mutating func selectType(_ type: PixKeyType) {
    guard type != keyType else { return }
    keyType = type
    preservesUnclassifiedLegacyKey = false
  }

  mutating func updateKey(_ value: String) {
    key = PixKeyInput.formatted(value, as: keyType)
    preservesUnclassifiedLegacyKey = false
  }

  func result(merchantName: String, merchantCity: String) -> PixFormResult {
    guard preservesUnclassifiedLegacyKey else {
      return PixFormRules.result(
        type: keyType,
        key: key,
        merchantName: merchantName,
        merchantCity: merchantCity
      )
    }

    let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedName = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedCity = merchantCity.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedKey.isEmpty else { return .invalid("Informe a chave PIX.") }
    guard !normalizedName.isEmpty else { return .invalid("Informe o nome do recebedor.") }
    guard normalizedName.unicodeScalars.count <= 25 else {
      return .invalid("O nome do recebedor deve ter até 25 caracteres.")
    }
    guard !normalizedCity.isEmpty else { return .invalid("Informe a cidade do recebedor.") }
    guard normalizedCity.unicodeScalars.count <= 15 else {
      return .invalid("A cidade do recebedor deve ter até 15 caracteres.")
    }
    return .custom(
      PixConfiguration(
        key: normalizedKey,
        merchantName: normalizedName,
        merchantCity: normalizedCity
      )
    )
  }
}

import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

@Test func pixKeyInferenceUsesTheBackendOrder() {
  #expect(PixKeyInput.inferType(from: "123.456.789-01") == .cpf)
  #expect(PixKeyInput.inferType(from: "12.345.678/0001-90") == .cnpj)
  #expect(PixKeyInput.inferType(from: "Ana@Example.com") == .email)
  #expect(PixKeyInput.inferType(from: "+55 (11) 99999-4321") == .phone)
  #expect(PixKeyInput.inferType(from: "550e8400-e29b-41d4-a716-446655440000") == .random)
  #expect(PixKeyInput.inferType(from: "11999994321") == .cpf)
}

@Test func pixKeyFormattingAndNormalizationCoverCPFAndCNPJ() {
  #expect(PixKeyInput.formatted("12345678901", as: .cpf) == "123.456.789-01")
  #expect(PixKeyInput.normalized("123.456.789-01", as: .cpf) == "12345678901")
  #expect(PixKeyInput.formatted("12345678000190", as: .cnpj) == "12.345.678/0001-90")
  #expect(PixKeyInput.normalized("12.345.678/0001-90", as: .cnpj) == "12345678000190")
  #expect(PixKeyInput(type: .cpf, value: "123").validationMessage == "Informe um CPF com 11 dígitos.")
  #expect(PixKeyInput(type: .cnpj, value: "123").validationMessage == "Informe um CNPJ com 14 dígitos.")
  #expect(PixKeyInput.formatted("123.456.789-0199", as: .cpf) == "123.456.789-01")
  #expect(PixKeyInput.formatted("12.345.678/0001-9099", as: .cnpj) == "12.345.678/0001-90")
}

@Test func pixEmailAndPhoneRulesNormalizePasteAndRejectInvalidValues() {
  #expect(PixKeyInput.normalized(" Ana@Example.COM ", as: .email) == "ana@example.com")
  #expect(PixKeyInput.normalized("ana @example.com", as: .email) == nil)
  #expect(PixKeyInput.normalized("ana@example", as: .email) == nil)
  #expect(PixKeyInput.normalized("(11) 99999-4321", as: .phone) == "+5511999994321")
  #expect(PixKeyInput.normalized("+55 (11) 3333-4321", as: .phone) == "+551133334321")
  #expect(PixKeyInput.normalized("1133334321", as: .phone) == "+551133334321")
  #expect(PixKeyInput.normalized("5511999994321", as: .phone) == "+5511999994321")
  #expect(PixKeyInput.formatted("+5511999994321", as: .phone) == "+55 (11) 99999-4321")
  #expect(PixKeyInput(type: .phone, value: "11999").validationMessage == "Informe um telefone com DDD.")
}

@Test func pixValidationMessagesMatchEveryApprovedType() {
  #expect(PixKeyInput(type: .cpf, value: "").validationMessage == "Informe a chave PIX.")
  #expect(PixKeyInput(type: .cpf, value: "123").validationMessage == "Informe um CPF com 11 dígitos.")
  #expect(PixKeyInput(type: .cnpj, value: "123").validationMessage == "Informe um CNPJ com 14 dígitos.")
  #expect(PixKeyInput(type: .email, value: "ana@example").validationMessage == "Informe um e-mail válido.")
  #expect(PixKeyInput(type: .phone, value: "11999").validationMessage == "Informe um telefone com DDD.")
  #expect(
    PixKeyInput(type: .random, value: "550e8400").validationMessage
      == "Informe uma chave aleatória válida no formato UUID."
  )
}

@Test func randomPixKeysInsertHyphensLowercaseAndRequireAFullUUID() {
  let uppercase = "550E8400E29B41D4A716446655440000"
  let normalized = "550e8400-e29b-41d4-a716-446655440000"
  #expect(PixKeyInput.formatted(uppercase, as: .random) == normalized)
  #expect(PixKeyInput.normalized(uppercase, as: .random) == normalized)
  #expect(PixKeyInput.normalized("550e8400-e29b", as: .random) == nil)
  #expect(PixKeyInput.formatted("550e8400-G29b", as: .random) == "550e8400-29b")
}

@Test func pixReviewMasksExposeOnlyTheApprovedCharacters() {
  #expect(PixKeyInput(type: .cpf, value: "12345678901").maskedValue == "***.***.***-01")
  #expect(PixKeyInput(type: .cnpj, value: "12345678000190").maskedValue == "**.***.***/****-90")
  #expect(PixKeyInput(type: .email, value: "alice@example.com").maskedValue == "a••••e@example.com")
  #expect(PixKeyInput(type: .phone, value: "11999994321").maskedValue == "+55 (**) *****-4321")
  #expect(PixKeyInput(type: .random, value: "550e8400e29b41d4a716446655440000").maskedValue == "••••0000")
}

@Test func changingANonEmptyPixKeyTypeRequiresExplicitClearing() {
  let input = PixKeyInput(type: .email, value: "ana@example.com")
  #expect(input.requiresConfirmation(to: .phone))
  #expect(!input.requiresConfirmation(to: .email))
  #expect(!PixKeyInput(type: .email, value: "").requiresConfirmation(to: .phone))
}

@Test func unclassifiedLegacyPixIsPreservedAndBlockedUntilEdited() {
  let legacy = PixKeyInput(persistedKey: "chave-legada")
  #expect(legacy.type == .random)
  #expect(legacy.value == "chave-legada")
  #expect(legacy.preservesUnclassifiedLegacyValue)
  #expect(legacy.normalizedValue == nil)
  #expect(legacy.validationMessage == "Esta chave não corresponde ao tipo selecionado.")
}

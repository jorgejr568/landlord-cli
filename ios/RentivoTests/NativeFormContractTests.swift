import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

@Test func billingDraftValidatesTheCompleteReplyToCollection() {
  let validItem = BillingItem(
    id: BillingItemID(rawValue: "01ARZ3NDEKTSV4RRFFQ69G5FAV"),
    description: "Aluguel", amount: Money(centavos: 100_000), type: .fixed, sortOrder: 0
  )
  let invalidReplyTo = BillingRecipient(
    id: RecipientID(rawValue: "reply-1"), name: "Financeiro", email: "email-invalido"
  )
  let draft = BillingDraft(
    name: "Apartamento", description: "", owner: .user(id: 7, name: "Pessoal"),
    items: [validItem], replyTo: [invalidReplyTo]
  )

  #expect(draft.validate().contains { $0.field == .replyTo })
}

@Test func billingDraftEnforcesEveryNativeTextBoundaryBeforeSubmitting() {
  let item = BillingItem(
    id: BillingItemID(rawValue: "01ARZ3NDEKTSV4RRFFQ69G5FAV"),
    description: String(repeating: "i", count: 256), amount: .zero, type: .variable, sortOrder: 0
  )
  let recipient = BillingRecipient(
    id: RecipientID(rawValue: "recipient-1"),
    name: String(repeating: "n", count: 256), email: "valid@example.com"
  )
  let draft = BillingDraft(
    name: String(repeating: "n", count: 256),
    description: String(repeating: "d", count: 2_001),
    owner: .user(id: 7, name: "Pessoal"), items: [item], recipients: [recipient]
  )

  let fields = Set(draft.validate().map(\.field))
  #expect(fields.isSuperset(of: [.name, .description, .itemDescription, .recipient]))
}

@Test func pixFormRulesRequireAllOrNoneAndNormalizeACompleteTriple() {
  #expect(
    PixFormRules.result(key: "", merchantName: "", merchantCity: "") == .inherit
  )
  #expect(
    PixFormRules.result(key: "chave", merchantName: "", merchantCity: "São Paulo")
      == .invalid("Preencha a chave, o nome e a cidade do recebedor para usar PIX personalizado.")
  )
  #expect(
    PixFormRules.result(key: " chave ", merchantName: " Locador ", merchantCity: " SAO PAULO ")
      == .custom(PixConfiguration(key: "chave", merchantName: "Locador", merchantCity: "SAO PAULO"))
  )
}

@Test func communicationFormRulesCountUTF8BytesRatherThanCharacters() {
  #expect(CommunicationFormRules.issues(subject: "Assunto", body: String(repeating: "a", count: 4_096)).isEmpty)
  #expect(
    CommunicationFormRules.issues(subject: "Assunto", body: String(repeating: "á", count: 2_049))
      .contains { $0.field == .body }
  )
  #expect(
    CommunicationFormRules.issues(subject: "   ", body: "Mensagem")
      .contains { $0.field == .subject }
  )
}

@Test func communicationFormRulesEnforceTheServerSubjectLimit() {
  #expect(CommunicationFormRules.issues(subject: String(repeating: "a", count: 998), body: "ok").isEmpty)
  #expect(
    CommunicationFormRules.issues(subject: String(repeating: "a", count: 999), body: "ok")
      .contains { $0.field == .subject })
}

@Test func themeFormRulesRejectMalformedHexAndWarnAboutLowContrast() {
  var values = ThemeValues.rentivo
  values.primary = "07744F"
  #expect(ThemeFormRules.invalidColorNames(in: values) == ["Primária"])

  values.primary = "#FFFFFF"
  values.textContrast = "#FFFFFF"
  #expect(!ThemeFormRules.contrastWarnings(for: values).isEmpty)
}

@Test func moneyInputRulesCapPastedAmountsInsteadOfResettingOverflowToZero() {
  #expect(MoneyInputRules.centavos(from: "R$ 2.450,00") == 245_000)
  #expect(MoneyInputRules.centavos(from: "000000123") == 123)
  #expect(MoneyInputRules.centavos(from: "sem valor") == 0)
  #expect(MoneyInputRules.centavos(from: "٣٥٠") == 0)
  #expect(MoneyInputRules.centavos(from: "2.147.483.647") == 2_147_483_647)
  #expect(MoneyInputRules.centavos(from: "999999999999999999999") == 2_147_483_647)
}

@Test func authEmailRulesMatchThePermissiveBackendCredentialContract() {
  #expect(AuthEmailAddress.isValid(" a@b "))
  #expect(AuthEmailAddress.isValid("ana@example.com"))
  #expect(!AuthEmailAddress.isValid("ana"))
  #expect(!AuthEmailAddress.isValid("a@@b"))
  #expect(!AuthEmailAddress.isValid("a @b"))
}

@Test func uploadPolicyRejectsUnsupportedAndOversizedFilesBeforeReadingThem() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }

  let unsupported = directory.appendingPathComponent("foto.heic")
  try Data([0x00]).write(to: unsupported)
  #expect(throws: FileUploadValidationError.unsupportedType) {
    _ = try FileUpload.from(url: unsupported, policy: .rentivoDocument)
  }

  let oversized = directory.appendingPathComponent("grande.pdf")
  try Data(count: RentivoUploadPolicy.maxByteCount + 1).write(to: oversized)
  #expect(throws: FileUploadValidationError.tooLarge) {
    _ = try FileUpload.from(url: oversized, policy: .rentivoDocument)
  }
}

@Test func receiptUploadResponseExplainsEveryServerRejectionReason() throws {
  let response = try JSONDecoder().decode(
    RemoteReceiptUpload.self,
    from: Data(
      #"{"items":[],"skipped_reasons":["unsupported_mime","empty_file","size_limit_exceeded"]}"#.utf8
    )
  )

  #expect(response.rejectionMessage?.contains("PDF, JPG ou PNG") == true)
  #expect(response.rejectionMessage?.contains("vazio") == true)
  #expect(response.rejectionMessage?.contains("10 MB") == true)
}

@Test func organizationDraftStateDetectsEveryEditableField() {
  let original = NativeOrganizationDraftState(
    name: "Horizonte", pixKey: "pix", merchantName: "HORIZONTE", city: "SALVADOR",
    usesCustomPix: true
  )

  #expect(original.hasChanges(from: original) == false)
  #expect(
    NativeOrganizationDraftState(
      name: "Horizonte Sul", pixKey: "pix", merchantName: "HORIZONTE", city: "SALVADOR",
      usesCustomPix: true
    ).hasChanges(from: original)
  )
  #expect(
    NativeOrganizationDraftState(
      name: "Horizonte", pixKey: "pix", merchantName: "HORIZONTE", city: "SALVADOR",
      usesCustomPix: false
    ).hasChanges(from: original)
  )
}

@Test func apiKeyDraftStateTracksFieldsAndUserEditedExpiration() {
  let original = NativeAPIKeyDraftState(
    name: "CRM", scopes: [.profileRead], resourceIDs: [.personal]
  )

  #expect(original.hasChanges(from: original, expirationEdited: false) == false)
  #expect(original.hasChanges(from: original, expirationEdited: true))
  #expect(
    NativeAPIKeyDraftState(
      name: "CRM novo", scopes: [.profileRead], resourceIDs: [.personal]
    ).hasChanges(from: original, expirationEdited: false)
  )
  #expect(
    NativeAPIKeyDraftState(
      name: "CRM", scopes: [.profileRead, .billingsRead], resourceIDs: [.personal]
    ).hasChanges(from: original, expirationEdited: false)
  )
  #expect(
    NativeAPIKeyDraftState(
      name: "CRM", scopes: [.profileRead],
      resourceIDs: [.personal, WorkspaceID(rawValue: "org-1")]
    ).hasChanges(from: original, expirationEdited: false)
  )
}

@Test func communicationDraftStateTracksTypeRecipientsContentAndSaveScope() {
  let recipient = RecipientID(rawValue: "recipient-1")
  let original = NativeCommunicationDraftState(
    commType: .billReady, selectedRecipients: [recipient], subject: "Fatura",
    message: "Segue a fatura", saveScope: nil
  )

  #expect(original.hasChanges(from: original) == false)
  #expect(
    NativeCommunicationDraftState(
      commType: .paymentReceipt, selectedRecipients: [recipient], subject: "Recibo",
      message: "Segue o recibo", saveScope: .billing
    ).hasChanges(from: original)
  )
  #expect(
    NativeCommunicationDraftState(
      commType: .billReady, selectedRecipients: [], subject: "Fatura atualizada",
      message: "Segue a fatura", saveScope: nil
    ).hasChanges(from: original)
  )
}

import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

@Test func billingRequiresNameAndAtLeastOneItem() {
  let issues = BillingDraft.empty.validate()

  #expect(issues.map(\.field) == [.name, .items])
}

@Test func billingRejectsBlankItemDescriptionsAndNegativeAmounts() {
  let draft = BillingDraft(
    name: "Apartamento",
    description: "",
    owner: .user(id: StableID.userAna, name: "Pessoal"),
    items: [
      BillingItem(
        id: UUID(),
        description: "  ",
        amount: Money(centavos: -1),
        type: .fixed,
        sortOrder: 0
      )
    ]
  )

  #expect(draft.validate().map(\.field) == [.itemDescription, .itemAmount])
}

@Test func canonicalBillingDraftIsValid() {
  let draft = BillingDraft(
    name: "Apt 101",
    description: "Contrato mensal",
    owner: .user(id: StableID.userAna, name: "Pessoal"),
    items: [
      BillingItem(
        id: UUID(),
        description: "Aluguel",
        amount: Money(centavos: 180_000),
        type: .fixed,
        sortOrder: 0
      )
    ]
  )

  #expect(draft.validate().isEmpty)
}

@Test func variableBillingItemTypeHidesAndClearsTheTemplateAmount() {
  #expect(!BillingItemType.variable.showsTemplateAmount)
  #expect(BillingItemType.variable.normalizedTemplateAmount(5_000) == 0)
  #expect(BillingItemType.fixed.showsTemplateAmount)
  #expect(BillingItemType.fixed.normalizedTemplateAmount(5_000) == 5_000)
}

@Test func billingRejectsNonZeroVariableTemplateAmounts() {
  let draft = BillingDraft(
    name: "Apt 101",
    description: "Contrato mensal",
    owner: .user(id: StableID.userAna, name: "Pessoal"),
    items: [
      BillingItem(
        id: UUID(),
        description: "Água",
        amount: Money(centavos: 5_000),
        type: .variable,
        sortOrder: 0
      )
    ]
  )

  #expect(
    draft.validate()
      == [
        ValidationIssue(
          field: .itemAmount,
          message: "Itens variáveis devem ter valor zero no modelo."
        )
      ]
  )
}

@Test func billingKeepsEveryRecipientItIsGiven() {
  // A billing update replaces the whole recipient set server-side, so a draft carrying
  // several recipients must validate as-is instead of being narrowed to the first one.
  let draft = BillingDraft(
    name: "Apt 101",
    description: "",
    owner: .user(id: StableID.userAna, name: "Pessoal"),
    items: [
      BillingItem(id: UUID(), description: "Aluguel", amount: Money(centavos: 180_000), type: .fixed, sortOrder: 0)
    ],
    recipients: [
      BillingRecipient(id: RecipientID(rawValue: "r1"), name: "Ana", email: "ana@example.com"),
      BillingRecipient(id: RecipientID(rawValue: "r2"), name: "Bruno", email: "bruno@example.com"),
    ]
  )

  #expect(draft.validate().isEmpty)
  #expect(draft.recipients.count == 2)
}

@Test func billingRejectsIncompleteOrMalformedRecipients() {
  let draft = BillingDraft(
    name: "Apt 101",
    description: "",
    owner: .user(id: StableID.userAna, name: "Pessoal"),
    items: [
      BillingItem(id: UUID(), description: "Aluguel", amount: Money(centavos: 180_000), type: .fixed, sortOrder: 0)
    ],
    recipients: [
      BillingRecipient(id: RecipientID(rawValue: "r1"), name: "Ana", email: "ana@example.com"),
      BillingRecipient(id: RecipientID(rawValue: "r2"), name: "  ", email: "bruno@example.com"),
      BillingRecipient(id: RecipientID(rawValue: "r3"), name: "Carla", email: "carla@example"),
    ]
  )

  #expect(draft.validate().map(\.field) == [.recipient])
}

@Test func billingRejectsRepeatedRecipientEmails() {
  // The send endpoint requires distinct recipient uuids, and the server keys contacts by
  // email, so two rows sharing an address would break the communication flow.
  let draft = BillingDraft(
    name: "Apt 101",
    description: "",
    owner: .user(id: StableID.userAna, name: "Pessoal"),
    items: [
      BillingItem(id: UUID(), description: "Aluguel", amount: Money(centavos: 180_000), type: .fixed, sortOrder: 0)
    ],
    recipients: [
      BillingRecipient(id: RecipientID(rawValue: "r1"), name: "Ana", email: "ana@example.com"),
      BillingRecipient(id: RecipientID(rawValue: "r2"), name: "Ana (cópia)", email: "ANA@example.com"),
    ]
  )

  #expect(draft.validate().map(\.field) == [.recipient])
}

@Test func billingDraftMirrorsEveryServerTextLimit() {
  let draft = BillingDraft(
    name: String(repeating: "n", count: 256),
    description: String(repeating: "d", count: 2_001),
    owner: .user(id: StableID.userAna, name: "Pessoal"),
    items: [
      BillingItem(
        id: UUID(), description: String(repeating: "i", count: 256), amount: .zero,
        type: .fixed, sortOrder: 0
      )
    ],
    pixOverride: PixConfiguration(
      key: "pix", merchantName: String(repeating: "m", count: 26),
      merchantCity: String(repeating: "c", count: 16)
    ),
    recipients: [
      BillingRecipient(
        id: RecipientID(rawValue: "r1"), name: String(repeating: "r", count: 256),
        email: "ana@example.com"
      )
    ],
    replyTo: "resposta-invalida"
  )

  #expect(
    draft.validate().map(\.field)
      == [.name, .description, .itemDescription, .pix, .recipient, .replyTo]
  )
}

@Test func emailValidationAcceptsAddressesTheServerAccepts() {
  #expect(EmailAddress.isValid("ana@example.com"))
  #expect(EmailAddress.isValid("ana+cobranca@sub.example.com.br"))
  #expect(!EmailAddress.isValid(""))
  #expect(!EmailAddress.isValid("ana"))
  #expect(!EmailAddress.isValid("ana@example"))
  #expect(!EmailAddress.isValid("ana @example.com"))
  #expect(!EmailAddress.isValid(".ana@example.com"))
  #expect(!EmailAddress.isValid("ana.@example.com"))
  #expect(!EmailAddress.isValid("ana..silva@example.com"))
  #expect(!EmailAddress.isValid("ana()@example.com"))
  #expect(!EmailAddress.isValid("ana@example..com"))
  #expect(!EmailAddress.isValid("ana@-example.com"))
  #expect(!EmailAddress.isValid("ana@example-.com"))
  #expect(!EmailAddress.isValid("\(String(repeating: "a", count: 65))@example.com"))
  #expect(!EmailAddress.isValid("ana@\(String(repeating: "a", count: 64)).com"))
}

@Test func invoiceDraftRejectsBlankRowsAndNegativeValues() {
  let draft = BillDraft(
    billingID: StableID.billingAurora101,
    referenceMonth: ReferenceMonth(year: 2026, month: 8),
    dueDate: DateOnly(year: 2026, month: 8, day: 10),
    notes: "",
    lineItems: [
      BillLineItem(
        id: UUID(),
        description: "",
        amount: Money(centavos: -100),
        kind: .variable
      )
    ]
  )

  #expect(draft.validate().map(\.field) == [.itemDescription, .itemAmount])
}

@Test func invoiceDraftRejectsDescriptionsBeyondTheServerLimit() {
  let draft = BillDraft(
    billingID: StableID.billingAurora101,
    referenceMonth: ReferenceMonth(year: 2026, month: 8),
    dueDate: nil,
    notes: "",
    lineItems: [
      BillLineItem(
        id: UUID(), description: String(repeating: "i", count: 256), amount: .zero,
        kind: .fixed
      )
    ]
  )

  #expect(draft.validate().map(\.field) == [.itemDescription])
}

@Test func invoiceDraftAllowsZeroAmountForFixedAndVariableLineItems() {
  // Variable items (e.g. water/electricity meters) legitimately start at zero
  // before this month's reading is filled in; only extras must be positive.
  let draft = BillDraft(
    billingID: StableID.billingAurora101,
    referenceMonth: ReferenceMonth(year: 2026, month: 8),
    dueDate: DateOnly(year: 2026, month: 8, day: 10),
    notes: "",
    lineItems: [
      BillLineItem(id: UUID(), description: "Aluguel", amount: Money(centavos: 180_000), kind: .fixed),
      BillLineItem(id: UUID(), description: "Água", amount: .zero, kind: .variable),
    ]
  )

  #expect(draft.validate().isEmpty)
}

@Test func invoiceDraftRejectsZeroOrNegativeExtraLineItems() {
  // The server requires `BillExtraRequest.amount` to be strictly positive
  // (`exclusiveMinimum: 0`), so a zero-value extra must fail client-side too.
  let zeroExtraDraft = BillDraft(
    billingID: StableID.billingAurora101,
    referenceMonth: ReferenceMonth(year: 2026, month: 8),
    dueDate: DateOnly(year: 2026, month: 8, day: 10),
    notes: "",
    lineItems: [
      BillLineItem(id: UUID(), description: "Pintura", amount: .zero, kind: .extra)
    ]
  )
  #expect(zeroExtraDraft.validate().map(\.field) == [.itemAmount])

  let negativeExtraDraft = BillDraft(
    billingID: StableID.billingAurora101,
    referenceMonth: ReferenceMonth(year: 2026, month: 8),
    dueDate: DateOnly(year: 2026, month: 8, day: 10),
    notes: "",
    lineItems: [
      BillLineItem(id: UUID(), description: "Pintura", amount: Money(centavos: -500), kind: .extra)
    ]
  )
  #expect(negativeExtraDraft.validate().map(\.field) == [.itemAmount])
}

@Test func invoiceDraftAcceptsPositiveExtraLineItems() {
  let draft = BillDraft(
    billingID: StableID.billingAurora101,
    referenceMonth: ReferenceMonth(year: 2026, month: 8),
    dueDate: DateOnly(year: 2026, month: 8, day: 10),
    notes: "",
    lineItems: [
      BillLineItem(id: UUID(), description: "Pintura", amount: Money(centavos: 5_000), kind: .extra)
    ]
  )

  #expect(draft.validate().isEmpty)
}

@Test func expenseDescriptionsMirrorTheServerContract() {
  #expect(!ExpenseInput.isValidDescription("   "))
  #expect(ExpenseInput.isValidDescription(String(repeating: "d", count: 2_000)))
  #expect(!ExpenseInput.isValidDescription(String(repeating: "d", count: 2_001)))
  #expect(ExpenseInput.normalizedDescription("  Pintura  ") == "Pintura")
}

@Test func communicationContentMirrorsTheServerContract() {
  #expect(CommunicationContent.validationMessage(subject: "   ", message: "Corpo") != nil)
  #expect(CommunicationContent.validationMessage(subject: "Assunto", message: "   ") != nil)
  #expect(CommunicationContent.validationMessage(
    subject: String(repeating: "a", count: 998),
    message: String(repeating: "b", count: 4_096)
  ) == nil)
  #expect(CommunicationContent.validationMessage(
    subject: String(repeating: "a", count: 999), message: "Corpo"
  ) != nil)
  #expect(CommunicationContent.validationMessage(
    subject: "Assunto", message: String(repeating: "b", count: 4_097)
  ) != nil)
  #expect(CommunicationContent.validationMessage(
    subject: "Assunto", message: String(repeating: "😀", count: 1_025)
  ) != nil)
  #expect(CommunicationContent.normalizedSubject("  Assunto  ") == "Assunto")
  #expect(CommunicationContent.normalizedMessage("  Corpo  ") == "Corpo")
}

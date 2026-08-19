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

@Test func billingRejectsAmountsOrFixedSubtotalsBeyondPersistenceLimit() {
  let draft = BillingDraft(
    name: "Apt 101",
    description: "",
    owner: .user(id: StableID.userAna, name: "Pessoal"),
    items: [
      BillingItem(
        id: UUID(), description: "Aluguel",
        amount: Money(centavos: Money.maximumPersistedCentavos), type: .fixed, sortOrder: 0
      ),
      BillingItem(
        id: UUID(), description: "Condomínio", amount: Money(centavos: 1),
        type: .fixed, sortOrder: 1
      ),
    ]
  )

  #expect(draft.validate().map(\.field) == [.itemAmount])
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
      key: "ana@example.com", merchantName: String(repeating: "m", count: 26),
      merchantCity: String(repeating: "c", count: 16)
    ),
    recipients: [
      BillingRecipient(
        id: RecipientID(rawValue: "r1"), name: String(repeating: "r", count: 256),
        email: "ana@example.com"
      )
    ],
    replyTo: [
      BillingRecipient(
        id: RecipientID(rawValue: "reply-1"), name: "Resposta", email: "resposta-invalida"
      )
    ]
  )

  #expect(
    draft.validate().map(\.field)
      == [.name, .description, .itemDescription, .pix, .recipient, .replyTo]
  )
}

@Test func billingDraftRejectsRepeatedReplyToContacts() {
  let draft = BillingDraft(
    name: "Apt 101",
    description: "",
    owner: .user(id: StableID.userAna, name: "Pessoal"),
    items: [
      BillingItem(
        id: UUID(), description: "Aluguel", amount: Money(centavos: 180_000),
        type: .fixed, sortOrder: 0
      )
    ],
    replyTo: [
      BillingRecipient(id: RecipientID(rawValue: "a"), name: "Ana", email: "ana@example.com"),
      BillingRecipient(id: RecipientID(rawValue: "b"), name: "Cópia", email: " ANA@example.com "),
    ]
  )

  #expect(draft.validate().filter { $0.field == .replyTo }.map(\.message) == [
    "Remova os contatos de resposta repetidos."
  ])
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

@Test func organizationInviteEmailMirrorsTheServerContract() {
  #expect(OrganizationInviteEmail.normalized("  ANA@EXAMPLE.COM\n") == "ana@example.com")
  #expect(OrganizationInviteEmail.isValid("a@b"))
  #expect(OrganizationInviteEmail.isValid("\(String(repeating: "😀", count: 318))@a"))
  #expect(!OrganizationInviteEmail.isValid(""))
  #expect(!OrganizationInviteEmail.isValid("ana"))
  #expect(!OrganizationInviteEmail.isValid("a@@b"))
  #expect(!OrganizationInviteEmail.isValid("@example.com"))
  #expect(!OrganizationInviteEmail.isValid("ana@"))
  #expect(!OrganizationInviteEmail.isValid("ana @example.com"))
  #expect(!OrganizationInviteEmail.isValid("\(String(repeating: "😀", count: 319))@a"))
  #expect(OrganizationInviteEmail.maximumLength == 320)
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

@Test func invoiceDraftRejectsAmountsOrTotalsBeyondPersistenceLimit() {
  let draft = BillDraft(
    billingID: StableID.billingAurora101,
    referenceMonth: ReferenceMonth(year: 2026, month: 8),
    dueDate: nil,
    notes: "",
    lineItems: [
      BillLineItem(
        id: UUID(), description: "Aluguel",
        amount: Money(centavos: Money.maximumPersistedCentavos), kind: .fixed
      ),
      BillLineItem(
        id: UUID(), description: "Condomínio", amount: Money(centavos: 1), kind: .fixed
      ),
    ]
  )

  #expect(draft.validate().map(\.field) == [.itemAmount])
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

@Test func organizationNamesMirrorTheServerContract() {
  #expect(OrganizationDraft(name: "   ", pix: nil).isValid == false)
  #expect(OrganizationDraft(name: String(repeating: "😀", count: 255), pix: nil).isValid)
  #expect(OrganizationDraft(name: String(repeating: "😀", count: 256), pix: nil).isValid == false)
  #expect(OrganizationDraft.nameLimit == 255)
}

@Test func organizationPIXFieldsMirrorTheServerCharacterLimits() {
  let combiningCharacter = "e\u{301}"
  #expect(
    OrganizationDraft.pixValidationMessage(
      key: "ana@example.com", merchantName: String(repeating: "😀", count: 25), city: String(repeating: "😀", count: 15)
    ) == nil
  )
  #expect(
    OrganizationDraft.pixValidationMessage(
      key: "ana@example.com", merchantName: String(repeating: combiningCharacter, count: 13), city: "RECIFE"
    ) == "O nome do recebedor deve ter até 25 caracteres."
  )
  #expect(
    OrganizationDraft.pixValidationMessage(
      key: "ana@example.com", merchantName: "ANA", city: String(repeating: combiningCharacter, count: 8)
    ) == "A cidade do recebedor deve ter até 15 caracteres."
  )
  #expect(
    OrganizationDraft(
      name: "Imobiliária",
      pix: PixConfiguration(
        key: "ana@example.com", merchantName: String(repeating: combiningCharacter, count: 13),
        merchantCity: "RECIFE"
      )
    ).isValid == false
  )
}

@Test func customPIXValidationRejectsTheKeyBeforeRecipientData() {
  let item = BillingItem(
    id: UUID(), description: "Aluguel", amount: Money(centavos: 120_000),
    type: .fixed, sortOrder: 0
  )
  let draft = BillingDraft(
    name: "Apartamento 202",
    description: "",
    owner: .user(id: StableID.userAna, name: "Pessoal"),
    items: [item],
    pixOverride: PixConfiguration(key: "incompatível", merchantName: "", merchantCity: "")
  )

  #expect(
    draft.validate().first(where: { $0.field == .pix })?.message
      == "Esta chave não corresponde ao tipo selecionado."
  )
  #expect(
    OrganizationDraft.pixValidationMessage(
      key: "incompatível", merchantName: "", city: ""
    ) == "Esta chave não corresponde ao tipo selecionado."
  )
}

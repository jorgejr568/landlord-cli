package app.rentivo.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ValidationTest {

  @Test
  fun `totp code is exactly six decimal digits`() {
    assertEquals(null, TOTPCodeRule.validationMessage("123456"))
    assertEquals("Informe um código de seis dígitos.", TOTPCodeRule.validationMessage("12345"))
    assertEquals("Informe um código de seis dígitos.", TOTPCodeRule.validationMessage("12345a"))
  }

  @Test
  fun `bcrypt password limit counts UTF-8 bytes rather than characters`() {
    assertEquals(null, PasswordInput.validationMessage("a".repeat(72)))
    assertEquals(null, PasswordInput.validationMessage("á".repeat(36)))
    assertEquals("A senha deve ter no máximo 72 bytes UTF-8.", PasswordInput.validationMessage("a".repeat(73)))
    assertEquals("A senha deve ter no máximo 72 bytes UTF-8.", PasswordInput.validationMessage("á".repeat(37)))
  }

  @Test
  fun `pix form fields reject every partial triple including a blank key`() {
    val nameWithoutKey = PixFormFields(key = "", merchantName = "Ana", merchantCity = "Santos")
    val cityWithoutKey = PixFormFields(key = " ", merchantName = "", merchantCity = "Recife")
    val empty = PixFormFields(key = " ", merchantName = "", merchantCity = " ")

    assertFalse(nameWithoutKey.isValid)
    assertFalse(cityWithoutKey.isValid)
    assertEquals(null, nameWithoutKey.configuration)
    assertTrue(empty.isValid)
    assertEquals(null, empty.configuration)
  }

  @Test
  fun billingRequiresNameAndAtLeastOneItem() {
    val issues = BillingDraft.empty.validate()

    assertEquals(
      listOf(ValidationField.NAME, ValidationField.ITEMS),
      issues.map { it.field },
    )
    assertEquals(
      listOf("Informe o nome da cobrança.", "Adicione ao menos um item recorrente."),
      issues.map { it.message },
    )
  }

  @Test
  fun billingRejectsBlankItemDescriptionsAndNegativeAmounts() {
    val draft = BillingDraft(
      name = "Apartamento",
      description = "",
      owner = BillingOwner.User(id = StableID.userAna, name = "Pessoal"),
      items = listOf(
        BillingItem.generated(
          description = "  ",
          amount = Money(centavos = -1),
          type = BillingItemType.FIXED,
          sortOrder = 0,
        )
      ),
    )

    assertEquals(
      listOf(ValidationField.ITEM_DESCRIPTION, ValidationField.ITEM_AMOUNT),
      draft.validate().map { it.field },
    )
    assertEquals(
      listOf("Descreva todos os itens.", "Os valores não podem ser negativos."),
      draft.validate().map { it.message },
    )
  }

  @Test
  fun `billing text limits match the API boundaries`() {
    fun draft(
      name: String = "a".repeat(255),
      description: String = "d".repeat(2_000),
      itemDescription: String = "i".repeat(255),
      contactName: String = "c".repeat(255),
      contactEmail: String = "a".repeat(308) + "@example.com",
    ) = BillingDraft(
      name = name,
      description = description,
      owner = BillingOwner.User(StableID.userAna, "Pessoal"),
      items = listOf(BillingItem.generated(itemDescription, Money.zero, BillingItemType.FIXED, 0)),
      recipients = listOf(BillingRecipient(RecipientID("r1"), contactName, contactEmail)),
    )

    assertTrue(draft().validate().isEmpty())
    assertTrue(draft(name = "a".repeat(256)).validate().any { it.field == ValidationField.NAME })
    assertTrue(draft(description = "d".repeat(2_001)).validate().any { it.field == ValidationField.DESCRIPTION })
    assertTrue(draft(itemDescription = "i".repeat(256)).validate().any { it.field == ValidationField.ITEM_DESCRIPTION })
    assertTrue(draft(contactName = "c".repeat(256)).validate().any { it.field == ValidationField.RECIPIENT })
    assertTrue(draft(contactEmail = "a".repeat(309) + "@example.com").validate().any { it.field == ValidationField.RECIPIENT })
  }

  @Test
  fun canonicalBillingDraftIsValid() {
    val draft = BillingDraft(
      name = "Apt 101",
      description = "Contrato mensal",
      owner = BillingOwner.User(id = StableID.userAna, name = "Pessoal"),
      items = listOf(
        BillingItem.generated(
          description = "Aluguel",
          amount = Money(centavos = 180_000),
          type = BillingItemType.FIXED,
          sortOrder = 0,
        )
      ),
    )

    assertTrue(draft.validate().isEmpty())
  }

  @Test
  fun variableBillingItemTypeHidesAndClearsTheTemplateAmount() {
    assertFalse(BillingItemType.VARIABLE.showsTemplateAmount)
    assertEquals(0, BillingItemType.VARIABLE.normalizedTemplateAmount(5_000))
    assertTrue(BillingItemType.FIXED.showsTemplateAmount)
    assertEquals(5_000, BillingItemType.FIXED.normalizedTemplateAmount(5_000))
  }

  @Test
  fun billingRejectsNonZeroVariableTemplateAmounts() {
    val draft = BillingDraft(
      name = "Apt 101",
      description = "Contrato mensal",
      owner = BillingOwner.User(id = StableID.userAna, name = "Pessoal"),
      items = listOf(
        BillingItem.generated(
          description = "Água",
          amount = Money(centavos = 5_000),
          type = BillingItemType.VARIABLE,
          sortOrder = 0,
        )
      ),
    )

    assertEquals(
      listOf(
        ValidationIssue(
          ValidationField.ITEM_AMOUNT,
          "Itens variáveis devem ter valor zero no modelo.",
        )
      ),
      draft.validate(),
    )
  }

  @Test
  fun billingKeepsEveryRecipientItIsGiven() {
    // A billing update replaces the whole recipient set server-side, so a draft carrying several
    // recipients must validate as-is instead of being narrowed to the first one.
    val draft = BillingDraft(
      name = "Apt 101",
      description = "",
      owner = BillingOwner.User(id = StableID.userAna, name = "Pessoal"),
      items = listOf(
        BillingItem.generated(
          description = "Aluguel",
          amount = Money(centavos = 180_000),
          type = BillingItemType.FIXED,
          sortOrder = 0,
        )
      ),
      recipients = listOf(
        BillingRecipient(id = RecipientID("r1"), name = "Ana", email = "ana@example.com"),
        BillingRecipient(id = RecipientID("r2"), name = "Bruno", email = "bruno@example.com"),
      ),
    )

    assertTrue(draft.validate().isEmpty())
    assertEquals(2, draft.recipients.size)
  }

  @Test
  fun billingRejectsIncompleteOrMalformedRecipients() {
    val draft = BillingDraft(
      name = "Apt 101",
      description = "",
      owner = BillingOwner.User(id = StableID.userAna, name = "Pessoal"),
      items = listOf(
        BillingItem.generated(
          description = "Aluguel",
          amount = Money(centavos = 180_000),
          type = BillingItemType.FIXED,
          sortOrder = 0,
        )
      ),
      recipients = listOf(
        BillingRecipient(id = RecipientID("r1"), name = "Ana", email = "ana@example.com"),
        BillingRecipient(id = RecipientID("r2"), name = "  ", email = "bruno@example.com"),
        BillingRecipient(id = RecipientID("r3"), name = "Carla", email = "carla@example"),
      ),
    )

    assertEquals(listOf(ValidationField.RECIPIENT), draft.validate().map { it.field })
    assertEquals(
      listOf("Informe nome e e-mail válidos para todos os destinatários."),
      draft.validate().map { it.message },
    )
  }

  @Test
  fun billingRejectsRepeatedRecipientEmails() {
    // The send endpoint requires distinct recipient uuids, and the server keys contacts by email,
    // so two rows sharing an address would break the communication flow.
    val draft = BillingDraft(
      name = "Apt 101",
      description = "",
      owner = BillingOwner.User(id = StableID.userAna, name = "Pessoal"),
      items = listOf(
        BillingItem.generated(
          description = "Aluguel",
          amount = Money(centavos = 180_000),
          type = BillingItemType.FIXED,
          sortOrder = 0,
        )
      ),
      recipients = listOf(
        BillingRecipient(id = RecipientID("r1"), name = "Ana", email = "ana@example.com"),
        BillingRecipient(id = RecipientID("r2"), name = "Ana (cópia)", email = " ANA@example.com "),
      ),
    )

    assertEquals(listOf(ValidationField.RECIPIENT), draft.validate().map { it.field })
    assertEquals(listOf("Remova os destinatários repetidos."), draft.validate().map { it.message })
  }

  @Test
  fun emailValidationAcceptsAddressesTheServerAccepts() {
    assertTrue(EmailAddress.isValid("ana@example.com"))
    assertTrue(EmailAddress.isValid("ana+cobranca@sub.example.com.br"))
    assertFalse(EmailAddress.isValid(""))
    assertFalse(EmailAddress.isValid("ana"))
    assertFalse(EmailAddress.isValid("ana@example"))
    assertFalse(EmailAddress.isValid("ana @example.com"))
  }

  @Test
  fun invoiceDraftRejectsBlankRowsAndNegativeValues() {
    val draft = BillDraft(
      billingID = StableID.billingAurora101,
      referenceMonth = ReferenceMonth(year = 2026, month = 8),
      dueDate = DateOnly(year = 2026, month = 8, day = 10),
      notes = "",
      lineItems = listOf(
        BillLineItem.generated(
          description = "",
          amount = Money(centavos = -100),
          kind = BillLineItemKind.VARIABLE,
        )
      ),
    )

    assertEquals(
      listOf(ValidationField.ITEM_DESCRIPTION, ValidationField.ITEM_AMOUNT),
      draft.validate().map { it.field },
    )
    assertEquals(
      listOf("Descreva todos os itens da fatura.", "Os valores não podem ser negativos."),
      draft.validate().map { it.message },
    )
  }

  @Test
  fun invoiceDraftAllowsZeroAmountForFixedAndVariableLineItems() {
    // Variable items (e.g. water/electricity meters) legitimately start at zero before this
    // month's reading is filled in; only extras must be positive.
    val draft = BillDraft(
      billingID = StableID.billingAurora101,
      referenceMonth = ReferenceMonth(year = 2026, month = 8),
      dueDate = DateOnly(year = 2026, month = 8, day = 10),
      notes = "",
      lineItems = listOf(
        BillLineItem.generated(
          description = "Aluguel",
          amount = Money(centavos = 180_000),
          kind = BillLineItemKind.FIXED,
        ),
        BillLineItem.generated(
          description = "Água",
          amount = Money.zero,
          kind = BillLineItemKind.VARIABLE,
        ),
      ),
    )

    assertTrue(draft.validate().isEmpty())
  }

  @Test
  fun invoiceDraftRejectsZeroOrNegativeExtraLineItems() {
    // The server requires `BillExtraRequest.amount` to be strictly positive
    // (`exclusiveMinimum: 0`), so a zero-value extra must fail client-side too.
    val zeroExtraDraft = BillDraft(
      billingID = StableID.billingAurora101,
      referenceMonth = ReferenceMonth(year = 2026, month = 8),
      dueDate = DateOnly(year = 2026, month = 8, day = 10),
      notes = "",
      lineItems = listOf(
        BillLineItem.generated(
          description = "Pintura",
          amount = Money.zero,
          kind = BillLineItemKind.EXTRA,
        )
      ),
    )
    assertEquals(
      listOf(ValidationField.ITEM_AMOUNT),
      zeroExtraDraft.validate().map { it.field },
    )
    assertEquals(
      listOf("Os itens extras devem ter valor maior que zero."),
      zeroExtraDraft.validate().map { it.message },
    )

    val negativeExtraDraft = BillDraft(
      billingID = StableID.billingAurora101,
      referenceMonth = ReferenceMonth(year = 2026, month = 8),
      dueDate = DateOnly(year = 2026, month = 8, day = 10),
      notes = "",
      lineItems = listOf(
        BillLineItem.generated(
          description = "Pintura",
          amount = Money(centavos = -500),
          kind = BillLineItemKind.EXTRA,
        )
      ),
    )
    assertEquals(
      listOf(ValidationField.ITEM_AMOUNT),
      negativeExtraDraft.validate().map { it.field },
    )
  }

  @Test
  fun invoiceDraftAcceptsPositiveExtraLineItems() {
    val draft = BillDraft(
      billingID = StableID.billingAurora101,
      referenceMonth = ReferenceMonth(year = 2026, month = 8),
      dueDate = DateOnly(year = 2026, month = 8, day = 10),
      notes = "",
      lineItems = listOf(
        BillLineItem.generated(
          description = "Pintura",
          amount = Money(centavos = 5_000),
          kind = BillLineItemKind.EXTRA,
        )
      ),
    )

    assertTrue(draft.validate().isEmpty())
  }
}

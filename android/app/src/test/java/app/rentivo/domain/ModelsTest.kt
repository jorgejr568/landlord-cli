package app.rentivo.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

private class SampleLocalizedError(
  override val errorDescription: String?,
) : Exception(errorDescription), LocalizedError

private class SamplePlainError : Exception()

class ModelsTest {

  @Test
  fun stableIdentifiersAreDeterministic() {
    assertEquals(1, StableID.userAna)
    assertEquals("00000000-0000-0000-0000-000000000101", StableID.billingAurora101.rawValue)
    assertEquals("00000000-0000-0000-0000-000000001004", StableID.billPaid.rawValue)
  }

  @Test
  fun loadStateExposesLoadedValueOnly() {
    assertNull(LoadState.Idle.value)
    assertNull(LoadState.Loading.value)
    assertEquals(42, LoadState.Loaded(42).value)
    assertNull(LoadState.Empty.value)
    assertNull(LoadState.Failed(DemoError.operationFailed).value)
  }

  @Test
  fun demoErrorUsesPortugueseRecoveryCopy() {
    assertEquals(
      "Não foi possível concluir esta ação de demonstração.",
      DemoError.operationFailed.message,
    )
  }

  @Test
  fun demoErrorPreservesRealLocalizedErrorMessages() {
    val serverError = SampleLocalizedError("Sua sessão expirou. Entre novamente para continuar.")
    val wrapped = DemoError.from(serverError)
    assertEquals("Sua sessão expirou. Entre novamente para continuar.", wrapped.message)
  }

  @Test
  fun demoErrorFallsBackToGenericNonDemoCopyForUnknownErrors() {
    val wrapped = DemoError.from(SamplePlainError())
    assertEquals("Não foi possível concluir esta ação. Tente novamente.", wrapped.message)
    assertFalse(wrapped.message.contains("demonstração"))
  }

  @Test
  fun demoErrorPassesThroughExistingDemoErrors() {
    val wrapped = DemoError.from(DemoError.permissionDenied)
    assertEquals(DemoError.permissionDenied, wrapped)
    assertSame(DemoError.permissionDenied, wrapped)
  }

  @Test
  fun dateOnlyFailableInitializerParsesValidISOStrings() {
    assertEquals(
      DateOnly(year = 2026, month = 8, day = 10),
      DateOnly.fromIso8601String("2026-08-10"),
    )
  }

  @Test
  fun dateOnlyFailableInitializerRejectsMalformedWireData() {
    assertNull(DateOnly.fromIso8601String("not-a-date"))
    assertNull(DateOnly.fromIso8601String("2026-13-40"))
    assertNull(DateOnly.fromIso8601String("2026-08"))
  }

  @Test
  fun dateOnlyConstructorRejectsOutOfRangeComponents() {
    var thrown = false
    try {
      DateOnly(year = 2026, month = 13, day = 1)
    } catch (error: IllegalArgumentException) {
      thrown = true
    }
    assertEquals(true, thrown)

    thrown = false
    try {
      DateOnly(year = 2026, month = 1, day = 32)
    } catch (error: IllegalArgumentException) {
      thrown = true
    }
    assertEquals(true, thrown)
  }

  @Test
  fun referenceMonthFailableInitializerParsesValidAPIValues() {
    assertEquals(ReferenceMonth(year = 2026, month = 8), ReferenceMonth.fromApiValue("2026-08"))
  }

  @Test
  fun referenceMonthFailableInitializerRejectsMalformedWireData() {
    assertNull(ReferenceMonth.fromApiValue("not-a-month"))
    assertNull(ReferenceMonth.fromApiValue("2026-13"))
    assertNull(ReferenceMonth.fromApiValue("2026"))
  }

  @Test
  fun dateOnlyDisplayFormattedRendersBrazilianDayMonthYear() {
    assertEquals("10/08/2026", DateOnly(year = 2026, month = 8, day = 10).displayFormatted)
  }

  @Test
  fun referenceMonthDisplayFormattedMatchesPortugueseLabel() {
    assertEquals("agosto de 2026", ReferenceMonth(year = 2026, month = 8).displayFormatted)
  }

  @Test
  fun communicationTypeRawValuesMatchTheAPIContract() {
    assertEquals("bill_ready", CommunicationType.BILL_READY.wire)
    assertEquals("payment_receipt", CommunicationType.PAYMENT_RECEIPT.wire)
    assertEquals("billing", CommunicationSaveScope.BILLING.wire)
    assertEquals("owner", CommunicationSaveScope.OWNER.wire)
  }

  @Test
  fun billingResolvesTheTemplateForACommunicationType() {
    val billReady = CommunicationTemplate(
      commType = CommunicationType.BILL_READY,
      subject = "Cobrança {{unidade}}",
      body = "Olá {{nome_inquilino}}",
    )
    val receipt = CommunicationTemplate(
      commType = CommunicationType.PAYMENT_RECEIPT,
      subject = "Recibo {{unidade}}",
      body = "Recebemos {{total}}",
    )
    val billing = Billing(
      id = BillingID("b1"),
      name = "Apt 101",
      description = "",
      owner = BillingOwner.User(id = StableID.userAna, name = "Pessoal"),
      items = emptyList(),
      communicationTemplates = listOf(billReady, receipt),
    )

    assertEquals(billReady, billing.template(CommunicationType.BILL_READY))
    assertEquals(receipt, billing.template(CommunicationType.PAYMENT_RECEIPT))
    assertNull(
      Billing(
        id = BillingID("b2"),
        name = "Apt 102",
        description = "",
        owner = BillingOwner.User(id = StableID.userAna, name = "Pessoal"),
        items = emptyList(),
      ).template(CommunicationType.BILL_READY)
    )
  }

  @Test
  fun profilePixFormSeedsFromTheProfileAndRebuildsTheConfiguration() {
    val empty = ProfilePIXForm.from(null)
    assertEquals("", empty.key)
    assertEquals("", empty.merchantName)
    assertEquals("", empty.merchantCity)

    val pix = PixConfiguration(key = "ana@pix.com", merchantName = "Ana", merchantCity = "Recife")
    val seeded = ProfilePIXForm.from(UserProfile(id = 1, email = "ana@rentivo.com.br", pix = pix))
    assertEquals(pix, seeded.configuration)
    assertNotNull(seeded.configuration)
  }

  @Test
  fun profilePixFormDistinguishesClearFromAnInvalidPartialTriple() {
    val clear = ProfilePIXForm(key = "  ", merchantName = "", merchantCity = " ")
    assertNull(clear.configuration)

    val partial = ProfilePIXForm(key = "ana@pix.com", merchantName = "Ana", merchantCity = "")
    assertNull(partial.configuration)
  }

  @Test
  fun workspaceIdentifierForPersonalOwnershipIsTheLiteralPersonal() {
    assertEquals("personal", WorkspaceID.personal.rawValue)
    assertEquals(
      WorkspaceID.personal,
      BillingOwner.User(id = StableID.userAna, name = "Pessoal").workspaceID,
    )
    assertEquals(
      WorkspaceID(StableID.organizationHorizonte.rawValue),
      BillingOwner.Organization(
        id = StableID.organizationHorizonte,
        name = "Horizonte",
      ).workspaceID,
    )
  }

  @Test
  fun `form submit state admits one submission until it is finished`() {
    val idle = FormSubmitState.idle
    val submitting = idle.start()

    assertTrue(submitting.isSubmitting)
    assertEquals(submitting, submitting.start())
    assertEquals(idle, submitting.finish())
  }

  @Test
  fun `api key grant edit rule locks hidden grants and only marks visible changes`() {
    val original = setOf(WorkspaceID.personal)
    val hidden = APIKeyGrantEditRule(originalGrantIDs = original, unavailableGrantCount = 1)
    val visible = APIKeyGrantEditRule(originalGrantIDs = original, unavailableGrantCount = 0)

    assertFalse(hidden.canEdit)
    assertFalse(hidden.shouldUpdate(setOf(WorkspaceID("organization-1"))))
    assertTrue(visible.canEdit)
    assertFalse(visible.shouldUpdate(original))
    assertTrue(visible.shouldUpdate(setOf(WorkspaceID("organization-1"))))
  }

  @Test
  fun `api key name validation matches the 255 character API limit`() {
    assertEquals(null, APIKeyNameRule.validationMessage("a".repeat(255)))
    assertEquals("O nome deve ter no máximo 255 caracteres.", APIKeyNameRule.validationMessage("a".repeat(256)))
  }

  @Test
  fun `api key scope edit rule locks unknown scopes and only marks visible changes`() {
    val original = setOf(APIKeyScope.PROFILE_READ)
    val hidden = APIKeyScopeEditRule(originalScopes = original, unavailableScopeCount = 1)
    val visible = APIKeyScopeEditRule(originalScopes = original, unavailableScopeCount = 0)

    assertFalse(hidden.canEdit)
    assertFalse(hidden.shouldUpdate(setOf(APIKeyScope.BILLINGS_READ)))
    assertFalse(visible.shouldUpdate(original))
    assertTrue(visible.shouldUpdate(setOf(APIKeyScope.BILLINGS_READ)))
  }

  @Test
  fun `bill form rules keep unsupported create and edit fields read only`() {
    val create = BillFormEditRule(isEditing = false)
    val edit = BillFormEditRule(isEditing = true)

    assertTrue(create.canEditReferenceMonth)
    assertFalse(edit.canEditReferenceMonth)
    assertFalse(create.canEditDescription(BillLineItemKind.FIXED))
    assertFalse(create.canEditDescription(BillLineItemKind.VARIABLE))
    assertTrue(create.canEditDescription(BillLineItemKind.EXTRA))
    assertFalse(create.canEditAmount(BillLineItemKind.FIXED))
    assertTrue(create.canEditAmount(BillLineItemKind.VARIABLE))
    assertFalse(create.canDelete(BillLineItemKind.FIXED))
    assertFalse(create.canDelete(BillLineItemKind.VARIABLE))
    assertTrue(create.canDelete(BillLineItemKind.EXTRA))
  }

  @Test
  fun `expense form trims descriptions and enforces the API length`() {
    val valid = ExpenseFormInput(description = "  Troca de fechadura  ", centavos = 1_000)
    val blank = ExpenseFormInput(description = "   ", centavos = 1_000)
    val long = ExpenseFormInput(description = "a".repeat(2_001), centavos = 1_000)

    assertEquals("Troca de fechadura", valid.normalizedDescription)
    assertEquals(null, valid.validationMessage)
    assertEquals("Informe a descrição da despesa.", blank.validationMessage)
    assertEquals("A descrição deve ter no máximo 2000 caracteres.", long.validationMessage)
  }

  @Test
  fun `communication form enforces nonblank fields and UTF-8 byte body limit`() {
    val valid = CommunicationFormInput(subject = "  Fatura pronta  ", body = "á".repeat(2_048))
    val blank = CommunicationFormInput(subject = " ", body = "\n")
    val longSubject = CommunicationFormInput(subject = "a".repeat(999), body = "ok")
    val longBody = CommunicationFormInput(subject = "ok", body = "á".repeat(2_049))

    assertEquals("Fatura pronta", valid.normalizedSubject)
    assertEquals(4_096, valid.bodyUTF8ByteCount)
    assertEquals(null, valid.validationMessage)
    assertEquals("Informe o assunto.", blank.validationMessage)
    assertEquals("O assunto deve ter no máximo 998 caracteres.", longSubject.validationMessage)
    assertEquals("A mensagem deve ter no máximo 4096 bytes UTF-8.", longBody.validationMessage)
  }

  @Test
  fun `communication type options follow the per-document capabilities`() {
    val invoiceOnly = BillCapabilities.permissive.copy(canSendRecibo = false)
    val none = BillCapabilities.permissive.copy(canSendInvoice = false, canSendRecibo = false)

    assertEquals(listOf(CommunicationType.BILL_READY), communicationTypes(invoiceOnly))
    assertTrue(communicationTypes(none).isEmpty())
  }

  @Test
  fun `theme form requires strict hex colors and reports contrast warnings`() {
    assertTrue(ThemeFormRules.isHexColor("#Aa09Ff"))
    assertFalse(ThemeFormRules.isHexColor("Aa09Ff"))
    assertFalse(ThemeFormRules.isHexColor("#GG0000"))
    assertEquals(listOf("Primária"), ThemeFormRules.invalidColorNames(ThemeValues.rentivo.copy(primary = "#123")))

    val lowContrast = ThemeValues.rentivo.copy(
      primary = "#FFFFFF",
      textContrast = "#FFFFFF",
      primaryLight = "#000000",
      textColor = "#000000",
    )
    assertEquals(2, ThemeFormRules.contrastWarnings(lowContrast).size)
  }
}

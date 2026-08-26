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
  fun profilePixFormAllowsClearingOrSavingACompleteConfiguration() {
    val form = ProfilePIXForm.from()
    assertTrue(form.isSavable)

    form.key = "ana@example.com"
    assertFalse(form.isSavable)
    form.merchantName = "ANA"
    assertFalse(form.isSavable)
    form.merchantCity = "RECIFE"
    assertTrue(form.isSavable)

    form.merchantName = "N".repeat(256)
    assertFalse(form.isSavable)
    form.merchantName = "ANA"
    form.merchantCity = "C".repeat(256)
    assertFalse(form.isSavable)
  }

  @Test
  fun attachmentUploadRulesMirrorTheServerTypeAndSizeContract() {
    val valid = FileUpload(
      data = "pdf".toByteArray(),
      filename = "contrato.pdf",
      mediaType = "application/pdf",
    )
    assertEquals(valid, AttachmentUploadRules.validated(valid))
    assertEquals(10 * 1024 * 1024, AttachmentUploadRules.maximumByteCount)

    val unsupported = runCatching {
      AttachmentUploadRules.validated(
        FileUpload("texto".toByteArray(), "notas.txt", "text/plain")
      )
    }.exceptionOrNull()
    assertEquals(DemoError("Envie um arquivo PDF, JPEG ou PNG."), unsupported)

    val oversized = runCatching {
      AttachmentUploadRules.validated(
        FileUpload(
          ByteArray(AttachmentUploadRules.maximumByteCount + 1),
          "contrato.pdf",
          "application/pdf",
        )
      )
    }.exceptionOrNull()
    assertEquals(DemoError("O arquivo excede o limite de 10 MB."), oversized)

    val empty = runCatching {
      AttachmentUploadRules.validated(FileUpload(ByteArray(0), "contrato.pdf", "application/pdf"))
    }.exceptionOrNull()
    assertEquals(DemoError("O arquivo selecionado está vazio."), empty)
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
  fun onlyOrganizationsAllowedByTheApiCanOwnANewBilling() {
    val allowed = Organization(
      id = StableID.organizationHorizonte,
      name = "Horizonte",
      pix = null,
      members = emptyList(),
      requiresMFA = false,
      currentUserRole = OrganizationRole.VIEWER,
      capabilities = OrganizationCapabilities(
        canManage = false,
        canInvite = false,
        canCreateBilling = true,
        canViewBillingStats = false,
      ),
    )
    val denied = Organization(
      id = OrganizationID("organization-denied"),
      name = "Sem criação",
      pix = null,
      members = emptyList(),
      requiresMFA = false,
      currentUserRole = OrganizationRole.ADMIN,
      capabilities = OrganizationCapabilities(
        canManage = true,
        canInvite = true,
        canCreateBilling = false,
        canViewBillingStats = true,
      ),
    )

    assertEquals(
      BillingOwner.Organization(id = StableID.organizationHorizonte, name = "Horizonte"),
      allowed.billingOwnerForCreation,
    )
    assertNull(denied.billingOwnerForCreation)
  }

  @Test
  fun billingExportContractMatchesTheBackendJobPayload() {
    assertEquals(listOf("csv", "xlsx"), BillingExportContract.formats)
    assertEquals(listOf("Faturas"), BillingExportContract.includedSections)
  }

  @Test
  fun organizationNamesMirrorTheServerContract() {
    assertFalse(OrganizationDraft(name = "   ", pix = null).isValid)
    assertTrue(OrganizationDraft(name = "😀".repeat(255), pix = null).isValid)
    assertFalse(OrganizationDraft(name = "😀".repeat(256), pix = null).isValid)
    assertEquals(255, OrganizationDraft.nameLimit)
  }

  @Test
  fun organizationPIXFieldsMirrorTheServerCharacterLimits() {
    val combiningCharacter = "e\u0301"
    assertNull(
      OrganizationDraft.pixValidationMessage(
        key = "pix",
        merchantName = "😀".repeat(255),
        city = "😀".repeat(255),
      ),
    )
    assertEquals(
      "O nome do recebedor deve ter até 255 caracteres.",
      OrganizationDraft.pixValidationMessage(
        key = "pix",
        merchantName = combiningCharacter.repeat(128),
        city = "RECIFE",
      ),
    )
    assertEquals(
      "A cidade do recebedor deve ter até 255 caracteres.",
      OrganizationDraft.pixValidationMessage(
        key = "pix",
        merchantName = "ANA",
        city = combiningCharacter.repeat(128),
      ),
    )
    assertFalse(
      OrganizationDraft(
        name = "Imobiliária",
        pix = PixConfiguration(
          key = "pix",
          merchantName = combiningCharacter.repeat(128),
          merchantCity = "RECIFE",
        ),
      ).isValid,
    )
    assertEquals(
      "Informe a chave, o nome e a cidade do recebedor para usar uma chave PIX.",
      OrganizationDraft.pixValidationMessage(
        key = "",
        merchantName = "ANA",
        city = "RECIFE",
      ),
    )
  }

  @Test
  fun organizationInviteEmailsMirrorTheServerContract() {
    assertEquals("ana@example.com", OrganizationInviteEmail.normalized("  ANA@EXAMPLE.COM\n"))
    assertTrue(OrganizationInviteEmail.isValid("a@b"))
    assertTrue(OrganizationInviteEmail.isValid("😀".repeat(318) + "@a"))
    assertFalse(OrganizationInviteEmail.isValid(""))
    assertFalse(OrganizationInviteEmail.isValid("ana"))
    assertFalse(OrganizationInviteEmail.isValid("a@@b"))
    assertFalse(OrganizationInviteEmail.isValid("@example.com"))
    assertFalse(OrganizationInviteEmail.isValid("ana@"))
    assertFalse(OrganizationInviteEmail.isValid("ana @example.com"))
    assertFalse(OrganizationInviteEmail.isValid("😀".repeat(319) + "@a"))
    assertEquals(320, OrganizationInviteEmail.maximumLength)
  }
}

package app.rentivo.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

private fun makeBill(
  status: BillStatus = BillStatus.DRAFT,
  availableTransitions: List<BillStatus>? = null,
  serverTotal: Money? = null,
): Bill = Bill(
  id = StableID.billDraft,
  billingID = StableID.billingAurora101,
  referenceMonth = ReferenceMonth(year = 2026, month = 7),
  dueDate = DateOnly(year = 2026, month = 7, day = 10),
  paidAt = null,
  notes = "",
  status = status,
  lineItems = listOf(
    BillLineItem.generated(
      description = "Aluguel",
      amount = Money(centavos = 180_000),
      kind = BillLineItemKind.FIXED,
    )
  ),
  receipts = emptyList(),
  availableTransitions = availableTransitions,
  serverTotal = serverTotal,
)

class BillLifecycleTest {
  @Test
  fun `only transferable personal billings can be moved into an organization`() {
    val transferable = Billing(
      id = BillingID("transferable"), name = "Pessoal", description = "",
      owner = BillingOwner.User(id = 7, name = "Pessoal"), items = emptyList(),
      capabilities = BillingCapabilities.full,
    )
    val denied = transferable.copy(id = BillingID("denied"), capabilities = BillingCapabilities.viewer)
    val organizationOwned = transferable.copy(
      id = BillingID("organization"),
      owner = BillingOwner.Organization(id = OrganizationID("org-1"), name = "Organização"),
    )

    assertTrue(transferable.canTransferToOrganization)
    assertFalse(denied.canTransferToOrganization)
    assertFalse(organizationOwned.canTransferToOrganization)
  }


  @Test
  fun draftCanPublishButCannotBecomeDelayedDirectly() {
    assertTrue(BillStatus.DRAFT.canTransition(BillStatus.PUBLISHED))
    assertTrue(BillStatus.DRAFT.canTransition(BillStatus.CANCELLED))
    assertFalse(BillStatus.DRAFT.canTransition(BillStatus.DELAYED_PAYMENT))
  }

  @Test
  fun paidAndCancelledBillsAreTerminal() {
    assertTrue(BillStatus.PAID.allowedTransitions.isEmpty())
    assertTrue(BillStatus.CANCELLED.allowedTransitions.isEmpty())
  }

  @Test
  fun billStatusesKeepAPIValuesAndPortugueseLabels() {
    assertEquals("delayed_payment", BillStatus.DELAYED_PAYMENT.wire)
    assertEquals("Pagamento atrasado", BillStatus.DELAYED_PAYMENT.label)
    assertEquals("Publicada", BillStatus.PUBLISHED.label)
  }

  @Test
  fun viewerCapabilitiesAreReadOnly() {
    assertTrue(BillingCapabilities.viewer.canReadBills)
    assertTrue(BillingCapabilities.viewer.canReadExpenses)
    assertFalse(BillingCapabilities.viewer.canEdit)
    assertFalse(BillingCapabilities.viewer.canDelete)
    assertFalse(BillingCapabilities.viewer.canWriteExpenses)
    assertFalse(BillingCapabilities.viewer.allowsEveryAction)
  }

  @Test
  fun fullCapabilitiesExposeEveryBillingAction() {
    assertTrue(BillingCapabilities.full.allowsEveryAction)
  }

  @Test
  fun billTotalIsDerivedFromLineItems() {
    val bill = Bill(
      id = StableID.billPaid,
      billingID = StableID.billingAurora101,
      referenceMonth = ReferenceMonth(year = 2026, month = 7),
      dueDate = DateOnly(year = 2026, month = 7, day = 10),
      paidAt = DateOnly(year = 2026, month = 7, day = 8),
      notes = "",
      status = BillStatus.PAID,
      lineItems = listOf(
        BillLineItem.generated(
          description = "Aluguel",
          amount = Money(centavos = 180_000),
          kind = BillLineItemKind.FIXED,
        ),
        BillLineItem.generated(
          description = "Água",
          amount = Money(centavos = 12_340),
          kind = BillLineItemKind.VARIABLE,
        ),
        BillLineItem.generated(
          description = "Pintura",
          amount = Money(centavos = 5_000),
          kind = BillLineItemKind.EXTRA,
        ),
      ),
      receipts = emptyList(),
    )

    assertEquals(Money(centavos = 197_340), bill.total)
  }

  @Test
  fun dateAndReferenceMonthHaveStableAPIRepresentations() {
    assertEquals("2026-07-09", DateOnly(year = 2026, month = 7, day = 9).iso8601)
    assertEquals("2026-07", ReferenceMonth(year = 2026, month = 7).apiValue)
    assertEquals("julho de 2026", ReferenceMonth(year = 2026, month = 7).label)
  }

  @Test
  fun integrationScopesExcludePrivilegedAccountOperations() {
    assertTrue(APIKeyScope.integrationCases.contains(APIKeyScope.BILLINGS_READ))
    assertTrue(APIKeyScope.integrationCases.contains(APIKeyScope.COMMUNICATIONS_SEND))
    assertFalse(APIKeyScope.integrationCases.contains(APIKeyScope.SECURITY_MANAGE))
    assertFalse(APIKeyScope.integrationCases.contains(APIKeyScope.API_KEYS_MANAGE))
  }

  @Test
  fun apiKeyOptionsApplyServerExpirationLimitsAndValidateNames() {
    val now = Instant.ofEpochSecond(1_700_000_000L)
    val options = APIKeyOptions(
      scopes = listOf(APIKeyScope.PROFILE_READ),
      personalWorkspace = APIKeyWorkspaceOption(
        resourceType = WorkspaceResourceType.USER,
        resourceID = WorkspaceID.personal,
        name = "Conta pessoal",
      ),
      organizations = emptyList(),
      defaultExpirationDays = 30,
      maxExpirationDays = 180,
    )

    assertEquals(now.plusSeconds(30 * 86_400L), options.defaultExpiration(now))
    assertEquals(now.plusSeconds(180 * 86_400L - 60), options.maximumExpiration(now))
    assertEquals(now.plusSeconds(60), options.clampedExpiration(now, now))
    assertEquals(
      options.maximumExpiration(now),
      options.clampedExpiration(now.plusSeconds(365 * 86_400L), now),
    )
    assertTrue(APIKeyValidation.isValidName(" CRM "))
    assertFalse(APIKeyValidation.isValidName("   "))
    assertFalse(APIKeyValidation.isValidName("a".repeat(256)))
    assertTrue(APIKeyValidation.isValidName("😀".repeat(255)))
    assertFalse(APIKeyValidation.isValidName("😀".repeat(256)))
    assertFalse(APIKeyValidation.isValidName("e\u0301".repeat(128)))
  }

  @Test
  fun apiEnumsPreserveRawValues() {
    assertEquals("manutencao", ExpenseCategory.MAINTENANCE.wire)
    assertEquals("viewer", OrganizationRole.VIEWER.wire)
    assertEquals("organization", ThemeSource.ORGANIZATION.wire)
    assertEquals("default", ThemeSource.DEFAULT.wire)
    assertEquals("profile:read", APIKeyScope.PROFILE_READ.wire)
    assertEquals("Playfair Display", ThemeFont.PLAYFAIR_DISPLAY.wire)
    assertEquals("api_key", ActivityKind.API_KEY.wire)
  }

  @Test
  fun organizationRoleMatchesTheServerContractExactly() {
    // OrganizationMemberUpdateRequest.role and every invite/member response enum in the OpenAPI
    // contract only ever accept admin/manager/viewer — there is no "owner" concept on the wire.
    assertEquals(
      setOf(OrganizationRole.ADMIN, OrganizationRole.MANAGER, OrganizationRole.VIEWER),
      OrganizationRole.entries.toSet(),
    )
  }

  @Test
  fun organizationRoleForRoleGrantsFullCapabilitiesToAdmin() {
    assertEquals(
      OrganizationCapabilities.full,
      OrganizationCapabilities.forRole(OrganizationRole.ADMIN),
    )
    assertEquals(
      OrganizationCapabilities.manager,
      OrganizationCapabilities.forRole(OrganizationRole.MANAGER),
    )
    assertEquals(
      OrganizationCapabilities.viewer,
      OrganizationCapabilities.forRole(OrganizationRole.VIEWER),
    )
  }

  @Test
  fun billFallsBackToLocalTransitionRulesWhenServerOmitsThem() {
    val bill = makeBill(status = BillStatus.DRAFT)
    assertEquals(BillStatus.DRAFT.allowedTransitions, bill.effectiveTransitions)
    assertTrue(bill.canTransition(BillStatus.PUBLISHED))
    assertFalse(bill.canTransition(BillStatus.DELAYED_PAYMENT))
  }

  @Test
  fun billPrefersServerSuppliedTransitionsWhenPresent() {
    // Even though the local state machine would allow draft -> published, the server can restrict
    // this specific bill further (or further loosen it).
    val bill = makeBill(
      status = BillStatus.DRAFT,
      availableTransitions = listOf(BillStatus.CANCELLED),
    )
    assertEquals(setOf(BillStatus.CANCELLED), bill.effectiveTransitions)
    assertTrue(bill.canTransition(BillStatus.CANCELLED))
    assertFalse(bill.canTransition(BillStatus.PUBLISHED))
  }

  @Test
  fun billFallbackTransitionActionsConfirmConsequentialChanges() {
    val bill = makeBill(
      status = BillStatus.SENT,
      availableTransitions = listOf(BillStatus.PAID, BillStatus.DELAYED_PAYMENT),
    )

    assertTrue(bill.effectiveTransitionActions.first { it.target == BillStatus.PAID }
      .requiresConfirmation)
    assertEquals(
      "primary",
      bill.effectiveTransitionActions.first { it.target == BillStatus.PAID }.style,
    )
    assertFalse(bill.effectiveTransitionActions.first { it.target == BillStatus.DELAYED_PAYMENT }
      .requiresConfirmation)
  }

  @Test
  fun billTreatsAnEmptyServerTransitionListAsAuthoritative() {
    val bill = makeBill(status = BillStatus.DRAFT, availableTransitions = emptyList())
    assertTrue(bill.effectiveTransitions.isEmpty())
    assertFalse(bill.canTransition(BillStatus.PUBLISHED))
  }

  @Test
  fun billFallsBackToComputedTotalWhenServerOmitsIt() {
    val bill = makeBill()
    assertEquals(bill.total, bill.effectiveTotal)
    assertEquals(Money(centavos = 180_000), bill.effectiveTotal)
  }

  @Test
  fun billPrefersServerSuppliedTotalWhenPresent() {
    val bill = makeBill(serverTotal = Money(centavos = 99_900))
    assertEquals(Money(centavos = 99_900), bill.effectiveTotal)
    assertEquals(Money(centavos = 180_000), bill.total)
  }

  @Test
  fun renderingBillsArePolledUntilTheServerSettles() {
    assertEquals(3_000L, BillPDFPolling.INTERVAL_MILLIS)
    assertFalse(BillPDFPolling.shouldPoll(null))
    assertFalse(BillPDFPolling.shouldPoll(makeBill()))
    assertTrue(
      BillPDFPolling.shouldPoll(makeBill().copy(pdfRenderStatus = PDFRenderStatus.PENDING))
    )
    assertFalse(
      BillPDFPolling.shouldPoll(makeBill().copy(pdfRenderStatus = PDFRenderStatus.SUCCEEDED))
    )
    assertFalse(
      BillPDFPolling.shouldPoll(makeBill().copy(pdfRenderStatus = PDFRenderStatus.FAILED))
    )
  }

  @Test
  fun applyingRenderMetadataMergesOnlyTheSummaryFields() {
    // `POST .../regenerate` answers with the summary shape, which carries no receipts at all, so
    // replacing the loaded bill with it would empty the receipt list until the next poll tick.
    val loaded = makeBill(status = BillStatus.PUBLISHED).copy(
      receipts = listOf(Receipt(id = ReceiptID("r1"), name = "comprovante.pdf", sortOrder = 0)),
      notes = "Notas carregadas",
      pdfRenderStatus = PDFRenderStatus.SUCCEEDED,
      hasInvoice = true,
      hasRecibo = true,
      capabilities = BillCapabilities.permissive,
      serverTotal = Money(centavos = 99_900),
    )
    val summary = Bill(
      id = loaded.id,
      billingID = loaded.billingID,
      referenceMonth = ReferenceMonth(year = 2030, month = 1),
      dueDate = null,
      paidAt = null,
      notes = "",
      status = BillStatus.SENT,
      lineItems = emptyList(),
      receipts = emptyList(),
      availableTransitions = listOf(BillStatus.PAID),
      serverTotal = null,
      pdfRenderStatus = PDFRenderStatus.PENDING,
      hasInvoice = false,
      hasRecibo = false,
      capabilities = BillCapabilities(
        canDownloadInvoice = false,
        canDownloadRecibo = false,
        canSendInvoice = false,
        canSendRecibo = false,
        canRegenerate = false,
      ),
    )

    val merged = loaded.applyingRenderMetadata(summary)

    // Taken from the summary.
    assertEquals(PDFRenderStatus.PENDING, merged.pdfRenderStatus)
    assertEquals(summary.capabilities, merged.capabilities)
    assertFalse(merged.hasInvoice)
    assertFalse(merged.hasRecibo)
    assertEquals(BillStatus.SENT, merged.status)
    assertEquals(listOf(BillStatus.PAID), merged.availableTransitions)
    // Kept from the loaded detail.
    assertEquals(loaded.receipts, merged.receipts)
    assertEquals(loaded.lineItems, merged.lineItems)
    assertEquals(loaded.notes, merged.notes)
    assertEquals(loaded.referenceMonth, merged.referenceMonth)
    assertEquals(loaded.dueDate, merged.dueDate)
    assertEquals(loaded.serverTotal, merged.serverTotal)
  }
}

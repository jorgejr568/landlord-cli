package app.rentivo.data

import app.rentivo.domain.APIKeyDraft
import app.rentivo.domain.APIKeyGrant
import app.rentivo.domain.APIKeyScope
import app.rentivo.domain.ActivityKind
import app.rentivo.domain.BillCapabilities
import app.rentivo.domain.BillStatus
import app.rentivo.domain.BillingCapabilities
import app.rentivo.domain.BillingDraft
import app.rentivo.domain.BillingOwner
import app.rentivo.domain.CommunicationType
import app.rentivo.domain.DateOnly
import app.rentivo.domain.DemoError
import app.rentivo.domain.ExpenseCategory
import app.rentivo.domain.MobileLoginOutcome
import app.rentivo.domain.Money
import app.rentivo.domain.OrganizationRole
import app.rentivo.domain.PDFRenderStatus
import app.rentivo.domain.PixConfiguration
import app.rentivo.domain.RecipientID
import app.rentivo.domain.StableID
import app.rentivo.domain.ThemeSource
import app.rentivo.domain.ThemeTarget
import app.rentivo.domain.ThemeValues
import app.rentivo.domain.WorkspaceID
import app.rentivo.domain.WorkspaceResourceType
import java.time.Instant
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs [block] and answers the [DemoError] it must throw. */
private suspend fun assertDemoError(block: suspend () -> Unit): DemoError {
  try {
    block()
  } catch (error: DemoError) {
    return error
  }
  throw AssertionError("Expected the operation to throw a DemoError")
}

class MockRentivoStoreTest {

  @Test
  fun canonicalFixturesCoverEveryInvoiceStatus() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val billings = store.listBillings()
    val bills = billings.flatMap { store.listBills(billingID = it.id) }

    assertEquals(6, billings.size)
    assertEquals(BillStatus.entries.toSet(), bills.map { it.status }.toSet())
  }

  @Test
  fun addingExpenseUpdatesDashboardNetIncome() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val before = store.dashboardSummary()

    store.createExpense(
      billingID = StableID.billingAurora101,
      description = "Manutenção",
      category = ExpenseCategory.MAINTENANCE,
      incurredOn = DateOnly(year = 2026, month = 7, day = 20),
      amount = Money(centavos = 25_000),
    )

    val after = store.dashboardSummary()
    assertEquals(before.expenses + Money(centavos = 25_000), after.expenses)
    assertEquals(before.netIncome - Money(centavos = 25_000), after.netIncome)
  }

  @Test
  fun invalidTransitionDoesNotMutateBill() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)

    val error = assertDemoError {
      store.transitionBill(
        billingID = StableID.billingAurora101,
        billID = StableID.billDraft,
        status = BillStatus.DELAYED_PAYMENT,
      )
    }
    assertEquals(DemoError.invalidBillTransition, error)

    val bill = store.bill(billingID = StableID.billingAurora101, id = StableID.billDraft)
    assertEquals(BillStatus.DRAFT, bill.status)
  }

  @Test
  fun validTransitionMutatesSharedBill() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)

    store.transitionBill(
      billingID = StableID.billingAurora101,
      billID = StableID.billDraft,
      status = BillStatus.PUBLISHED,
    )

    val bill = store.bill(billingID = StableID.billingAurora101, id = StableID.billDraft)
    assertEquals(BillStatus.PUBLISHED, bill.status)
    assertEquals(ActivityKind.BILL, store.recentActivities.first().kind)
  }

  @Test
  fun injectedFailureIsConsumedByOneOperation() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    store.failNextOperation()

    val error = assertDemoError { store.listBillings() }
    assertEquals(DemoError.operationFailed, error)

    assertEquals(6, store.listBillings().size)
  }

  @Test
  fun emptyModeChangesReadsWithoutDestroyingSnapshot() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val canonical = store.snapshot
    store.setEmptyMode(true)

    assertTrue(store.listBillings().isEmpty())
    assertEquals(canonical, store.snapshot)

    store.setEmptyMode(false)
    assertEquals(6, store.listBillings().size)
  }

  @Test
  fun viewerModeRestrictsCapabilitiesWithoutChangingOwnership() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val original = store.listBillings().first()
    store.setViewerMode(true)
    val restricted = store.listBillings().first()

    assertEquals(original.id, restricted.id)
    assertEquals(original.owner, restricted.owner)
    assertEquals(BillingCapabilities.viewer, restricted.capabilities)
  }

  @Test
  fun viewerModeRestrictsOrganizationManagementCapabilities() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    store.setViewerMode(true)

    val organization = store.organization(id = StableID.organizationHorizonte)

    assertEquals(OrganizationRole.VIEWER, organization.currentUserRole)
    assertFalse(organization.capabilities.canManage)
    assertFalse(organization.capabilities.canInvite)
    assertFalse(organization.capabilities.canCreateBilling)
    assertTrue(organization.capabilities.canViewBillingStats)
  }

  @Test
  fun acceptingInvitationCreatesMembershipAndClearsPendingCount() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val invitation = store.listPendingInvitations().first()

    store.acceptInvitation(id = invitation.id)

    assertTrue(store.listPendingInvitations().isEmpty())
    val organization = store.organization(id = invitation.organizationID)
    assertTrue(organization.members.any { it.userID == store.currentUser.id })
  }

  @Test
  fun acceptedManagerCannotMutateOrganizationPolicy() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val invitation = store.listPendingInvitations().first()
    store.acceptInvitation(id = invitation.id)

    val error = assertDemoError {
      store.setOrganizationMFA(organizationID = invitation.organizationID, required = true)
    }
    assertEquals(DemoError.permissionDenied, error)
  }

  @Test
  fun acceptedManagerCannotInviteOrganizationMembers() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val invitation = store.listPendingInvitations().first()
    store.acceptInvitation(id = invitation.id)

    val error = assertDemoError {
      store.inviteMember(
        organizationID = invitation.organizationID,
        email = "novo-membro@rentivo.com.br",
        role = OrganizationRole.VIEWER,
      )
    }

    assertEquals(DemoError.permissionDenied, error)
  }

  @Test
  fun acceptedManagerCannotMutateOrganizationTheme() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val invitation = store.listPendingInvitations().first()
    store.acceptInvitation(id = invitation.id)
    val target = ThemeTarget.Organization(invitation.organizationID)

    assertFalse(store.theme(target = target).canEdit)

    val error = assertDemoError {
      store.updateTheme(target = target, values = ThemeValues.sunset)
    }
    assertEquals(DemoError.permissionDenied, error)
  }

  @Test
  fun resetRestoresCanonicalSnapshotAndBehavior() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    store.createExpense(
      billingID = StableID.billingAurora101,
      description = "Pintura",
      category = ExpenseCategory.MAINTENANCE,
      incurredOn = DateOnly(year = 2026, month = 7, day = 20),
      amount = Money(centavos = 10_000),
    )
    store.setEmptyMode(true)
    store.setViewerMode(true)

    store.reset()

    assertEquals(MockFixtures.canonical.snapshot, store.snapshot)
    assertEquals(6, store.listBillings().size)
    assertEquals(BillingCapabilities.full, store.listBillings().first().capabilities)
  }

  @Test
  fun receiptOrderPersists() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val bill = store.bill(billingID = StableID.billingAurora101, id = StableID.billPaid)
    val reversed = bill.receipts.map { it.id }.reversed()

    store.reorderReceipts(billingID = bill.billingID, billID = bill.id, receiptIDs = reversed)

    val updated = store.bill(billingID = bill.billingID, id = bill.id)
    assertEquals(2, bill.receipts.size)
    assertEquals(reversed, updated.receipts.map { it.id })
  }

  @Test
  fun communicationMutationUsesSharedActivityGraph() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val billing = store.billing(id = StableID.billingAurora101)
    val recipientIDs = billing.recipients.map { it.id }
    // The fixture must exercise the multi-recipient path.
    assertTrue(recipientIDs.size >= 2)

    val queued = store.sendCommunication(
      billingID = StableID.billingAurora101,
      billID = StableID.billPublished,
      commType = CommunicationType.BILL_READY,
      recipientIDs = recipientIDs,
      subject = "Sua fatura está disponível",
      message = "Olá! Consulte os detalhes no Rentivo.",
      acknowledgeWarning = false,
      saveScope = null,
    )

    assertEquals(recipientIDs.size, queued)
    val record = store.snapshot.communications.first()
    assertEquals(billing.recipients.map { it.email }.toSet(), record.recipients.toSet())
    assertEquals(record.subject, store.recentActivities.first().detail)
  }

  @Test
  fun canonicalFixtureBillingsCarryATemplateForEveryCommType() = runTest {
    // The composer prefills subject/body from the billing templates, so demo mode only
    // matches production when the fixtures ship templates for every communication type.
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)

    for (billing in store.listBillings()) {
      for (commType in CommunicationType.entries) {
        val template = billing.template(commType)
        assertNotNull(template)
        assertTrue(template!!.subject.isNotEmpty())
        assertTrue(template.body.contains("{{nome_inquilino}}"))
      }
    }
  }

  @Test
  fun creatingABillingAttachesTheDefaultCommunicationTemplates() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)

    val created = store.createBilling(
      BillingDraft(
        name = "Apt 999 - Edifício Novo",
        description = "Cobrança recém-criada",
        owner = BillingOwner.User(id = StableID.userAna, name = "Pessoal"),
        items = emptyList(),
      )
    )

    assertEquals(MockFixtures.defaultCommunicationTemplates, created.communicationTemplates)
    val stored = store.billing(id = created.id)
    assertEquals(MockFixtures.defaultCommunicationTemplates, stored.communicationTemplates)
  }

  @Test
  fun updatingABillingKeepsItsCommunicationTemplates() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val billing = store.billing(id = StableID.billingAurora101)
    val draft = BillingDraft(
      name = "Apt 101 - Edifício Aurora (renomeado)",
      description = billing.description,
      owner = billing.owner,
      items = billing.items,
      recipients = billing.recipients,
      replyTo = billing.replyTo,
    )

    val updated = store.updateBilling(id = billing.id, draft = draft)

    assertTrue(billing.communicationTemplates.isNotEmpty())
    assertEquals(billing.communicationTemplates, updated.communicationTemplates)
    val stored = store.billing(id = billing.id)
    assertEquals(billing.communicationTemplates, stored.communicationTemplates)
  }

  @Test
  fun sendingToASubsetQueuesOnlyTheSelectedRecipient() = runTest {
    // The composer lets the user deselect recipients, so a partial selection must queue exactly
    // the chosen ones instead of falling back to the whole billing.
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val billing = store.billing(id = StableID.billingAurora101)
    assertTrue(billing.recipients.size >= 2)
    val selected = billing.recipients.last()

    val queued = store.sendCommunication(
      billingID = billing.id,
      billID = StableID.billPublished,
      commType = CommunicationType.BILL_READY,
      recipientIDs = listOf(selected.id),
      subject = "Sua fatura está disponível",
      message = "Olá! Consulte os detalhes no Rentivo.",
      acknowledgeWarning = false,
      saveScope = null,
    )

    assertEquals(1, queued)
    val record = store.snapshot.communications.first()
    assertEquals(listOf(selected.email), record.recipients)
  }

  @Test
  fun sendingToARecipientOutsideTheBillingFails() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)

    assertDemoError {
      store.sendCommunication(
        billingID = StableID.billingAurora101,
        billID = StableID.billPublished,
        commType = CommunicationType.BILL_READY,
        recipientIDs = listOf(RecipientID(rawValue = "not-a-recipient")),
        subject = "Assunto",
        message = "Corpo",
        acknowledgeWarning = false,
        saveScope = null,
      )
    }
  }

  @Test
  fun creatingExpenseRejectsZeroOrNegativeAmounts() = runTest {
    // Matches the server contract: `ExpenseCreateRequest.amount` requires `exclusiveMinimum: 0`.
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)

    val zero = assertDemoError {
      store.createExpense(
        billingID = StableID.billingAurora101,
        description = "Reparo",
        category = ExpenseCategory.MAINTENANCE,
        incurredOn = DateOnly(year = 2026, month = 7, day = 20),
        amount = Money.zero,
      )
    }
    assertEquals(DemoError.invalidAmount, zero)

    val negative = assertDemoError {
      store.createExpense(
        billingID = StableID.billingAurora101,
        description = "Reparo",
        category = ExpenseCategory.MAINTENANCE,
        incurredOn = DateOnly(year = 2026, month = 7, day = 20),
        amount = Money(centavos = -100),
      )
    }
    assertEquals(DemoError.invalidAmount, negative)
  }

  @Test
  fun deletingExpenseUpdatesDashboard() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val expense = store.listExpenses(billingID = StableID.billingAurora101).first()
    val before = store.dashboardSummary()

    store.deleteExpense(billingID = expense.billingID, expenseID = expense.id)

    val after = store.dashboardSummary()
    assertEquals(before.expenses - expense.amount, after.expenses)
    assertEquals(before.netIncome + expense.amount, after.netIncome)
  }

  @Test
  fun transferringBillingChangesOwnerAcrossRepositoryReads() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)

    store.transferBilling(
      billingID = StableID.billingAurora101,
      toOrganizationID = StableID.organizationHorizonte,
    )

    val billing = store.billing(id = StableID.billingAurora101)
    assertEquals(
      StableID.organizationHorizonte.rawValue,
      billing.owner.workspaceID.rawValue,
    )
    assertTrue(billing.owner.isOrganization)
  }

  @Test
  fun memberRoleAndMFAPolicyMutationsPersist() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val organization = store.organization(id = StableID.organizationHorizonte)
    val member = organization.members.first { it.role == OrganizationRole.VIEWER }

    store.updateMemberRole(
      organizationID = organization.id,
      userID = member.userID,
      role = OrganizationRole.MANAGER,
    )
    store.setOrganizationMFA(organizationID = organization.id, required = false)

    val updated = store.organization(id = organization.id)
    assertEquals(
      OrganizationRole.MANAGER,
      updated.members.first { it.userID == member.userID }.role,
    )
    assertFalse(updated.requiresMFA)
  }

  @Test
  fun mfaPolicyReportsWhenTheCurrentUserNeedsEnrollment() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val organization = store.organization(id = StableID.organizationHorizonte)
    store.setOrganizationMFA(organizationID = organization.id, required = false)
    store.disableTOTP(password = "senha-valida")
    store.securitySummary().passkeys.forEach { store.deletePasskey(id = it.id) }

    val policy = store.setOrganizationMFA(
      organizationID = organization.id,
      required = true,
    )

    assertTrue(policy.enforceMFA)
    assertTrue(policy.mfaSetupRequired)
    val summary = store.securitySummary()
    assertTrue(summary.organizationEnforced)
    assertTrue(summary.setupRequired)
  }

  @Test
  fun enforcedOrganizationProtectsTheLastMfaFactor() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    store.disableTOTP(password = "senha-valida")
    val passkey = store.securitySummary().passkeys.first()

    assertEquals(
      DemoError.permissionDenied,
      runCatching { store.deletePasskey(id = passkey.id) }.exceptionOrNull(),
    )
  }

  @Test
  fun memberRoleCanBePromotedToAdmin() = runTest {
    // Regression coverage for the role picker bug: promoting a member to admin must be a
    // supported mutation (the API accepts admin/manager/viewer).
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val organization = store.organization(id = StableID.organizationHorizonte)
    val member = organization.members.first { it.role == OrganizationRole.MANAGER }

    store.updateMemberRole(
      organizationID = organization.id,
      userID = member.userID,
      role = OrganizationRole.ADMIN,
    )

    val updated = store.organization(id = organization.id)
    assertEquals(OrganizationRole.ADMIN, updated.members.first { it.userID == member.userID }.role)
  }

  @Test
  fun createdKeySecretIsSeparateFromMetadata() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)

    val created = store.createAPIKey(APIKeyDraft.demo)
    val metadata = store.listAPIKeys()

    assertTrue(created.secret.startsWith("rntv-v1-"))
    assertTrue(metadata.any { it.id == created.metadata.id })
    assertFalse(metadata.toString().contains(created.secret))
  }

  @Test
  fun clearingProfilePIXRemovesTheConfiguration() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)

    val profile = store.updatePix(PixConfiguration(key = "", merchantName = "", merchantCity = ""))

    assertNull(profile.pix)
    assertNull(store.profile().pix)
  }

  @Test
  fun revokedAPIKeyRemainsInHistoryAndCannotBeRevokedAgain() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val key = store.listAPIKeys().first()

    store.revokeAPIKey(key.id)

    val revoked = store.listAPIKeys().first { it.id == key.id }
    assertNotNull(revoked.revokedAt)
    assertEquals(
      DemoError.resourceNotFound,
      runCatching { store.revokeAPIKey(key.id) }.exceptionOrNull(),
    )
  }

  @Test
  fun apiKeyMetadataCanBeUpdatedWithoutRotatingSecret() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val key = store.listAPIKeys().first()
    val updatedDraft = APIKeyDraft(
      name = "Integração contábil",
      scopes = setOf(APIKeyScope.PROFILE_READ, APIKeyScope.EXPENSES_READ),
      grants = listOf(
        APIKeyGrant(
          resourceType = WorkspaceResourceType.USER,
          resourceID = WorkspaceID.personal,
        )
      ),
      expiresAt = Instant.ofEpochSecond(1_830_297_600L),
    )

    val updated = store.updateAPIKey(id = key.id, draft = updatedDraft)

    assertEquals(key.id, updated.id)
    assertEquals(key.hint, updated.hint)
    assertEquals(updatedDraft.name, updated.name)
    assertEquals(updatedDraft.scopes, updated.scopes)
    assertEquals(updatedDraft.grants, updated.grants)
    // PATCH does not accept `expires_at`; metadata edits must preserve the issued expiry.
    assertEquals(key.expiresAt, updated.expiresAt)
  }

  @Test
  fun apiKeyUpdateKeepsGrantsWhenTheFormDidNotChangeAccess() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val key = store.listAPIKeys().first()
    val draft = APIKeyDraft(
      name = "Somente nome",
      scopes = key.scopes,
      grants = emptyList(),
      expiresAt = key.expiresAt,
    )

    val updated = store.updateAPIKey(
      id = key.id,
      draft = draft,
      updateGrants = false,
    )

    assertEquals(key.grants, updated.grants)
  }

  @Test
  fun demoSettingsAreAuthoritativeAndResetTogether() {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)

    store.setDelayEnabled(true)
    store.setEmptyMode(true)
    store.setViewerMode(true)

    assertEquals(
      DemoSettings(delayEnabled = true, emptyMode = true, viewerMode = true),
      store.demoSettings,
    )

    store.reset()
    assertEquals(DemoSettings.standard, store.demoSettings)
  }

  @Test
  fun appDependenciesExposeFocusedRepositoryBoundary() {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val dependencies = mockDependencies(store = store)

    assertSame(store, dependencies.auth)
    assertSame(store, dependencies.billings)
    assertSame(store, dependencies.bills)
    assertSame(store, dependencies.organizations)
    assertSame(store, dependencies.demo)
  }

  @Test
  fun themeResetRestoresUserInheritance() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val target = ThemeTarget.Billing(StableID.billingAurora101)

    store.updateTheme(target = target, values = ThemeValues.sunset)
    store.resetTheme(target = target)

    val theme = store.theme(target = target)
    assertNull(theme.stored)
    assertEquals(ThemeSource.USER, theme.effectiveSource)
    assertEquals(ThemeValues.rentivo, theme.effective)
  }

  @Test
  fun securityMutationsUpdateTOTPAndRecoveryCodes() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)

    // The TOTP flag is only reachable through the enrollment/disable pair, which is how the
    // security screen drives it.
    val enrollmentCodes = store.confirmTOTPEnrollment(code = "123456")
    assertEquals(8, enrollmentCodes.size)
    assertTrue(store.securitySummary().totpEnabled)

    store.disableTOTP(password = "senha-de-demonstração")

    val summary = store.securitySummary()
    assertFalse(summary.totpEnabled)
    assertEquals(0, summary.recoveryCodeCount)
    assertEquals(
      DemoError.operationFailed,
      runCatching { store.regenerateRecoveryCodes() }.exceptionOrNull(),
    )
  }

  @Test
  fun demoStoreReportsNoLiveSessionToRestoreRevokeOrDelete() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)

    assertFalse(store.usesLiveAPI)
    assertNull(store.restoreSession())
    // Nothing to revoke or delete server-side; the demo data must survive both untouched.
    store.logout()
    store.deleteAccount(password = "senha-de-demonstração")
    assertEquals(store.snapshot.profile, store.currentUser)

    // Native sign-in always succeeds immediately as the demo user and never asks for a factor.
    val outcome = store.mobileLogin(email = "ana@demo.com.br", password = "irrelevante")
    assertEquals(MobileLoginOutcome.Authenticated(store.snapshot.profile), outcome)
    assertEquals(store.snapshot.profile, store.mobileSignup(email = "ana@demo.com.br", password = "x"))
  }

  @Test
  fun mockPreviewFlagsTermsTakenFromTheServerModerationLexicon() = runTest {
    // The demo lexicon is a strict subset of the server's, so anything flagged here is also
    // flagged by backend/rentivo/communications/moderation.py — demo mode never warns about
    // text production accepts.
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)

    val clean = store.previewCommunication(
      billingID = StableID.billingAurora101,
      subject = "Fatura",
      message = "Olá {{nome_inquilino}}",
    )
    assertTrue(clean.mildWarnings.isEmpty())
    assertTrue(clean.severeWarnings.isEmpty())
    assertEquals("Olá {{nome_inquilino}}", clean.html)

    val flaggedBody = store.previewCommunication(
      billingID = StableID.billingAurora101,
      subject = "Fatura",
      message = "Pague logo, seu babaca",
    )
    assertEquals(listOf("babaca"), flaggedBody.mildWarnings)
    assertTrue(flaggedBody.severeWarnings.isEmpty())

    // The server scans subject and body together and normalizes accents before matching.
    val flaggedSubject = store.previewCommunication(
      billingID = StableID.billingAurora101,
      subject = "Aviso ao otário",
      message = "Segue a fatura.",
    )
    assertEquals(listOf("otario"), flaggedSubject.mildWarnings)
    assertTrue(flaggedSubject.severeWarnings.isEmpty())

    // Severe terms block sending, which is the composer branch this case keeps demoable.
    val blocked = store.previewCommunication(
      billingID = StableID.billingAurora101,
      subject = "Fatura",
      message = "Se não pagar até sexta, vou te matar.",
    )
    assertEquals(listOf("vou te matar"), blocked.severeWarnings)
    assertTrue(blocked.mildWarnings.isEmpty())
  }

  @Test
  fun mockFixtureBillsExposeRenderedDocuments() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)

    val sent = store.bill(billingID = StableID.billingAurora202, id = StableID.billSent)
    val paid = store.bill(billingID = StableID.billingAurora101, id = StableID.billPaid)

    assertEquals(PDFRenderStatus.SUCCEEDED, sent.pdfRenderStatus)
    assertTrue(sent.hasInvoice)
    assertFalse(sent.hasRecibo)
    assertEquals(BillCapabilities.permissive, sent.capabilities)
    assertTrue(paid.hasRecibo)
  }

  @Test
  fun viewerModeReturnsReadOnlyPerBillCapabilities() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    store.setViewerMode(true)

    val bill = store.bill(billingID = StableID.billingAurora202, id = StableID.billSent)

    assertTrue(bill.capabilities.canDownloadInvoice)
    assertFalse(bill.capabilities.canEdit)
    assertFalse(bill.capabilities.canDelete)
    assertFalse(bill.capabilities.canTransition)
    assertFalse(bill.capabilities.canRegenerate)
    assertFalse(bill.capabilities.canUploadReceipts)
    assertFalse(bill.capabilities.canDeleteReceipts)
    assertFalse(bill.capabilities.canReorderReceipts)
    assertFalse(bill.capabilities.canCompose)
    assertFalse(bill.capabilities.canSendInvoice)
    assertFalse(bill.capabilities.canSendRecibo)

    assertEquals(
      DemoError.permissionDenied,
      assertDemoError { store.regenerateBill(billingID = bill.billingID, billID = bill.id) },
    )
  }

  @Test
  fun mockRegenerateQueuesTheRenderAndSettlesAfterTwoFetches() = runTest {
    // Demo mode has to exercise the whole poll cycle: the bill comes back `pending`, stays pending
    // for the first poll tick, and flips to `succeeded` on the second one.
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)

    val queued = store.regenerateBill(
      billingID = StableID.billingAurora202,
      billID = StableID.billSent,
    )
    assertEquals(PDFRenderStatus.PENDING, queued.pdfRenderStatus)

    val firstPoll = store.bill(billingID = StableID.billingAurora202, id = StableID.billSent)
    assertEquals(PDFRenderStatus.PENDING, firstPoll.pdfRenderStatus)

    val secondPoll = store.bill(billingID = StableID.billingAurora202, id = StableID.billSent)
    assertEquals(PDFRenderStatus.SUCCEEDED, secondPoll.pdfRenderStatus)

    // The countdown is consumed, so later fetches stay settled.
    val thirdPoll = store.bill(billingID = StableID.billingAurora202, id = StableID.billSent)
    assertEquals(PDFRenderStatus.SUCCEEDED, thirdPoll.pdfRenderStatus)
  }

  @Test
  fun mockResetClearsAPendingRenderCountdown() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    store.regenerateBill(billingID = StableID.billingAurora202, billID = StableID.billSent)

    store.reset()

    val bill = store.bill(billingID = StableID.billingAurora202, id = StableID.billSent)
    assertEquals(PDFRenderStatus.SUCCEEDED, bill.pdfRenderStatus)
  }

  @Test
  fun viewerModeDeniesEveryWriteWithoutTouchingTheSnapshot() = runTest {
    // `requireWriteAccess` is the single gate every demo mutation shares; viewer mode must reject
    // reads' write counterparts uniformly rather than per screen.
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val canonical = store.snapshot
    store.setViewerMode(true)

    val error = assertDemoError {
      store.transitionBill(
        billingID = StableID.billingAurora101,
        billID = StableID.billDraft,
        status = BillStatus.PUBLISHED,
      )
    }
    assertEquals(DemoError.permissionDenied, error)
    assertEquals(canonical.bills, store.snapshot.bills)
  }

  @Test
  fun delayedOperationsStillResolve() = runTest {
    // The 350 ms demo delay is virtual time under `runTest`, so enabling it changes latency in the
    // app without slowing the suite down.
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    store.setDelayEnabled(true)

    assertEquals(6, store.listBillings().size)
    assertTrue(store.demoSettings.delayEnabled)
  }
}

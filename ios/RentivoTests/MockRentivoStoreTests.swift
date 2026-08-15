import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

@Test @MainActor func canonicalFixturesCoverEveryInvoiceStatus() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  let billings = try await store.listBillings()
  var bills: [Bill] = []
  for billing in billings {
    bills.append(contentsOf: try await store.listBills(billingID: billing.id))
  }

  #expect(billings.count == 6)
  #expect(Set(bills.map(\.status)) == Set(BillStatus.allCases))
}

@Test @MainActor func addingExpenseUpdatesDashboardNetIncome() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  let before = try await store.dashboardSummary()

  _ = try await store.createExpense(
    billingID: StableID.billingAurora101,
    description: "Manutenção",
    category: .maintenance,
    incurredOn: DateOnly(year: 2026, month: 7, day: 20),
    amount: Money(centavos: 25_000)
  )

  let after = try await store.dashboardSummary()
  #expect(after.expenses == before.expenses + Money(centavos: 25_000))
  #expect(after.netIncome == before.netIncome - Money(centavos: 25_000))
}

@Test @MainActor func invalidTransitionDoesNotMutateBill() async throws {
  let store = MockRentivoStore(fixtures: .canonical)

  do {
    try await store.transitionBill(
      billingID: StableID.billingAurora101,
      billID: StableID.billDraft,
      to: .delayedPayment
    )
    Issue.record("Expected invalid transition to throw")
  } catch let error as DemoError {
    #expect(error == .invalidBillTransition)
  }

  let bill = try await store.bill(
    billingID: StableID.billingAurora101,
    id: StableID.billDraft
  )
  #expect(bill.status == .draft)
}

@Test @MainActor func validTransitionMutatesSharedBill() async throws {
  let store = MockRentivoStore(fixtures: .canonical)

  try await store.transitionBill(
    billingID: StableID.billingAurora101,
    billID: StableID.billDraft,
    to: .published
  )

  let bill = try await store.bill(
    billingID: StableID.billingAurora101,
    id: StableID.billDraft
  )
  #expect(bill.status == .published)
  #expect(store.recentActivities.first?.kind == .bill)
}

@Test @MainActor func injectedFailureIsConsumedByOneOperation() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  store.failNextOperation()

  do {
    _ = try await store.listBillings()
    Issue.record("Expected injected failure")
  } catch let error as DemoError {
    #expect(error == .operationFailed)
  }

  #expect(try await store.listBillings().count == 6)
}

@Test @MainActor func emptyModeChangesReadsWithoutDestroyingSnapshot() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  let canonical = store.snapshot
  store.setEmptyMode(true)

  #expect(try await store.listBillings().isEmpty)
  #expect(store.snapshot == canonical)

  store.setEmptyMode(false)
  #expect(try await store.listBillings().count == 6)
}

@Test @MainActor func viewerModeRestrictsCapabilitiesWithoutChangingOwnership() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  let original = try #require(try await store.listBillings().first)
  store.setViewerMode(true)
  let restricted = try #require(try await store.listBillings().first)

  #expect(restricted.id == original.id)
  #expect(restricted.owner == original.owner)
  #expect(restricted.capabilities == .viewer)
}

@Test @MainActor func viewerModeRestrictsOrganizationManagementCapabilities() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  store.setViewerMode(true)

  let organization = try await store.organization(id: StableID.organizationHorizonte)

  #expect(organization.currentUserRole == .viewer)
  #expect(!organization.capabilities.canManage)
  #expect(!organization.capabilities.canInvite)
  #expect(!organization.capabilities.canCreateBilling)
  #expect(organization.capabilities.canViewBillingStats)
}

@Test @MainActor func acceptingInvitationCreatesMembershipAndClearsPendingCount() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  let invitation = try #require(try await store.listPendingInvitations().first)

  try await store.acceptInvitation(id: invitation.id)

  #expect(try await store.listPendingInvitations().isEmpty)
  let organization = try await store.organization(id: invitation.organizationID)
  #expect(organization.members.contains { $0.userID == store.currentUser.id })
}

@Test @MainActor func acceptedManagerCannotMutateOrganizationPolicy() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  let invitation = try #require(try await store.listPendingInvitations().first)
  try await store.acceptInvitation(id: invitation.id)

  do {
    _ = try await store.setOrganizationMFA(
      organizationID: invitation.organizationID,
      required: true
    )
    Issue.record("Expected manager policy mutation to be denied")
  } catch let error as DemoError {
    #expect(error == .permissionDenied)
  }
}

@Test @MainActor func acceptedManagerCannotInviteOrganizationMembers() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  let invitation = try #require(try await store.listPendingInvitations().first)
  try await store.acceptInvitation(id: invitation.id)

  do {
    _ = try await store.inviteMember(
      organizationID: invitation.organizationID,
      email: "novo-membro@rentivo.com.br",
      role: .viewer
    )
    Issue.record("Expected manager invitation to be denied")
  } catch let error as DemoError {
    #expect(error == .permissionDenied)
  }
}

@Test @MainActor func acceptedManagerCannotMutateOrganizationTheme() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  let invitation = try #require(try await store.listPendingInvitations().first)
  try await store.acceptInvitation(id: invitation.id)

  let theme = try await store.theme(target: .organization(invitation.organizationID))
  #expect(!theme.canEdit)

  do {
    try await store.updateTheme(
      target: .organization(invitation.organizationID),
      values: .sunset
    )
    Issue.record("Expected manager theme mutation to be denied")
  } catch let error as DemoError {
    #expect(error == .permissionDenied)
  }
}

@Test @MainActor func resetRestoresCanonicalSnapshotAndBehavior() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  _ = try await store.createExpense(
    billingID: StableID.billingAurora101,
    description: "Pintura",
    category: .maintenance,
    incurredOn: DateOnly(year: 2026, month: 7, day: 20),
    amount: Money(centavos: 10_000)
  )
  store.setEmptyMode(true)
  store.setViewerMode(true)

  store.reset()

  #expect(store.snapshot == MockFixtures.canonical.snapshot)
  #expect(try await store.listBillings().count == 6)
  #expect(try #require(try await store.listBillings().first).capabilities == .full)
}

@Test @MainActor func receiptOrderPersists() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  let bill = try await store.bill(
    billingID: StableID.billingAurora101,
    id: StableID.billPaid
  )
  let reversed = Array(bill.receipts.map(\.id).reversed())

  try await store.reorderReceipts(
    billingID: bill.billingID,
    billID: bill.id,
    receiptIDs: reversed
  )

  let updated = try await store.bill(billingID: bill.billingID, id: bill.id)
  #expect(bill.receipts.count == 2)
  #expect(updated.receipts.map(\.id) == reversed)
}

@Test @MainActor func communicationMutationUsesSharedActivityGraph() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  let billing = try await store.billing(id: StableID.billingAurora101)
  let recipientIDs = billing.recipients.map(\.id)
  #expect(recipientIDs.count >= 2)  // fixture must exercise the multi-recipient path

  let queued = try await store.sendCommunication(
    billingID: StableID.billingAurora101,
    billID: StableID.billPublished,
    commType: .billReady,
    recipientIDs: recipientIDs,
    subject: "Sua fatura está disponível",
    message: "Olá! Consulte os detalhes no Rentivo.",
    acknowledgeWarning: false,
    saveScope: nil
  )

  #expect(queued == recipientIDs.count)
  let record = try #require(store.snapshot.communications.first)
  #expect(Set(record.recipients) == Set(billing.recipients.map(\.email)))
  #expect(store.recentActivities.first?.detail == record.subject)
}

@Test @MainActor func canonicalFixtureBillingsCarryATemplateForEveryCommType() async throws {
  // The composer prefills subject/body from the billing templates, so demo mode only
  // matches production when the fixtures ship templates for every communication type.
  let store = MockRentivoStore(fixtures: .canonical)

  for billing in try await store.listBillings() {
    for commType in CommunicationType.allCases {
      let template = try #require(billing.template(for: commType))
      #expect(!template.subject.isEmpty)
      #expect(template.body.contains("{{nome_inquilino}}"))
    }
  }
}

@Test @MainActor func creatingABillingAttachesTheDefaultCommunicationTemplates() async throws {
  let store = MockRentivoStore(fixtures: .canonical)

  let created = try await store.createBilling(
    BillingDraft(
      name: "Apt 999 - Edifício Novo",
      description: "Cobrança recém-criada",
      owner: .user(id: StableID.userAna, name: "Pessoal"),
      items: []
    )
  )

  #expect(created.communicationTemplates == MockFixtures.defaultCommunicationTemplates)
  let stored = try await store.billing(id: created.id)
  #expect(stored.communicationTemplates == MockFixtures.defaultCommunicationTemplates)
}

@Test @MainActor func updatingABillingKeepsItsCommunicationTemplates() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  let billing = try await store.billing(id: StableID.billingAurora101)
  let draft = BillingDraft(
    name: "Apt 101 - Edifício Aurora (renomeado)",
    description: billing.description,
    owner: billing.owner,
    items: billing.items,
    recipients: billing.recipients,
    replyTo: billing.replyTo
  )

  let updated = try await store.updateBilling(id: billing.id, draft: draft)

  #expect(!billing.communicationTemplates.isEmpty)
  #expect(updated.communicationTemplates == billing.communicationTemplates)
  let stored = try await store.billing(id: billing.id)
  #expect(stored.communicationTemplates == billing.communicationTemplates)
}

@Test @MainActor func sendingToASubsetQueuesOnlyTheSelectedRecipient() async throws {
  // The composer lets the user deselect recipients, so a partial selection must queue exactly
  // the chosen ones instead of falling back to the whole billing.
  let store = MockRentivoStore(fixtures: .canonical)
  let billing = try await store.billing(id: StableID.billingAurora101)
  #expect(billing.recipients.count >= 2)
  let selected = try #require(billing.recipients.last)

  let queued = try await store.sendCommunication(
    billingID: billing.id,
    billID: StableID.billPublished,
    commType: .billReady,
    recipientIDs: [selected.id],
    subject: "Sua fatura está disponível",
    message: "Olá! Consulte os detalhes no Rentivo.",
    acknowledgeWarning: false,
    saveScope: nil
  )

  #expect(queued == 1)
  let record = try #require(store.snapshot.communications.first)
  #expect(record.recipients == [selected.email])
}

@Test @MainActor func sendingToARecipientOutsideTheBillingFails() async throws {
  let store = MockRentivoStore(fixtures: .canonical)

  await #expect(throws: DemoError.self) {
    try await store.sendCommunication(
      billingID: StableID.billingAurora101,
      billID: StableID.billPublished,
      commType: .billReady,
      recipientIDs: [RecipientID(rawValue: "not-a-recipient")],
      subject: "Assunto",
      message: "Corpo",
      acknowledgeWarning: false,
      saveScope: nil
    )
  }
}

@Test @MainActor func sendingCommunicationNormalizesAndValidatesContent() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  let billing = try await store.billing(id: StableID.billingAurora101)
  let recipient = try #require(billing.recipients.first)

  _ = try await store.sendCommunication(
    billingID: billing.id,
    billID: StableID.billPublished,
    commType: .billReady,
    recipientIDs: [recipient.id],
    subject: "  Assunto  ",
    message: "  Corpo  ",
    acknowledgeWarning: false,
    saveScope: nil
  )
  let record = try #require(store.snapshot.communications.first)
  #expect(record.subject == "Assunto")
  #expect(record.message == "Corpo")

  await #expect(throws: DemoError.self) {
    try await store.sendCommunication(
      billingID: billing.id,
      billID: StableID.billPublished,
      commType: .billReady,
      recipientIDs: [recipient.id],
      subject: "   ",
      message: "Corpo",
      acknowledgeWarning: false,
      saveScope: nil
    )
  }
}

@Test @MainActor func creatingExpenseRejectsZeroOrNegativeAmounts() async throws {
  // Matches the server contract: `ExpenseCreateRequest.amount` requires
  // `exclusiveMinimum: 0`.
  let store = MockRentivoStore(fixtures: .canonical)

  do {
    _ = try await store.createExpense(
      billingID: StableID.billingAurora101,
      description: "Reparo",
      category: .maintenance,
      incurredOn: DateOnly(year: 2026, month: 7, day: 20),
      amount: .zero
    )
    Issue.record("Expected zero-amount expense to be rejected")
  } catch let error as DemoError {
    #expect(error == .invalidAmount)
  }

  do {
    _ = try await store.createExpense(
      billingID: StableID.billingAurora101,
      description: "Reparo",
      category: .maintenance,
      incurredOn: DateOnly(year: 2026, month: 7, day: 20),
      amount: Money(centavos: -100)
    )
    Issue.record("Expected negative-amount expense to be rejected")
  } catch let error as DemoError {
    #expect(error == .invalidAmount)
  }
}

@Test @MainActor func creatingExpenseNormalizesAndValidatesItsDescription() async throws {
  let store = MockRentivoStore(fixtures: .canonical)

  let created = try await store.createExpense(
    billingID: StableID.billingAurora101,
    description: "  Pintura  ",
    category: .maintenance,
    incurredOn: DateOnly(year: 2026, month: 7, day: 20),
    amount: Money(centavos: 100)
  )
  #expect(created.description == "Pintura")

  for invalid in ["   ", String(repeating: "d", count: 2_001)] {
    do {
      _ = try await store.createExpense(
        billingID: StableID.billingAurora101,
        description: invalid,
        category: .maintenance,
        incurredOn: DateOnly(year: 2026, month: 7, day: 20),
        amount: Money(centavos: 100)
      )
      Issue.record("Expected the invalid expense description to be rejected")
    } catch let error as DemoError {
      #expect(error == .invalidDescription)
    }
  }
}

@Test @MainActor func deletingExpenseUpdatesDashboard() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  let expense = try #require(
    try await store.listExpenses(billingID: StableID.billingAurora101).first
  )
  let before = try await store.dashboardSummary()

  try await store.deleteExpense(billingID: expense.billingID, expenseID: expense.id)

  let after = try await store.dashboardSummary()
  #expect(after.expenses == before.expenses - expense.amount)
  #expect(after.netIncome == before.netIncome + expense.amount)
}

@Test @MainActor func transferringBillingChangesOwnerAcrossRepositoryReads() async throws {
  let store = MockRentivoStore(fixtures: .canonical)

  try await store.transferBilling(
    billingID: StableID.billingAurora101,
    toOrganizationID: StableID.organizationHorizonte
  )

  let billing = try await store.billing(id: StableID.billingAurora101)
  #expect(billing.owner.workspaceID.rawValue == StableID.organizationHorizonte.rawValue)
  #expect(billing.owner.isOrganization)
}

@Test @MainActor func memberRoleAndMFAPolicyMutationsPersist() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  let organization = try await store.organization(id: StableID.organizationHorizonte)
  let member = try #require(organization.members.first { $0.role == .viewer })

  try await store.updateMemberRole(
    organizationID: organization.id,
    userID: member.userID,
    role: .manager
  )
  _ = try await store.setOrganizationMFA(organizationID: organization.id, required: false)

  let updated = try await store.organization(id: organization.id)
  #expect(updated.members.first { $0.userID == member.userID }?.role == .manager)
  #expect(!updated.requiresMFA)
}

@Test @MainActor func mfaPolicyReportsWhenTheCurrentUserNeedsEnrollment() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  let organization = try await store.organization(id: StableID.organizationHorizonte)
  _ = try await store.setOrganizationMFA(organizationID: organization.id, required: false)
  try await store.disableTOTP(password: "senha-valida")
  for passkey in try await store.securitySummary().passkeys {
    try await store.deletePasskey(id: passkey.id)
  }

  let policy = try await store.setOrganizationMFA(
    organizationID: organization.id,
    required: true
  )

  #expect(policy.enforceMFA)
  #expect(policy.mfaSetupRequired)
  let summary = try await store.securitySummary()
  #expect(summary.organizationEnforced)
  #expect(summary.setupRequired)
}

@Test @MainActor func enforcedOrganizationProtectsTheLastMFAFactor() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  try await store.disableTOTP(password: "senha-valida")
  let passkey = try #require(try await store.securitySummary().passkeys.first)

  await #expect(throws: DemoError.permissionDenied) {
    try await store.deletePasskey(id: passkey.id)
  }
}

@Test @MainActor func memberRoleCanBePromotedToAdmin() async throws {
  // Regression coverage for the role picker bug: promoting a member to admin
  // must be a supported mutation (the API accepts admin/manager/viewer).
  let store = MockRentivoStore(fixtures: .canonical)
  let organization = try await store.organization(id: StableID.organizationHorizonte)
  let member = try #require(organization.members.first { $0.role == .manager })

  try await store.updateMemberRole(
    organizationID: organization.id,
    userID: member.userID,
    role: .admin
  )

  let updated = try await store.organization(id: organization.id)
  #expect(updated.members.first { $0.userID == member.userID }?.role == .admin)
}

@Test @MainActor func createdKeySecretIsSeparateFromMetadata() async throws {
  let store = MockRentivoStore(fixtures: .canonical)

  let created = try await store.createAPIKey(.demo)
  let metadata = try await store.listAPIKeys()

  #expect(created.secret.hasPrefix("rntv-v1-"))
  #expect(metadata.contains { $0.id == created.metadata.id })
  #expect(!String(describing: metadata).contains(created.secret))
}

@Test @MainActor func clearingProfilePIXRemovesTheConfiguration() async throws {
  let store = MockRentivoStore(fixtures: .canonical)

  let profile = try await store.updatePix(
    PixConfiguration(key: "", merchantName: "", merchantCity: "")
  )

  #expect(profile.pix == nil)
  #expect(try await store.profile().pix == nil)
}

@Test @MainActor func revokedAPIKeyRemainsInHistoryAndCannotBeRevokedAgain() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  let key = try #require(try await store.listAPIKeys().first)

  try await store.revokeAPIKey(id: key.id)

  let revoked = try #require(try await store.listAPIKeys().first { $0.id == key.id })
  #expect(revoked.revokedAt != nil)
  await #expect(throws: DemoError.resourceNotFound) {
    try await store.revokeAPIKey(id: key.id)
  }
}

@Test @MainActor func apiKeyMetadataCanBeUpdatedWithoutRotatingSecret() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  let key = try #require(try await store.listAPIKeys().first)
  let updatedDraft = APIKeyDraft(
    name: "Integração contábil",
    scopes: [.profileRead, .expensesRead],
    grants: [APIKeyGrant(resourceType: .user, resourceID: .personal)],
    expiresAt: Date(timeIntervalSince1970: 1_830_297_600)
  )

  let updated = try await store.updateAPIKey(id: key.id, draft: updatedDraft)

  #expect(updated.id == key.id)
  #expect(updated.hint == key.hint)
  #expect(updated.name == updatedDraft.name)
  #expect(updated.scopes == updatedDraft.scopes)
  #expect(updated.grants == updatedDraft.grants)
  // PATCH does not accept `expires_at`; metadata edits must preserve the issued expiry.
  #expect(updated.expiresAt == key.expiresAt)
}

@Test @MainActor func apiKeyUpdateKeepsGrantsWhenTheFormDidNotChangeAccess() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  let key = try #require(try await store.listAPIKeys().first)
  let draft = APIKeyDraft(
    name: "Somente nome",
    scopes: key.scopes,
    grants: [],
    expiresAt: key.expiresAt
  )

  let updated = try await store.updateAPIKey(id: key.id, draft: draft, updateGrants: false)

  #expect(updated.grants == key.grants)
}

@Test @MainActor func demoSettingsAreAuthoritativeAndResetTogether() async throws {
  let store = MockRentivoStore(fixtures: .canonical)

  store.setDelayEnabled(true)
  store.setEmptyMode(true)
  store.setViewerMode(true)

  #expect(
    store.demoSettings
      == DemoSettings(delayEnabled: true, emptyMode: true, viewerMode: true)
  )

  store.reset()
  #expect(store.demoSettings == .standard)
}

@Test @MainActor func appDependenciesExposeFocusedRepositoryBoundary() {
  let store = MockRentivoStore(fixtures: .canonical)
  let dependencies = AppDependencies.mock(store: store)

  #expect(dependencies.auth === store)
  #expect(dependencies.billings === store)
  #expect(dependencies.bills === store)
  #expect(dependencies.organizations === store)
  #expect(dependencies.demo === store)
}

@Test @MainActor func themeResetRestoresUserInheritance() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  let target = ThemeTarget.billing(StableID.billingAurora101)

  try await store.updateTheme(target: target, values: .sunset)
  try await store.resetTheme(target: target)

  let theme = try await store.theme(target: target)
  #expect(theme.stored == nil)
  #expect(theme.effectiveSource == .user)
  #expect(theme.effective == .rentivo)
}

@Test @MainActor func securityMutationsUpdateTOTPAndRecoveryCodes() async throws {
  let store = MockRentivoStore(fixtures: .canonical)

  // The TOTP flag is only reachable through the enrollment/disable pair, which is how the
  // security screen drives it.
  let enrollmentCodes = try await store.confirmTOTPEnrollment(code: "123456")
  #expect(enrollmentCodes.count == 8)
  #expect(try await store.securitySummary().totpEnabled)

  try await store.disableTOTP(password: "senha-de-demonstração")

  let summary = try await store.securitySummary()
  #expect(!summary.totpEnabled)
  #expect(summary.recoveryCodeCount == 0)
  await #expect(throws: DemoError.self) {
    _ = try await store.regenerateRecoveryCodes()
  }
}

@Test @MainActor func demoStoreReportsNoLiveSessionToRestoreRevokeOrDelete() async throws {
  let store = MockRentivoStore(fixtures: .canonical)

  #expect(store.usesLiveAPI == false)
  #expect(try await store.restoreSession() == nil)
  // Nothing to revoke or delete server-side; the demo data must survive both untouched.
  await store.logout()
  try await store.deleteAccount(password: "senha-de-demonstração")
  #expect(store.currentUser == store.snapshot.profile)

  let exchanged = try await store.exchangeMobileAuthorization(code: "codigo-de-demonstração")
  #expect(exchanged == store.snapshot.profile)
}

@Test @MainActor func mockPreviewFlagsTermsTakenFromTheServerModerationLexicon() async throws {
  // The demo lexicon is a strict subset of the server's, so anything flagged here is also
  // flagged by backend/rentivo/communications/moderation.py — demo mode never warns about
  // text production accepts.
  let store = MockRentivoStore(fixtures: .canonical)

  let clean = try await store.previewCommunication(
    billingID: StableID.billingAurora101, subject: "Fatura", message: "Olá {{nome_inquilino}}"
  )
  #expect(clean.mildWarnings.isEmpty)
  #expect(clean.severeWarnings.isEmpty)
  #expect(clean.html == "Olá {{nome_inquilino}}")

  let flaggedBody = try await store.previewCommunication(
    billingID: StableID.billingAurora101, subject: "Fatura", message: "Pague logo, seu babaca"
  )
  #expect(flaggedBody.mildWarnings == ["babaca"])
  #expect(flaggedBody.severeWarnings.isEmpty)

  // The server scans subject and body together and normalizes accents before matching.
  let flaggedSubject = try await store.previewCommunication(
    billingID: StableID.billingAurora101, subject: "Aviso ao otário", message: "Segue a fatura."
  )
  #expect(flaggedSubject.mildWarnings == ["otario"])
  #expect(flaggedSubject.severeWarnings.isEmpty)

  // Severe terms block sending, which is the composer branch this case keeps demoable.
  let blocked = try await store.previewCommunication(
    billingID: StableID.billingAurora101,
    subject: "Fatura",
    message: "Se não pagar até sexta, vou te matar."
  )
  #expect(blocked.severeWarnings == ["vou te matar"])
  #expect(blocked.mildWarnings.isEmpty)
}

@Test @MainActor func mockFixtureBillsExposeRenderedDocuments() async throws {
  let store = MockRentivoStore(fixtures: .canonical)

  let sent = try await store.bill(billingID: StableID.billingAurora202, id: StableID.billSent)
  let paid = try await store.bill(billingID: StableID.billingAurora101, id: StableID.billPaid)

  #expect(sent.pdfRenderStatus == .succeeded)
  #expect(sent.hasInvoice)
  #expect(!sent.hasRecibo)
  #expect(sent.capabilities == .permissive)
  #expect(paid.hasRecibo)
}

@Test @MainActor func viewerModeReturnsReadOnlyPerBillCapabilities() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  store.setViewerMode(true)

  let bill = try await store.bill(
    billingID: StableID.billingAurora202, id: StableID.billSent)

  #expect(bill.capabilities.canDownloadInvoice)
  #expect(!bill.capabilities.canEdit)
  #expect(!bill.capabilities.canDelete)
  #expect(!bill.capabilities.canTransition)
  #expect(!bill.capabilities.canRegenerate)
  #expect(!bill.capabilities.canUploadReceipts)
  #expect(!bill.capabilities.canDeleteReceipts)
  #expect(!bill.capabilities.canReorderReceipts)
  #expect(!bill.capabilities.canCompose)
  #expect(!bill.capabilities.canSendInvoice)
  #expect(!bill.capabilities.canSendRecibo)

  do {
    _ = try await store.regenerateBill(billingID: bill.billingID, billID: bill.id)
    Issue.record("Expected viewer mode to reject PDF regeneration")
  } catch let error as DemoError {
    #expect(error == .permissionDenied)
  }
}

@Test @MainActor func mockRegenerateQueuesTheRenderAndSettlesAfterTwoFetches() async throws {
  // Demo mode has to exercise the whole poll cycle: the bill comes back `pending`, stays pending
  // for the first poll tick, and flips to `succeeded` on the second one.
  let store = MockRentivoStore(fixtures: .canonical)

  let queued = try await store.regenerateBill(
    billingID: StableID.billingAurora202, billID: StableID.billSent)
  #expect(queued.pdfRenderStatus == .pending)

  let firstPoll = try await store.bill(
    billingID: StableID.billingAurora202, id: StableID.billSent)
  #expect(firstPoll.pdfRenderStatus == .pending)

  let secondPoll = try await store.bill(
    billingID: StableID.billingAurora202, id: StableID.billSent)
  #expect(secondPoll.pdfRenderStatus == .succeeded)

  // The countdown is consumed, so later fetches stay settled.
  let thirdPoll = try await store.bill(
    billingID: StableID.billingAurora202, id: StableID.billSent)
  #expect(thirdPoll.pdfRenderStatus == .succeeded)
}

@Test @MainActor func mockResetClearsAPendingRenderCountdown() async throws {
  let store = MockRentivoStore(fixtures: .canonical)
  _ = try await store.regenerateBill(billingID: StableID.billingAurora202, billID: StableID.billSent)

  store.reset()

  let bill = try await store.bill(billingID: StableID.billingAurora202, id: StableID.billSent)
  #expect(bill.pdfRenderStatus == .succeeded)
}

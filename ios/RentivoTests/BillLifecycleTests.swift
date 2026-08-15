import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

@Test func draftCanPublishButCannotBecomeDelayedDirectly() {
  #expect(BillStatus.draft.canTransition(to: .published))
  #expect(BillStatus.draft.canTransition(to: .cancelled))
  #expect(!BillStatus.draft.canTransition(to: .delayedPayment))
}

@Test func paidAndCancelledBillsAreTerminal() {
  #expect(BillStatus.paid.allowedTransitions.isEmpty)
  #expect(BillStatus.cancelled.allowedTransitions.isEmpty)
}

@Test func billStatusesKeepAPIValuesAndPortugueseLabels() {
  #expect(BillStatus.delayedPayment.rawValue == "delayed_payment")
  #expect(BillStatus.delayedPayment.label == "Pagamento atrasado")
  #expect(BillStatus.published.label == "Publicada")
}

@Test func viewerCapabilitiesAreReadOnly() {
  #expect(BillingCapabilities.viewer.canReadBills)
  #expect(BillingCapabilities.viewer.canReadExpenses)
  #expect(!BillingCapabilities.viewer.canEdit)
  #expect(!BillingCapabilities.viewer.canDelete)
  #expect(!BillingCapabilities.viewer.canWriteExpenses)
}

@Test func fullCapabilitiesExposeEveryBillingAction() {
  let capabilities = BillingCapabilities.full
  #expect(capabilities.allowsEveryAction)
}

@Test func billTotalIsDerivedFromLineItems() {
  let bill = Bill(
    id: StableID.billPaid,
    billingID: StableID.billingAurora101,
    referenceMonth: ReferenceMonth(year: 2026, month: 7),
    dueDate: DateOnly(year: 2026, month: 7, day: 10),
    paidAt: DateOnly(year: 2026, month: 7, day: 8),
    notes: "",
    status: .paid,
    lineItems: [
      BillLineItem(
        id: UUID(), description: "Aluguel", amount: Money(centavos: 180_000), kind: .fixed),
      BillLineItem(
        id: UUID(), description: "Água", amount: Money(centavos: 12_340), kind: .variable),
      BillLineItem(
        id: UUID(), description: "Pintura", amount: Money(centavos: 5_000), kind: .extra),
    ],
    receipts: []
  )

  #expect(bill.total == Money(centavos: 197_340))
}

@Test func dateAndReferenceMonthHaveStableAPIRepresentations() {
  #expect(DateOnly(year: 2026, month: 7, day: 9).iso8601 == "2026-07-09")
  #expect(ReferenceMonth(year: 2026, month: 7).apiValue == "2026-07")
  #expect(ReferenceMonth(year: 2026, month: 7).label == "julho de 2026")
}

@Test func integrationScopesExcludePrivilegedAccountOperations() {
  #expect(APIKeyScope.integrationCases.contains(.billingsRead))
  #expect(APIKeyScope.integrationCases.contains(.communicationsSend))
  #expect(!APIKeyScope.integrationCases.contains(.securityManage))
  #expect(!APIKeyScope.integrationCases.contains(.apiKeysManage))
}

@Test func apiKeyOptionsApplyServerExpirationLimitsAndValidateNames() {
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let options = APIKeyOptions(
    scopes: [.profileRead],
    personalWorkspace: APIKeyWorkspaceOption(
      resourceType: .user, resourceID: .personal, name: "Conta pessoal"),
    organizations: [],
    defaultExpirationDays: 30,
    maxExpirationDays: 180
  )

  #expect(options.defaultExpiration(from: now) == now.addingTimeInterval(30 * 86_400))
  #expect(options.maximumExpiration(from: now) == now.addingTimeInterval(180 * 86_400 - 60))
  #expect(options.clampedExpiration(now, from: now) == now.addingTimeInterval(60))
  #expect(
    options.clampedExpiration(now.addingTimeInterval(365 * 86_400), from: now)
      == options.maximumExpiration(from: now)
  )
  #expect(APIKeyValidation.isValidName(" CRM "))
  #expect(!APIKeyValidation.isValidName("   "))
  #expect(!APIKeyValidation.isValidName(String(repeating: "a", count: 256)))
  #expect(APIKeyValidation.isValidName(String(repeating: "😀", count: 255)))
  #expect(!APIKeyValidation.isValidName(String(repeating: "😀", count: 256)))
  #expect(!APIKeyValidation.isValidName(String(repeating: "e\u{301}", count: 128)))
}

@Test func apiEnumsPreserveRawValues() {
  #expect(ExpenseCategory.maintenance.rawValue == "manutencao")
  #expect(OrganizationRole.viewer.rawValue == "viewer")
  #expect(ThemeSource.organization.rawValue == "organization")
}

@Test func organizationRoleMatchesTheServerContractExactly() {
  // OrganizationMemberUpdateRequest.role and every invite/member response enum
  // in the OpenAPI contract only ever accept admin/manager/viewer — there is
  // no "owner" concept on the wire.
  #expect(Set(OrganizationRole.allCases) == [.admin, .manager, .viewer])
}

@Test func organizationRoleForRoleGrantsFullCapabilitiesToAdmin() {
  #expect(OrganizationCapabilities.forRole(.admin) == .full)
  #expect(OrganizationCapabilities.forRole(.manager) == .manager)
  #expect(OrganizationCapabilities.forRole(.viewer) == .viewer)
}

private func makeBill(status: BillStatus = .draft, availableTransitions: [BillStatus]? = nil, serverTotal: Money? = nil) -> Bill {
  Bill(
    id: StableID.billDraft,
    billingID: StableID.billingAurora101,
    referenceMonth: ReferenceMonth(year: 2026, month: 7),
    dueDate: DateOnly(year: 2026, month: 7, day: 10),
    paidAt: nil,
    notes: "",
    status: status,
    lineItems: [
      BillLineItem(id: UUID(), description: "Aluguel", amount: Money(centavos: 180_000), kind: .fixed)
    ],
    receipts: [],
    availableTransitions: availableTransitions,
    serverTotal: serverTotal
  )
}

@Test func billFallsBackToLocalTransitionRulesWhenServerOmitsThem() {
  let bill = makeBill(status: .draft)
  #expect(bill.effectiveTransitions == BillStatus.draft.allowedTransitions)
  #expect(bill.canTransition(to: .published))
  #expect(!bill.canTransition(to: .delayedPayment))
}

@Test func billPrefersServerSuppliedTransitionsWhenPresent() {
  // Even though the local state machine would allow draft -> published, the
  // server can restrict this specific bill further (or further loosen it).
  let bill = makeBill(status: .draft, availableTransitions: [.cancelled])
  #expect(bill.effectiveTransitions == [.cancelled])
  #expect(bill.canTransition(to: .cancelled))
  #expect(!bill.canTransition(to: .published))
}

@Test func billFallbackTransitionActionsConfirmConsequentialChanges() {
  let bill = makeBill(status: .sent, availableTransitions: [.paid, .delayedPayment])
  let actions = bill.effectiveTransitionActions

  #expect(actions.first(where: { $0.target == .paid })?.requiresConfirmation == true)
  #expect(actions.first(where: { $0.target == .paid })?.style == "primary")
  #expect(actions.first(where: { $0.target == .delayedPayment })?.requiresConfirmation == false)
}

@Test func billFallsBackToComputedTotalWhenServerOmitsIt() {
  let bill = makeBill()
  #expect(bill.effectiveTotal == bill.total)
  #expect(bill.effectiveTotal == Money(centavos: 180_000))
}

@Test func billPrefersServerSuppliedTotalWhenPresent() {
  let bill = makeBill(serverTotal: Money(centavos: 99_900))
  #expect(bill.effectiveTotal == Money(centavos: 99_900))
  #expect(bill.total == Money(centavos: 180_000))
}

@Test func onlyTransferablePersonalBillingsCanBeMovedIntoAnOrganization() {
  let transferable = Billing(
    id: BillingID(rawValue: "transferable"), name: "Pessoal", description: "",
    owner: .user(id: 7, name: "Pessoal"), items: [], capabilities: .full
  )
  let denied = Billing(
    id: BillingID(rawValue: "denied"), name: "Sem acesso", description: "",
    owner: .user(id: 7, name: "Pessoal"), items: [], capabilities: .viewer
  )
  let organizationOwned = Billing(
    id: BillingID(rawValue: "organization"), name: "Organização", description: "",
    owner: .organization(id: OrganizationID(rawValue: "org-1"), name: "Organização"),
    items: [], capabilities: .full
  )

  #expect(transferable.canTransferToOrganization)
  #expect(!denied.canTransferToOrganization)
  #expect(!organizationOwned.canTransferToOrganization)
}

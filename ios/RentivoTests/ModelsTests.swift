import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

@Test func stableIdentifiersAreDeterministic() {
  #expect(StableID.userAna == 1)
  #expect(StableID.billingAurora101.rawValue == "00000000-0000-0000-0000-000000000101")
  #expect(StableID.billPaid.rawValue == "00000000-0000-0000-0000-000000001004")
}

@Test func loadStateExposesLoadedValueOnly() {
  #expect(LoadState<Int>.idle.value == nil)
  #expect(LoadState<Int>.loading.value == nil)
  #expect(LoadState.loaded(42).value == 42)
  #expect(LoadState<Int>.empty.value == nil)
}

@Test func demoErrorUsesPortugueseRecoveryCopy() {
  let error = DemoError.operationFailed
  #expect(error.localizedDescription == "Não foi possível concluir esta ação de demonstração.")
}

private struct SampleLocalizedError: LocalizedError {
  let errorDescription: String?
}

private struct SamplePlainError: Error {}

@Test func demoErrorPreservesRealLocalizedErrorMessages() {
  let serverError = SampleLocalizedError(errorDescription: "Sua sessão expirou. Entre novamente para continuar.")
  let wrapped = DemoError(serverError)
  #expect(wrapped.message == "Sua sessão expirou. Entre novamente para continuar.")
}

@Test func demoErrorFallsBackToGenericNonDemoCopyForUnknownErrors() {
  let wrapped = DemoError(SamplePlainError())
  #expect(wrapped.message == "Não foi possível concluir esta ação. Tente novamente.")
  #expect(!wrapped.message.contains("demonstração"))
}

@Test func demoErrorPassesThroughExistingDemoErrors() {
  let wrapped = DemoError(DemoError.permissionDenied)
  #expect(wrapped == .permissionDenied)
}

@Test func dateOnlyFailableInitializerParsesValidISOStrings() {
  let date = DateOnly(iso8601String: "2026-08-10")
  #expect(date == DateOnly(year: 2026, month: 8, day: 10))
}

@Test func dateOnlyFailableInitializerRejectsMalformedWireData() {
  #expect(DateOnly(iso8601String: "not-a-date") == nil)
  #expect(DateOnly(iso8601String: "2026-13-40") == nil)
  #expect(DateOnly(iso8601String: "2026-08") == nil)
}

@Test func referenceMonthFailableInitializerParsesValidAPIValues() {
  let month = ReferenceMonth(apiValue: "2026-08")
  #expect(month == ReferenceMonth(year: 2026, month: 8))
}

@Test func referenceMonthFailableInitializerRejectsMalformedWireData() {
  #expect(ReferenceMonth(apiValue: "not-a-month") == nil)
  #expect(ReferenceMonth(apiValue: "2026-13") == nil)
  #expect(ReferenceMonth(apiValue: "2026") == nil)
}

@Test func dateOnlyDisplayFormattedRendersBrazilianDayMonthYear() {
  #expect(DateOnly(year: 2026, month: 8, day: 10).displayFormatted == "10/08/2026")
}

@Test func referenceMonthDisplayFormattedMatchesPortugueseLabel() {
  let month = ReferenceMonth(year: 2026, month: 8)
  #expect(month.displayFormatted == "agosto de 2026")
  #expect(month.standaloneDisplayFormatted == "Agosto de 2026")
  #expect(month.standaloneMonthName == "Agosto")
  #expect(month.documentDisplayFormatted == "agosto 2026")
}

@Test func communicationTypeRawValuesMatchTheAPIContract() {
  #expect(CommunicationType.billReady.rawValue == "bill_ready")
  #expect(CommunicationType.paymentReceipt.rawValue == "payment_receipt")
  #expect(CommunicationSaveScope.billing.rawValue == "billing")
  #expect(CommunicationSaveScope.owner.rawValue == "owner")
}

@Test func billingResolvesTheTemplateForACommunicationType() {
  let billReady = CommunicationTemplate(
    commType: .billReady, subject: "Cobrança {{unidade}}", body: "Olá {{nome_inquilino}}"
  )
  let receipt = CommunicationTemplate(
    commType: .paymentReceipt, subject: "Recibo {{unidade}}", body: "Recebemos {{total}}"
  )
  let billing = Billing(
    id: BillingID(rawValue: "b1"), name: "Apt 101", description: "",
    owner: .user(id: StableID.userAna, name: "Pessoal"), items: [],
    communicationTemplates: [billReady, receipt]
  )

  #expect(billing.template(for: .billReady) == billReady)
  #expect(billing.template(for: .paymentReceipt) == receipt)
  #expect(
    Billing(
      id: BillingID(rawValue: "b2"), name: "Apt 102", description: "",
      owner: .user(id: StableID.userAna, name: "Pessoal"), items: []
    ).template(for: .billReady) == nil)
}

@Test func onlyOrganizationsAllowedByTheAPICanOwnANewBilling() {
  let allowed = Organization(
    id: StableID.organizationHorizonte,
    name: "Horizonte",
    pix: nil,
    members: [],
    requiresMFA: false,
    currentUserRole: .viewer,
    capabilities: OrganizationCapabilities(
      canManage: false,
      canInvite: false,
      canCreateBilling: true,
      canViewBillingStats: false
    )
  )
  let denied = Organization(
    id: OrganizationID(rawValue: "organization-denied"),
    name: "Sem criação",
    pix: nil,
    members: [],
    requiresMFA: false,
    currentUserRole: .admin,
    capabilities: OrganizationCapabilities(
      canManage: true,
      canInvite: true,
      canCreateBilling: false,
      canViewBillingStats: true
    )
  )

  #expect(
    allowed.billingOwnerForCreation
      == .organization(id: StableID.organizationHorizonte, name: "Horizonte")
  )
  #expect(denied.billingOwnerForCreation == nil)
}

@Test func billingExportContractMatchesTheBackendJobPayload() {
  #expect(BillingExportContract.formats == ["csv", "xlsx"])
  #expect(BillingExportContract.includedSections == ["Faturas"])
}

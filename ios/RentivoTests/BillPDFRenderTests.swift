import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

private func renderBill(
  status: PDFRenderStatus?,
  billStatus: BillStatus = .sent,
  lineItems: [BillLineItem] = [],
  receipts: [Receipt] = [],
  availableTransitions: [BillStatus]? = nil,
  hasInvoice: Bool = false,
  hasRecibo: Bool = false,
  capabilities: BillCapabilities = .permissive
) -> Bill {
  Bill(
    id: BillID(rawValue: "bill-render"),
    billingID: BillingID(rawValue: "billing-render"),
    referenceMonth: ReferenceMonth(year: 2026, month: 7),
    dueDate: nil,
    paidAt: nil,
    notes: "",
    status: billStatus,
    lineItems: lineItems,
    receipts: receipts,
    availableTransitions: availableTransitions,
    pdfRenderStatus: status,
    hasInvoice: hasInvoice,
    hasRecibo: hasRecibo,
    capabilities: capabilities
  )
}

@Test func pdfRenderStatusMapsTheWireLiterals() {
  #expect(PDFRenderStatus(rawValue: "pending") == .pending)
  #expect(PDFRenderStatus(rawValue: "succeeded") == .succeeded)
  #expect(PDFRenderStatus(rawValue: "failed") == .failed)
  #expect(PDFRenderStatus(rawValue: "PENDING") == nil)
  #expect(PDFRenderStatus(rawValue: "queued") == nil)
  #expect(PDFRenderStatus(rawValue: "") == nil)
}

@Test func isRenderingPDFIsTrueOnlyWhileTheRenderIsPending() {
  #expect(renderBill(status: .pending).isRenderingPDF)
  #expect(!renderBill(status: .succeeded).isRenderingPDF)
  #expect(!renderBill(status: .failed).isRenderingPDF)
  #expect(!renderBill(status: nil).isRenderingPDF)
}

@Test func billPDFPollingPollsOnlyForAPendingBill() {
  #expect(!BillPDFPolling.shouldPoll(nil))
  #expect(BillPDFPolling.shouldPoll(renderBill(status: .pending)))
  #expect(!BillPDFPolling.shouldPoll(renderBill(status: .succeeded)))
  #expect(!BillPDFPolling.shouldPoll(renderBill(status: .failed)))
  #expect(!BillPDFPolling.shouldPoll(renderBill(status: nil)))
}

@Test func communicationSendReadinessDoesNotDependOnPreviewState() {
  #expect(!communicationSendIsDisabled(
    isSending: false, hasSelectedRecipients: true, isRenderingPDF: false
  ))
  #expect(communicationSendIsDisabled(
    isSending: true, hasSelectedRecipients: true, isRenderingPDF: false
  ))
  #expect(communicationSendIsDisabled(
    isSending: false, hasSelectedRecipients: false, isRenderingPDF: false
  ))
  #expect(communicationSendIsDisabled(
    isSending: false, hasSelectedRecipients: true, isRenderingPDF: true
  ))
}

@Test func billPDFPollingUsesTheFiveSecondInterval() {
  #expect(BillPDFPolling.interval == .seconds(3))
}

@Test func permissiveCapabilitiesAllowEveryBillAction() {
  let capabilities = BillCapabilities.permissive

  #expect(capabilities.canDownloadInvoice)
  #expect(capabilities.canDownloadRecibo)
  #expect(capabilities.canOpenRecibo)
  #expect(capabilities.canSendInvoice)
  #expect(capabilities.canSendRecibo)
  #expect(capabilities.canRegenerate)
}

@Test func applyingRenderMetadataKeepsTheDetailOnlyDataOfTheLoadedBill() {
  // `POST .../regenerate` answers with the bill *summary* (no receipts), so applying that body
  // wholesale would blank out the receipt list until the next poll tick.
  let receipts = [
    Receipt(id: ReceiptID(rawValue: "receipt-1"), name: "comprovante.pdf", sortOrder: 0),
    Receipt(id: ReceiptID(rawValue: "receipt-2"), name: "boleto.pdf", sortOrder: 1),
  ]
  let lineItems = [
    BillLineItem(
      id: BillLineItemID(rawValue: "line-1"), description: "Aluguel",
      amount: Money(centavos: 250_000), kind: .fixed
    )
  ]
  let loaded = renderBill(
    status: .succeeded, billStatus: .sent, lineItems: lineItems, receipts: receipts,
    availableTransitions: [.paid], hasInvoice: true, hasRecibo: true, capabilities: .permissive
  )
  let blocked = BillCapabilities(
    canDownloadInvoice: false, canDownloadRecibo: false, canSendInvoice: false,
    canSendRecibo: false, canRegenerate: true
  )
  let queued = renderBill(
    status: .pending, billStatus: .paid, availableTransitions: [],
    hasInvoice: false, hasRecibo: false, capabilities: blocked
  )

  let merged = loaded.applyingRenderMetadata(from: queued)

  #expect(merged.receipts == receipts)
  #expect(merged.lineItems == lineItems)
  #expect(merged.pdfRenderStatus == .pending)
  #expect(merged.isRenderingPDF)
  #expect(merged.capabilities == blocked)
  #expect(!merged.hasInvoice)
  #expect(!merged.hasRecibo)
  #expect(merged.status == .paid)
  #expect(merged.availableTransitions == [])
}

@Test func billDefaultsToPermissiveCapabilitiesAndNoRenderStatus() {
  // Callers that predate the render-status contract (and the mock fixtures) must keep the
  // previous, unrestricted behavior instead of silently losing their action buttons.
  let bill = Bill(
    id: BillID(rawValue: "bill-legacy"),
    billingID: BillingID(rawValue: "billing-legacy"),
    referenceMonth: ReferenceMonth(year: 2026, month: 7),
    dueDate: nil,
    paidAt: nil,
    notes: "",
    status: .draft,
    lineItems: [],
    receipts: []
  )

  #expect(bill.pdfRenderStatus == nil)
  #expect(!bill.isRenderingPDF)
  #expect(bill.capabilities == .permissive)
}

import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

private func renderBill(
  status: PDFRenderStatus?,
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
    status: .sent,
    lineItems: [],
    receipts: [],
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

@Test func billPDFPollingUsesTheFiveSecondInterval() {
  #expect(BillPDFPolling.interval == .seconds(5))
}

@Test func permissiveCapabilitiesAllowEveryBillAction() {
  let capabilities = BillCapabilities.permissive

  #expect(capabilities.canDownloadInvoice)
  #expect(capabilities.canDownloadRecibo)
  #expect(capabilities.canSendInvoice)
  #expect(capabilities.canSendRecibo)
  #expect(capabilities.canRegenerate)
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

import RentivoCore

/// Contextual names used by every macOS download call.
enum MacOSDocumentPresentations {
  static func invoice(
    billingName: String, referenceMonth: ReferenceMonth
  ) -> DocumentPresentation {
    .invoice(billingName: billingName, referenceMonth: referenceMonth)
  }

  static func generatedReceipt(
    billingName: String, referenceMonth: ReferenceMonth
  ) -> DocumentPresentation {
    .generatedReceipt(billingName: billingName, referenceMonth: referenceMonth)
  }

  static func uploadedReceipt(
    _ receipt: Receipt,
    billingName: String,
    referenceMonth: ReferenceMonth
  ) -> DocumentPresentation {
    .uploadedReceipt(
      filename: receipt.name,
      billingName: billingName,
      referenceMonth: referenceMonth,
      mediaType: receipt.mediaType
    )
  }

  static func attachment(_ attachment: Attachment) -> DocumentPresentation {
    attachment.documentPresentation
  }
}

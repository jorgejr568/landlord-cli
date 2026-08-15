import Foundation

public enum BillingItemType: String, CaseIterable, Codable, Sendable {
  case fixed
  case variable

  public var label: String { self == .fixed ? "Fixo" : "Variável" }

  public var showsTemplateAmount: Bool { self == .fixed }

  public func normalizedTemplateAmount(_ centavos: Int) -> Int {
    self == .variable ? 0 : centavos
  }
}

public struct BillingItem: Identifiable, Hashable, Codable, Sendable {
  public let id: BillingItemID
  public var description: String
  public var amount: Money
  public var type: BillingItemType
  public var sortOrder: Int

  public init(id: BillingItemID, description: String, amount: Money, type: BillingItemType, sortOrder: Int) {
    self.id = id
    self.description = description
    self.amount = amount
    self.type = type
    self.sortOrder = sortOrder
  }

  init(id: UUID, description: String, amount: Money, type: BillingItemType, sortOrder: Int) {
    self.init(id: BillingItemID(rawValue: id.uuidString), description: description, amount: amount, type: type, sortOrder: sortOrder)
  }
}

public enum BillingOwner: Hashable, Codable, Sendable {
  case user(id: Int, name: String)
  case organization(id: OrganizationID, name: String)

  public var workspaceID: WorkspaceID {
    switch self {
    case .user: .personal
    case .organization(let id, _): WorkspaceID(rawValue: id.rawValue)
    }
  }

  public var id: WorkspaceID { workspaceID }

  public var name: String {
    switch self {
    case .user(_, let name), .organization(_, let name): name
    }
  }

  public var isOrganization: Bool {
    if case .organization = self { return true }
    return false
  }
}

public struct PixConfiguration: Hashable, Codable, Sendable {
  public var key: String
  public var merchantName: String
  public var merchantCity: String

  public init(key: String, merchantName: String, merchantCity: String) {
    self.key = key
    self.merchantName = merchantName
    self.merchantCity = merchantCity
  }

  public var isComplete: Bool {
    !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !merchantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !merchantCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  public var isEmpty: Bool {
    key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && merchantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && merchantCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

public struct BillingRecipient: Identifiable, Hashable, Codable, Sendable {
  public let id: RecipientID
  public var name: String
  public var email: String

  public init(id: RecipientID, name: String, email: String) {
    self.id = id
    self.name = name
    self.email = email
  }
}

public enum EmailAddress {
  private static let localPattern = #"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~.-]+$"#
  private static let domainLabelPattern = #"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$"#

  /// Mirrors `ContactInput` at the API boundary so a billing draft accepted here is accepted by
  /// the backend as well. Authentication addresses intentionally use a different server contract.
  public static func isValid(_ email: String) -> Bool {
    let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (3...320).contains(value.count), value.filter({ $0 == "@" }).count == 1,
      !value.contains(where: \.isWhitespace)
    else { return false }

    let parts = value.split(separator: "@", omittingEmptySubsequences: false)
    guard parts.count == 2 else { return false }
    let local = String(parts[0])
    let domain = String(parts[1])
    guard !local.isEmpty, local.count <= 64, !local.hasPrefix("."), !local.hasSuffix("."),
      !local.contains(".."),
      local.range(of: localPattern, options: .regularExpression) != nil,
      domain.count <= 253
    else { return false }

    let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
    return labels.count >= 2 && labels.allSatisfy {
      String($0).range(of: domainLabelPattern, options: .regularExpression) != nil
    }
  }
}

public struct BillingCapabilities: Hashable, Codable, Sendable {
  public var canEdit: Bool
  public var canReadBills: Bool
  public var canCreateBills: Bool
  public var canManageBills: Bool
  public var canReadExpenses: Bool
  public var canWriteExpenses: Bool
  public var canCreateExports: Bool
  public var canReadAttachments: Bool
  public var canWriteAttachments: Bool
  public var canReadTheme: Bool
  public var canManageTheme: Bool
  public var canUploadBillReceipts: Bool
  public var canDelete: Bool
  public var canTransfer: Bool

  public init(
    canEdit: Bool,
    canReadBills: Bool,
    canCreateBills: Bool,
    canManageBills: Bool,
    canReadExpenses: Bool,
    canWriteExpenses: Bool,
    canCreateExports: Bool,
    canReadAttachments: Bool,
    canWriteAttachments: Bool,
    canReadTheme: Bool,
    canManageTheme: Bool,
    canUploadBillReceipts: Bool,
    canDelete: Bool,
    canTransfer: Bool
  ) {
    self.canEdit = canEdit
    self.canReadBills = canReadBills
    self.canCreateBills = canCreateBills
    self.canManageBills = canManageBills
    self.canReadExpenses = canReadExpenses
    self.canWriteExpenses = canWriteExpenses
    self.canCreateExports = canCreateExports
    self.canReadAttachments = canReadAttachments
    self.canWriteAttachments = canWriteAttachments
    self.canReadTheme = canReadTheme
    self.canManageTheme = canManageTheme
    self.canUploadBillReceipts = canUploadBillReceipts
    self.canDelete = canDelete
    self.canTransfer = canTransfer
  }

  public static let full = BillingCapabilities(
    canEdit: true, canReadBills: true, canCreateBills: true, canManageBills: true,
    canReadExpenses: true, canWriteExpenses: true, canCreateExports: true,
    canReadAttachments: true, canWriteAttachments: true, canReadTheme: true,
    canManageTheme: true, canUploadBillReceipts: true, canDelete: true, canTransfer: true
  )

  public static let viewer = BillingCapabilities(
    canEdit: false, canReadBills: true, canCreateBills: false, canManageBills: false,
    canReadExpenses: true, canWriteExpenses: false, canCreateExports: false,
    canReadAttachments: true, canWriteAttachments: false, canReadTheme: true,
    canManageTheme: false, canUploadBillReceipts: false, canDelete: false, canTransfer: false
  )

  public var allowsEveryAction: Bool {
    [
      canEdit, canReadBills, canCreateBills, canManageBills, canReadExpenses,
      canWriteExpenses, canCreateExports, canReadAttachments, canWriteAttachments,
      canReadTheme, canManageTheme, canUploadBillReceipts, canDelete, canTransfer,
    ].allSatisfy { $0 }
  }
}

public struct Billing: Identifiable, Hashable, Codable, Sendable {
  public let id: BillingID
  public var name: String
  public var description: String
  public var owner: BillingOwner
  public var items: [BillingItem]
  public var pixOverride: PixConfiguration?
  public var pixNeedsSetup: Bool
  public var recipients: [BillingRecipient]
  public var replyTo: [BillingRecipient]
  public var communicationTemplates: [CommunicationTemplate]
  public var capabilities: BillingCapabilities

  public init(
    id: BillingID,
    name: String,
    description: String,
    owner: BillingOwner,
    items: [BillingItem],
    pixOverride: PixConfiguration? = nil,
    pixNeedsSetup: Bool = false,
    recipients: [BillingRecipient] = [],
    replyTo: [BillingRecipient] = [],
    communicationTemplates: [CommunicationTemplate] = [],
    capabilities: BillingCapabilities = .full
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.owner = owner
    self.items = items
    self.pixOverride = pixOverride
    self.pixNeedsSetup = pixNeedsSetup
    self.recipients = recipients
    self.replyTo = replyTo
    self.communicationTemplates = communicationTemplates
    self.capabilities = capabilities
  }

  public var fixedSubtotal: Money {
    items.filter { $0.type == .fixed }.map(\.amount).reduce(.zero, +)
  }

  /// Creating a bill needs both the write capability and a complete effective PIX configuration.
  /// The backend exposes these as separate fields and rejects creation when PIX is incomplete.
  public var canGenerateBills: Bool {
    capabilities.canCreateBills && !pixNeedsSetup
  }

  /// The transfer endpoint accepts only user-owned cobranças and advertises authorization through
  /// the per-billing capability returned by the backend.
  public var canTransferToOrganization: Bool {
    !owner.isOrganization && capabilities.canTransfer
  }

  public func template(for type: CommunicationType) -> CommunicationTemplate? {
    communicationTemplates.first { $0.commType == type }
  }

  mutating func replaceCommunicationTemplate(_ template: CommunicationTemplate) {
    if let index = communicationTemplates.firstIndex(where: { $0.commType == template.commType }) {
      communicationTemplates[index] = template
    } else {
      communicationTemplates.append(template)
    }
  }
}

public struct BillingDraft: Hashable, Sendable {
  public var name: String
  public var description: String
  public var owner: BillingOwner
  public var items: [BillingItem]
  public var pixOverride: PixConfiguration?
  public var recipients: [BillingRecipient]
  public var replyTo: [BillingRecipient]

  public init(
    name: String,
    description: String,
    owner: BillingOwner,
    items: [BillingItem],
    pixOverride: PixConfiguration? = nil,
    recipients: [BillingRecipient] = [],
    replyTo: [BillingRecipient] = []
  ) {
    self.name = name
    self.description = description
    self.owner = owner
    self.items = items
    self.pixOverride = pixOverride
    self.recipients = recipients
    self.replyTo = replyTo
  }

  public static let empty = BillingDraft(
    name: "",
    description: "",
    owner: .user(id: StableID.userAna, name: "Pessoal"),
    items: []
  )

  public func validate() -> [ValidationIssue] {
    var issues: [ValidationIssue] = []
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalizedName.isEmpty {
      issues.append(ValidationIssue(field: .name, message: "Informe o nome da cobrança."))
    } else if normalizedName.unicodeScalars.count > 255 {
      issues.append(
        ValidationIssue(field: .name, message: "O nome deve ter no máximo 255 caracteres.")
      )
    }
    if description.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count > 2_000 {
      issues.append(
        ValidationIssue(
          field: .description, message: "A descrição deve ter no máximo 2000 caracteres."
        )
      )
    }
    if items.isEmpty {
      issues.append(
        ValidationIssue(field: .items, message: "Adicione ao menos um item recorrente.")
      )
    }
    if items.contains(where: {
      $0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }) {
      issues.append(
        ValidationIssue(field: .itemDescription, message: "Descreva todos os itens.")
      )
    } else if items.contains(where: {
      $0.description.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count > 255
    }) {
      issues.append(
        ValidationIssue(
          field: .itemDescription,
          message: "Descreva todos os itens em até 255 caracteres."
        )
      )
    }
    if items.contains(where: { $0.amount.centavos < 0 }) {
      issues.append(
        ValidationIssue(field: .itemAmount, message: "Os valores não podem ser negativos.")
      )
    }
    if !Money.fitsPersistedTotal(
      items.lazy.filter { $0.type == .fixed }.map { $0.amount.centavos }
    ) {
      issues.append(
        ValidationIssue(
          field: .itemAmount,
          message: "O valor total deve ser de no máximo R$ 21.474.836,47."
        )
      )
    }
    if items.contains(where: { $0.type == .variable && $0.amount.centavos != 0 }) {
      issues.append(
        ValidationIssue(
          field: .itemAmount,
          message: "Itens variáveis devem ter valor zero no modelo."
        )
      )
    }
    if let pixOverride,
      (pixOverride.merchantName.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
        > 25
        || pixOverride.merchantCity.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars
          .count > 15)
    {
      issues.append(
        ValidationIssue(
          field: .pix, message: "O recebedor PIX aceita 25 caracteres no nome e 15 na cidade."
        )
      )
    }
    if recipients.contains(where: {
      let normalizedName = $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
      return normalizedName.isEmpty || normalizedName.unicodeScalars.count > 255
        || !EmailAddress.isValid($0.email.trimmingCharacters(in: .whitespacesAndNewlines))
    }) {
      issues.append(
        ValidationIssue(
          field: .recipient,
          message: "Informe nome e e-mail válidos para todos os destinatários."
        )
      )
    } else {
      // The send endpoint requires distinct recipient uuids and the server keys contacts by
      // email, so duplicates here would break the communication flow later.
      let emails = recipients.map {
        $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      }
      if Set(emails).count != emails.count {
        issues.append(
          ValidationIssue(field: .recipient, message: "Remova os destinatários repetidos.")
        )
      }
    }
    if replyTo.contains(where: {
      let normalizedName = $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
      return normalizedName.isEmpty || normalizedName.unicodeScalars.count > 255
        || !EmailAddress.isValid($0.email.trimmingCharacters(in: .whitespacesAndNewlines))
    }) {
      issues.append(
        ValidationIssue(
          field: .replyTo,
          message: "Informe nome e e-mail válidos para todos os contatos de resposta."
        )
      )
    } else {
      let emails = replyTo.map {
        $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      }
      if Set(emails).count != emails.count {
        issues.append(
          ValidationIssue(field: .replyTo, message: "Remova os contatos de resposta repetidos.")
        )
      }
    }
    return issues
  }
}

public enum ValidationField: Hashable, Sendable {
  case name
  case description
  case items
  case itemDescription
  case itemAmount
  case pix
  case recipient
  case replyTo
}

public struct ValidationIssue: Hashable, Sendable {
  public let field: ValidationField
  public let message: String

  public init(field: ValidationField, message: String) {
    self.field = field
    self.message = message
  }
}

public enum BillLineItemKind: String, CaseIterable, Codable, Sendable {
  case fixed
  case variable
  case extra
}

public struct BillLineItem: Identifiable, Hashable, Codable, Sendable {
  public let id: BillLineItemID
  public var description: String
  public var amount: Money
  public var kind: BillLineItemKind

  public init(id: BillLineItemID, description: String, amount: Money, kind: BillLineItemKind) {
    self.id = id
    self.description = description
    self.amount = amount
    self.kind = kind
  }

  init(id: UUID, description: String, amount: Money, kind: BillLineItemKind) {
    self.init(id: BillLineItemID(rawValue: id.uuidString), description: description, amount: amount, kind: kind)
  }
}

public enum BillStatus: String, CaseIterable, Codable, Sendable {
  case draft
  case published
  case sent
  case paid
  case cancelled
  case delayedPayment = "delayed_payment"

  public var allowedTransitions: Set<BillStatus> {
    switch self {
    case .draft: [.published, .cancelled]
    case .published: [.sent, .paid, .cancelled]
    case .sent: [.paid, .delayedPayment, .cancelled]
    case .delayedPayment: [.paid, .cancelled]
    case .paid, .cancelled: []
    }
  }

  public func canTransition(to target: BillStatus) -> Bool {
    allowedTransitions.contains(target)
  }

  public var label: String {
    switch self {
    case .draft: "Rascunho"
    case .published: "Publicada"
    case .sent: "Enviada"
    case .paid: "Paga"
    case .cancelled: "Cancelada"
    case .delayedPayment: "Pagamento atrasado"
    }
  }
}

public struct Receipt: Identifiable, Hashable, Codable, Sendable {
  public let id: ReceiptID
  public var name: String
  public var sortOrder: Int
  public var mediaType: String
  public var byteCount: Int
  public var createdAt: Date?

  public init(
    id: ReceiptID, name: String, sortOrder: Int,
    mediaType: String = "application/octet-stream", byteCount: Int = 0,
    createdAt: Date? = nil
  ) {
    self.id = id
    self.name = name
    self.sortOrder = sortOrder
    self.mediaType = mediaType
    self.byteCount = byteCount
    self.createdAt = createdAt
  }
}

public struct Attachment: Identifiable, Hashable, Codable, Sendable {
  public let id: AttachmentID
  public var name: String
  public var mediaType: String
  public var byteCount: Int

  public init(id: AttachmentID, name: String, mediaType: String, byteCount: Int) {
    self.id = id
    self.name = name
    self.mediaType = mediaType
    self.byteCount = byteCount
  }
}

/// The queued export currently contains the billing's bill rows only. Keep the client copy and
/// format picker tied to the `ExportCreateRequest` and `ExportService` backend contract.
public enum BillingExportContract {
  public static let formats = ["csv", "xlsx"]
  public static let includedSections = ["Faturas"]
}

/// The server's asynchronous PDF render state for a bill. The wire literals are exactly
/// `"pending" | "succeeded" | "failed"`; anything else (including `null`) decodes to `nil`.
public enum PDFRenderStatus: String, Hashable, Codable, Sendable {
  case pending
  case succeeded
  case failed
}

/// Server-authoritative, per-bill action gates. The server folds the pending render state into
/// these flags, so the UI can treat them as the single source of truth for what is allowed now.
public struct BillCapabilities: Hashable, Codable, Sendable {
  public var canDownloadInvoice: Bool
  public var canDownloadRecibo: Bool
  public var canOpenRecibo: Bool
  public var canSendInvoice: Bool
  public var canSendRecibo: Bool
  public var canRegenerate: Bool
  public var canEdit: Bool
  public var canDelete: Bool
  public var canTransition: Bool
  public var canUploadReceipts: Bool
  public var canDeleteReceipts: Bool
  public var canReorderReceipts: Bool
  public var canCompose: Bool

  public init(
    canDownloadInvoice: Bool,
    canDownloadRecibo: Bool,
    canSendInvoice: Bool,
    canSendRecibo: Bool,
    canRegenerate: Bool,
    canEdit: Bool = true,
    canDelete: Bool = true,
    canTransition: Bool = true,
    canUploadReceipts: Bool = true,
    canDeleteReceipts: Bool = true,
    canReorderReceipts: Bool = true,
    canCompose: Bool = true,
    canOpenRecibo: Bool = false
  ) {
    self.canDownloadInvoice = canDownloadInvoice
    self.canDownloadRecibo = canDownloadRecibo
    self.canOpenRecibo = canOpenRecibo
    self.canSendInvoice = canSendInvoice
    self.canSendRecibo = canSendRecibo
    self.canRegenerate = canRegenerate
    self.canEdit = canEdit
    self.canDelete = canDelete
    self.canTransition = canTransition
    self.canUploadReceipts = canUploadReceipts
    self.canDeleteReceipts = canDeleteReceipts
    self.canReorderReceipts = canReorderReceipts
    self.canCompose = canCompose
  }

  /// Used when no server capabilities are available (older payloads, the mock store). Gating is a
  /// server concern; without an answer the client must not invent restrictions of its own.
  public static let permissive = BillCapabilities(
    canDownloadInvoice: true, canDownloadRecibo: true, canSendInvoice: true,
    canSendRecibo: true, canRegenerate: true, canOpenRecibo: true
  )
}

/// Poll cadence for a bill whose PDF is still rendering.
public enum BillPDFPolling {
  public static let interval: Duration = .seconds(3)

  /// Poll only while the loaded bill reports a pending render; stop on success, failure, an
  /// unknown status, or no bill at all.
  public static func shouldPoll(_ bill: Bill?) -> Bool {
    bill?.isRenderingPDF == true
  }
}

public func communicationSendIsDisabled(
  isSending: Bool, hasSelectedRecipients: Bool, isRenderingPDF: Bool
) -> Bool {
  isSending || !hasSelectedRecipients || isRenderingPDF
}

public enum CommunicationContent {
  public static let maximumSubjectLength = 998
  public static let maximumMessageByteCount = 4_096

  public static func normalizedSubject(_ subject: String) -> String {
    subject.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func normalizedMessage(_ message: String) -> String {
    message.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func validationMessage(subject: String, message: String) -> String? {
    let subject = normalizedSubject(subject)
    let message = normalizedMessage(message)
    if subject.isEmpty { return "Informe o assunto." }
    if subject.unicodeScalars.count > maximumSubjectLength {
      return "O assunto deve ter no máximo 998 caracteres."
    }
    if message.isEmpty { return "Informe o corpo da mensagem." }
    if message.utf8.count > maximumMessageByteCount {
      return "A mensagem deve ter no máximo 4096 bytes."
    }
    return nil
  }
}

public struct BillTransition: Hashable, Codable, Sendable {
  public let target: BillStatus
  public let label: String
  public let style: String
  public let requiresConfirmation: Bool

  public init(
    target: BillStatus, label: String, style: String, requiresConfirmation: Bool
  ) {
    self.target = target
    self.label = label
    self.style = style
    self.requiresConfirmation = requiresConfirmation
  }

  fileprivate init(fallbackTarget target: BillStatus, from current: BillStatus) {
    let consequential = target == .paid || target == .cancelled
      || (current == .published && target == .draft)
      || (current == .sent && target == .published)
      || (current == .paid && target == .sent)
      || (current == .cancelled && target == .draft)
    let destructive = target == .cancelled
      || (current == .published && target == .draft)
      || (current == .sent && target == .published)
      || (current == .paid && target == .sent)
    self.init(
      target: target,
      label: "Marcar como \(target.label.lowercased())",
      style: destructive ? "danger" : "primary",
      requiresConfirmation: consequential
    )
  }
}

public struct BillCommunication: Identifiable, Hashable, Codable, Sendable {
  public let id: CommunicationID
  public let commType: CommunicationType?
  public let status: String
  public let createdAt: Date?
  public let sentAt: Date?
  public let recipientName: String?
  public let recipientEmail: String?
  public let subject: String?

  public var isRedacted: Bool { recipientEmail == nil }
  public var deliveryLabel: String {
    switch status {
    case "sent": "Enviado"
    case "failed": "Falhou"
    default: "Na fila"
    }
  }

  public init(
    id: CommunicationID, commType: CommunicationType?, status: String,
    createdAt: Date?, sentAt: Date?, recipientName: String?, recipientEmail: String?,
    subject: String?
  ) {
    self.id = id
    self.commType = commType
    self.status = status
    self.createdAt = createdAt
    self.sentAt = sentAt
    self.recipientName = recipientName
    self.recipientEmail = recipientEmail
    self.subject = subject
  }
}

public struct Bill: Identifiable, Hashable, Codable, Sendable {
  public let id: BillID
  public let billingID: BillingID
  public var referenceMonth: ReferenceMonth
  /// `nil` when the server has no due date for this bill (`due_date: null` on the wire) —
  /// distinct from a date, and never a sentinel.
  public var dueDate: DateOnly?
  public var paidAt: DateOnly?
  public var notes: String
  public var status: BillStatus
  public var lineItems: [BillLineItem]
  public var receipts: [Receipt]
  public var communications: [BillCommunication]
  public var statusUpdatedAt: Date?
  public var createdAt: Date?
  /// Server-authoritative transitions for this specific bill, when the API
  /// supplies them. `nil` means "not provided by this response" — callers
  /// should fall back to `status.allowedTransitions` (see `effectiveTransitions`).
  public var availableTransitions: [BillStatus]?
  /// Presentation and confirmation policy accompanying `availableTransitions` on current API
  /// responses. Kept separately so older snapshots that only carry statuses still decode.
  public var availableTransitionActions: [BillTransition]?
  /// Server-authoritative total for this bill, when the API supplies it.
  /// `nil` means "not provided by this response" — callers should fall back
  /// to the locally computed `total` (see `effectiveTotal`).
  public var serverTotal: Money?
  /// `nil` means the bill was never rendered, or the server reported a status this client does
  /// not model — either way, not "rendering".
  public var pdfRenderStatus: PDFRenderStatus?
  public var hasInvoice: Bool
  public var hasRecibo: Bool
  public var capabilities: BillCapabilities

  public init(
    id: BillID,
    billingID: BillingID,
    referenceMonth: ReferenceMonth,
    dueDate: DateOnly?,
    paidAt: DateOnly?,
    notes: String,
    status: BillStatus,
    lineItems: [BillLineItem],
    receipts: [Receipt],
    communications: [BillCommunication] = [],
    statusUpdatedAt: Date? = nil,
    createdAt: Date? = nil,
    availableTransitions: [BillStatus]? = nil,
    availableTransitionActions: [BillTransition]? = nil,
    serverTotal: Money? = nil,
    pdfRenderStatus: PDFRenderStatus? = nil,
    hasInvoice: Bool = false,
    hasRecibo: Bool = false,
    capabilities: BillCapabilities = .permissive
  ) {
    self.id = id
    self.billingID = billingID
    self.referenceMonth = referenceMonth
    self.dueDate = dueDate
    self.paidAt = paidAt
    self.notes = notes
    self.status = status
    self.lineItems = lineItems
    self.receipts = receipts
    self.communications = communications
    self.statusUpdatedAt = statusUpdatedAt
    self.createdAt = createdAt
    self.availableTransitions = availableTransitions
    self.availableTransitionActions = availableTransitionActions
    self.serverTotal = serverTotal
    self.pdfRenderStatus = pdfRenderStatus
    self.hasInvoice = hasInvoice
    self.hasRecibo = hasRecibo
    self.capabilities = capabilities
  }

  /// The PDF for this bill is being (re)generated in the background, so any document already on
  /// the server may be stale and must not be opened or e-mailed yet.
  public var isRenderingPDF: Bool { pdfRenderStatus == .pending }

  public var total: Money {
    lineItems.map(\.amount).reduce(.zero, +)
  }

  /// The locally computed total, unless the server supplied an authoritative
  /// one for this bill.
  public var effectiveTotal: Money {
    serverTotal ?? total
  }

  /// The local state-machine rules (`BillStatus.allowedTransitions`), unless
  /// the server supplied authoritative transitions for this specific bill.
  public var effectiveTransitions: Set<BillStatus> {
    if let availableTransitions { return Set(availableTransitions) }
    return status.allowedTransitions
  }

  /// Server-authored labels/styles/confirmation gates, with a conservative local policy for demo
  /// and legacy payloads that only have status targets.
  public var effectiveTransitionActions: [BillTransition] {
    if let availableTransitionActions { return availableTransitionActions }
    return effectiveTransitions.sorted { $0.rawValue < $1.rawValue }.map {
      BillTransition(fallbackTarget: $0, from: status)
    }
  }

  public func canTransition(to target: BillStatus) -> Bool {
    effectiveTransitions.contains(target)
  }

  /// Folds a freshly returned *bill summary* into this loaded bill: render state, action gates and
  /// status come from `updated`, while detail-only data (receipts, line items) stays as loaded.
  /// `POST .../regenerate` answers with the summary shape, which carries no receipts at all, so
  /// replacing the loaded bill with it would empty the receipt list until the next poll tick.
  public func applyingRenderMetadata(from updated: Bill) -> Bill {
    var merged = self
    merged.pdfRenderStatus = updated.pdfRenderStatus
    merged.capabilities = updated.capabilities
    merged.hasInvoice = updated.hasInvoice
    merged.hasRecibo = updated.hasRecibo
    merged.status = updated.status
    merged.statusUpdatedAt = updated.statusUpdatedAt
    if let createdAt = updated.createdAt { merged.createdAt = createdAt }
    merged.availableTransitions = updated.availableTransitions
    merged.availableTransitionActions = updated.availableTransitionActions
    return merged
  }
}

public struct BillDraft: Hashable, Sendable {
  public let billingID: BillingID
  public var referenceMonth: ReferenceMonth
  public var dueDate: DateOnly?
  public var notes: String
  public var lineItems: [BillLineItem]

  public init(
    billingID: BillingID,
    referenceMonth: ReferenceMonth,
    dueDate: DateOnly?,
    notes: String,
    lineItems: [BillLineItem]
  ) {
    self.billingID = billingID
    self.referenceMonth = referenceMonth
    self.dueDate = dueDate
    self.notes = notes
    self.lineItems = lineItems
  }

  public var total: Money {
    lineItems.map(\.amount).reduce(.zero, +)
  }

  public func validate() -> [ValidationIssue] {
    var issues: [ValidationIssue] = []
    if lineItems.isEmpty {
      issues.append(ValidationIssue(field: .items, message: "Adicione ao menos um item."))
    }
    if lineItems.contains(where: {
      $0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }) {
      issues.append(
        ValidationIssue(field: .itemDescription, message: "Descreva todos os itens da fatura.")
      )
    } else if lineItems.contains(where: { $0.description.unicodeScalars.count > 255 }) {
      issues.append(
        ValidationIssue(
          field: .itemDescription,
          message: "Descreva todos os itens da fatura em até 255 caracteres."
        )
      )
    }
    if lineItems.contains(where: { $0.kind != .extra && $0.amount.centavos < 0 }) {
      issues.append(
        ValidationIssue(field: .itemAmount, message: "Os valores não podem ser negativos.")
      )
    }
    // The server requires `BillExtraRequest.amount` to be strictly positive
    // (`exclusiveMinimum: 0`): a zero or negative extra always 422s.
    if lineItems.contains(where: { $0.kind == .extra && $0.amount.centavos <= 0 }) {
      issues.append(
        ValidationIssue(
          field: .itemAmount, message: "Os itens extras devem ter valor maior que zero."
        )
      )
    }
    if !Money.fitsPersistedTotal(lineItems.lazy.map { $0.amount.centavos }) {
      issues.append(
        ValidationIssue(
          field: .itemAmount,
          message: "O valor total deve ser de no máximo R$ 21.474.836,47."
        )
      )
    }
    return issues
  }
}

public enum ExpenseCategory: String, CaseIterable, Codable, Sendable {
  case propertyTax = "iptu"
  case condominium = "condominio"
  case maintenance = "manutencao"
  case insurance = "seguro"
  case other = "outros"

  public var label: String {
    switch self {
    case .propertyTax: "IPTU"
    case .condominium: "Condomínio"
    case .maintenance: "Manutenção"
    case .insurance: "Seguro"
    case .other: "Outros"
    }
  }
}

public enum ExpenseInput {
  public static let maximumDescriptionLength = 2_000

  public static func normalizedDescription(_ description: String) -> String {
    description.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func isValidDescription(_ description: String) -> Bool {
    let normalized = normalizedDescription(description)
    return !normalized.isEmpty
      && normalized.unicodeScalars.count <= maximumDescriptionLength
  }
}

public struct Expense: Identifiable, Hashable, Codable, Sendable {
  public let id: ExpenseID
  public let billingID: BillingID
  public var description: String
  public var amount: Money
  public var category: ExpenseCategory
  public var incurredOn: DateOnly

  public init(
    id: ExpenseID,
    billingID: BillingID,
    description: String,
    amount: Money,
    category: ExpenseCategory,
    incurredOn: DateOnly
  ) {
    self.id = id
    self.billingID = billingID
    self.description = description
    self.amount = amount
    self.category = category
    self.incurredOn = incurredOn
  }
}

public enum CommunicationType: String, CaseIterable, Codable, Sendable {
  case billReady = "bill_ready"
  case paymentReceipt = "payment_receipt"

  public var label: String {
    switch self {
    case .billReady: "Fatura"
    case .paymentReceipt: "Recibo de pagamento"
    }
  }
}

public enum CommunicationSaveScope: String, Codable, Sendable {
  case billing
  case owner
}

public struct CommunicationTemplate: Hashable, Codable, Sendable {
  public let commType: CommunicationType
  public let subject: String
  public let body: String

  public init(commType: CommunicationType, subject: String, body: String) {
    self.commType = commType
    self.subject = subject
    self.body = body
  }
}

public struct CommunicationRecord: Identifiable, Hashable, Codable, Sendable {
  public let id: CommunicationID
  public let billingID: BillingID
  public var billID: BillID?
  public var recipients: [String]
  public var subject: String
  public var message: String
  public var sentAt: Date

  public init(
    id: CommunicationID,
    billingID: BillingID,
    billID: BillID?,
    recipients: [String],
    subject: String,
    message: String,
    sentAt: Date
  ) {
    self.id = id
    self.billingID = billingID
    self.billID = billID
    self.recipients = recipients
    self.subject = subject
    self.message = message
    self.sentAt = sentAt
  }
}

public struct CommunicationPreview: Identifiable, Hashable, Sendable {
  public let id = UUID()
  public let html: String
  public let severeWarnings: [String]
  public let mildWarnings: [String]

  public init(html: String, severeWarnings: [String], mildWarnings: [String]) {
    self.html = html
    self.severeWarnings = severeWarnings
    self.mildWarnings = mildWarnings
  }
}

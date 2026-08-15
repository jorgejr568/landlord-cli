import Foundation

// Wire DTOs for the `/api/v1` JSON contract, decoded and encoded by `APIRentivoStore`. They
// mirror the server payloads (snake_case keys, nullable fields) and carry no domain logic;
// the store owns the translation to and from the `Domain` models.

struct RemoteOrganizationList: Decodable { let items: [RemoteOrganization] }
struct RemoteOrganization: Decodable {
  let uuid, name, currentRole: String; let enforceMFA: Bool; let capabilities: RemoteOrganizationCapabilities
  let settings: RemoteOrganizationSettings?
  let members: [RemoteOrganizationMember]?
  enum CodingKeys: String, CodingKey { case uuid, name, capabilities, settings, members; case currentRole = "current_role"; case enforceMFA = "enforce_mfa" }
}
struct RemoteOrganizationCapabilities: Decodable { let canManage, canInvite, canCreateBilling, canViewBillingStats: Bool; enum CodingKeys: String, CodingKey { case canManage = "can_manage"; case canInvite = "can_invite"; case canCreateBilling = "can_create_billing"; case canViewBillingStats = "can_view_billing_stats" } }
struct RemoteOrganizationSettings: Decodable { let pixKey, pixMerchantName, pixMerchantCity: String; enum CodingKeys: String, CodingKey { case pixKey = "pix_key"; case pixMerchantName = "pix_merchant_name"; case pixMerchantCity = "pix_merchant_city" } }
struct RemoteOrganizationMember: Decodable { let userID: Int; let email, role: String; let isCurrentUser: Bool?; enum CodingKeys: String, CodingKey { case email, role; case userID = "user_id"; case isCurrentUser = "is_current_user" } }
struct RemoteOrganizationCreate: Encodable {
  let name, pixKey, pixMerchantName, pixMerchantCity: String
  enum CodingKeys: String, CodingKey {
    case name
    case pixKey = "pix_key"
    case pixMerchantName = "pix_merchant_name"
    case pixMerchantCity = "pix_merchant_city"
  }
  init(draft: OrganizationDraft) {
    name = draft.name
    pixKey = draft.pix?.key ?? ""
    pixMerchantName = draft.pix?.merchantName ?? ""
    pixMerchantCity = draft.pix?.merchantCity ?? ""
  }
}
struct RemoteOrganizationUpdate: Encodable {
  let name, pixKey, pixMerchantName, pixMerchantCity: String
  enum CodingKeys: String, CodingKey {
    case name
    case pixKey = "pix_key"
    case pixMerchantName = "pix_merchant_name"
    case pixMerchantCity = "pix_merchant_city"
  }
  init(draft: OrganizationDraft) {
    name = draft.name
    pixKey = draft.pix?.key ?? ""
    pixMerchantName = draft.pix?.merchantName ?? ""
    pixMerchantCity = draft.pix?.merchantCity ?? ""
  }
}
struct RemoteMemberRole: Encodable { let role: String }
struct RemoteInviteCreate: Encodable { let email, role: String }
struct RemoteMFAPolicy: Encodable { let enforceMFA: Bool; enum CodingKeys: String, CodingKey { case enforceMFA = "enforce_mfa" } }
struct RemoteMFAPolicyResponse: Decodable { let enforceMFA, mfaSetupRequired: Bool; enum CodingKeys: String, CodingKey { case enforceMFA = "enforce_mfa"; case mfaSetupRequired = "mfa_setup_required" } }
struct RemoteBillingTransfer: Encodable { let organizationID: String; enum CodingKeys: String, CodingKey { case organizationID = "organization_uuid" } }
struct RemoteInvitation: Decodable { let uuid, invitedEmail, role, status: String; enum CodingKeys: String, CodingKey { case uuid, role, status; case invitedEmail = "invited_email" } }
struct RemotePendingInvitationList: Decodable { let items: [RemotePendingInvitation] }
struct RemotePendingInvitation: Decodable {
  let uuid, organizationUUID, organizationName, role, invitedByEmail: String
  let enforceMFA: Bool
  enum CodingKeys: String, CodingKey {
    case uuid, role
    case organizationUUID = "organization_uuid"
    case organizationName = "organization_name"
    case invitedByEmail = "invited_by_email"
    case enforceMFA = "enforce_mfa"
  }
}
struct RemoteInvitationAcceptance: Decodable {
  let organizationUUID: String
  let mfaSetupRequired: Bool
  enum CodingKeys: String, CodingKey {
    case organizationUUID = "organization_uuid"
    case mfaSetupRequired = "mfa_setup_required"
  }
}
struct RemoteSecuritySummary: Decodable {
  let profile: RemoteProfile
  let totp: RemoteTOTPStatus
  let mfa: RemoteMFAStatus
  let passkeys: [RemotePasskey]
}
struct RemoteTOTPStatus: Decodable { let enabled: Bool; let recoveryCodesRemaining: Int; enum CodingKeys: String, CodingKey { case enabled; case recoveryCodesRemaining = "recovery_codes_remaining" } }
struct RemoteMFAStatus: Decodable {
  let setupRequired, organizationEnforced: Bool
  enum CodingKeys: String, CodingKey {
    case setupRequired = "setup_required"
    case organizationEnforced = "organization_enforced"
  }
}
struct RemoteTOTPSetup: Decodable {
  let secret, provisioningURI, qrCodeBase64: String
  enum CodingKeys: String, CodingKey {
    case secret
    case provisioningURI = "provisioning_uri"
    case qrCodeBase64 = "qr_code_base64"
  }
}
struct RemoteTOTPConfirm: Encodable { let code: String }
struct RemoteTOTPDisable: Encodable { let password: String }
struct RemotePasswordChange: Encodable {
  let currentPassword, newPassword, confirmPassword: String
  enum CodingKeys: String, CodingKey {
    case currentPassword = "current_password"
    case newPassword = "new_password"
    case confirmPassword = "confirm_password"
  }
}
struct RemotePasskey: Decodable { let uuid, name, createdAt: String; let lastUsedAt: String?; enum CodingKeys: String, CodingKey { case uuid, name; case createdAt = "created_at"; case lastUsedAt = "last_used_at" } }
struct RemoteRecoveryCodes: Decodable { let recoveryCodes: [String]; enum CodingKeys: String, CodingKey { case recoveryCodes = "recovery_codes" } }
struct RemoteContactInput: Encodable {
  let name, email: String
  init(name: String, email: String) { self.name = name; self.email = email }
  init(_ recipient: BillingRecipient) { name = recipient.name; email = recipient.email }
}
struct RemoteCommunicationPreviewRequest: Encodable {
  let subject: String
  let body: String
}
struct RemoteCommunicationPreview: Decodable {
  let html: String
  let severe: [String]
  let mild: [String]
}
struct RemoteCommunicationSendRequest: Encodable {
  let billID, commType, subject, body: String
  let recipientIDs: [String]
  let acknowledgeWarning: Bool
  let saveScope: String?
  enum CodingKeys: String, CodingKey {
    case subject, body
    case billID = "bill_uuid"
    case commType = "comm_type"
    case recipientIDs = "recipient_uuids"
    case acknowledgeWarning = "acknowledge_warning"
    case saveScope = "save_scope"
  }
  init(
    billID: String, commType: String, recipientIDs: [String],
    subject: String, message: String, acknowledgeWarning: Bool, saveScope: String?
  ) {
    self.billID = billID; self.commType = commType; self.subject = subject; body = message
    self.recipientIDs = recipientIDs
    self.acknowledgeWarning = acknowledgeWarning
    self.saveScope = saveScope
  }
}
struct RemoteCommunicationSend: Decodable { let queuedCount: Int; enum CodingKeys: String, CodingKey { case queuedCount = "queued_count" } }
struct RemoteExportRequest: Encodable { let format: String }
struct RemoteExport: Decodable { let format, status: String }
struct RemoteReceiptUpload: Decodable { let items: [RemoteReceipt] }
struct RemoteReceiptList: Decodable { let items: [RemoteReceipt] }
struct RemoteReceiptOrder: Encodable { let order: [String] }
struct RemoteReceipt: Decodable {
  let uuid, filename, contentType: String
  let fileSize, sortOrder: Int
  let createdAt: String?
  enum CodingKeys: String, CodingKey {
    case uuid, filename
    case contentType = "content_type"
    case fileSize = "file_size"
    case sortOrder = "sort_order"
    case createdAt = "created_at"
  }
}
struct RemoteAttachmentList: Decodable { let items: [RemoteAttachment] }
struct RemoteAttachment: Decodable {
  let uuid, name, contentType: String
  let fileSize: Int
  enum CodingKeys: String, CodingKey {
    case uuid, name
    case contentType = "content_type"
    case fileSize = "file_size"
  }
}
struct RemoteAPIKeyList: Decodable { let items: [RemoteAPIKey] }
struct RemoteAPIKeyOptions: Decodable {
  let scopes: [String]
  let personalWorkspace: RemoteAPIKeyPersonalWorkspace
  let organizations: [RemoteAPIKeyOrganizationWorkspace]
  let defaultExpirationDays, maxExpirationDays: Int
  enum CodingKeys: String, CodingKey {
    case scopes, organizations
    case personalWorkspace = "personal_workspace"
    case defaultExpirationDays = "default_expiration_days"
    case maxExpirationDays = "max_expiration_days"
  }
}
struct RemoteAPIKeyPersonalWorkspace: Decodable {
  let resourceType, resourceID: String
  enum CodingKeys: String, CodingKey {
    case resourceType = "resource_type"
    case resourceID = "resource_id"
  }
}
struct RemoteAPIKeyOrganizationWorkspace: Decodable {
  let resourceType, resourceID, name: String
  enum CodingKeys: String, CodingKey {
    case name
    case resourceType = "resource_type"
    case resourceID = "resource_id"
  }
}
struct RemoteAPIKey: Decodable {
  let uuid, name, hint, expiresAt, createdAt: String
  let scopes: [String]
  let grants: [RemoteAPIKeyGrant]
  let lastUsedAt, revokedAt: String?
  enum CodingKeys: String, CodingKey {
    case uuid, name, hint, scopes, grants
    case expiresAt = "expires_at"
    case lastUsedAt = "last_used_at"
    case createdAt = "created_at"
    case revokedAt = "revoked_at"
  }
}
struct RemoteCreatedAPIKey: Decodable {
  let secret: String
  let apiKey: RemoteAPIKey
  enum CodingKeys: String, CodingKey {
    case secret, uuid, name, hint, scopes, grants
    case expiresAt = "expires_at"
    case lastUsedAt = "last_used_at"
    case createdAt = "created_at"
    case revokedAt = "revoked_at"
  }
  init(from decoder: Decoder) throws {
    secret = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .secret)
    apiKey = try RemoteAPIKey(from: decoder)
  }
}
struct RemoteAPIKeyGrant: Decodable {
  let resourceType: String
  let resourceID: String?
  let available: Bool
  enum CodingKeys: String, CodingKey {
    case available
    case resourceType = "resource_type"
    case resourceID = "resource_id"
  }
}
struct RemoteAPIKeyCreate: Encodable {
  let name: String
  let scopes: [String]
  let grants: [RemoteAPIKeyGrantInput]
  let expiresAt: String
  enum CodingKeys: String, CodingKey { case name, scopes, grants; case expiresAt = "expires_at" }
  init(draft: APIKeyDraft) {
    name = draft.name
    scopes = draft.scopes.map(\.rawValue).sorted()
    grants = draft.grants.map(RemoteAPIKeyGrantInput.init)
    expiresAt = ISO8601DateFormatter().string(from: draft.expiresAt)
  }
}
struct RemoteAPIKeyUpdate: Encodable {
  let name: String
  let scopes: [String]
  let grants: [RemoteAPIKeyGrantInput]?
  init(draft: APIKeyDraft, updateGrants: Bool) {
    name = draft.name
    scopes = draft.scopes.map(\.rawValue).sorted()
    grants = updateGrants ? draft.grants.map(RemoteAPIKeyGrantInput.init) : nil
  }
}
struct RemoteAPIKeyGrantInput: Encodable {
  let resourceType: String
  let resourceID: String
  enum CodingKeys: String, CodingKey { case resourceType = "resource_type"; case resourceID = "resource_id" }
  init(_ grant: APIKeyGrant) { resourceType = grant.resourceType.rawValue; resourceID = grant.resourceID.rawValue }
}
struct RemoteTheme: Decodable {
  let ownerName, effectiveSource: String
  let stored: RemoteThemeValues?
  let effective: RemoteThemeValues
  let capabilities: RemoteThemeCapabilities
  enum CodingKeys: String, CodingKey {
    case stored, effective, capabilities
    case ownerName = "owner_name"
    case effectiveSource = "effective_source"
  }
}
struct RemoteThemeCapabilities: Decodable {
  let canEdit, canReset: Bool
  enum CodingKeys: String, CodingKey { case canEdit = "can_edit"; case canReset = "can_reset" }
}
struct RemoteThemeValues: Codable {
  let headerFont, textFont: String
  let primary, primaryLight, secondary, secondaryDark, textColor, textContrast: String
  enum CodingKeys: String, CodingKey {
    case primary, secondary
    case headerFont = "header_font"
    case textFont = "text_font"
    case primaryLight = "primary_light"
    case secondaryDark = "secondary_dark"
    case textColor = "text_color"
    case textContrast = "text_contrast"
  }
  init(_ values: ThemeValues) {
    headerFont = values.headerFont.rawValue; textFont = values.textFont.rawValue
    primary = values.primary; primaryLight = values.primaryLight; secondary = values.secondary
    secondaryDark = values.secondaryDark; textColor = values.textColor; textContrast = values.textContrast
  }
}
extension ThemeValues {
  init(_ remote: RemoteThemeValues) {
    self.init(
      headerFont: ThemeFont(rawValue: remote.headerFont) ?? .montserrat,
      textFont: ThemeFont(rawValue: remote.textFont) ?? .openSans,
      primary: remote.primary, primaryLight: remote.primaryLight, secondary: remote.secondary,
      secondaryDark: remote.secondaryDark, textColor: remote.textColor,
      textContrast: remote.textContrast
    )
  }
}

struct RemoteBillingDraft: Encodable {
  let name: String; let description: String; let owner: RemoteOwnerInput; let items: [RemoteBillingItemInput]
  let pixKey: String; let pixMerchantName: String; let pixMerchantCity: String
  let recipients, replyTo: [RemoteContactInput]
  enum CodingKeys: String, CodingKey { case name, description, owner, items, recipients; case replyTo = "reply_to"; case pixKey = "pix_key"; case pixMerchantName = "pix_merchant_name"; case pixMerchantCity = "pix_merchant_city" }
  init(draft: BillingDraft) {
    name = draft.name; description = draft.description; items = draft.items.map(RemoteBillingItemInput.init)
    pixKey = draft.pixOverride?.key ?? ""; pixMerchantName = draft.pixOverride?.merchantName ?? ""; pixMerchantCity = draft.pixOverride?.merchantCity ?? ""
    recipients = draft.recipients.map(RemoteContactInput.init)
    replyTo = draft.replyTo.map(RemoteContactInput.init)
    switch draft.owner { case .user: owner = RemoteOwnerInput(type: "user", uuid: nil); case .organization(let id, _): owner = RemoteOwnerInput(type: "organization", uuid: id.rawValue) }
  }
}
struct RemoteBillingUpdate: Encodable {
  let name, description, pixKey, pixMerchantName, pixMerchantCity: String
  let items: [RemoteBillingItemInput]
  let recipients, replyTo: [RemoteContactInput]
  enum CodingKeys: String, CodingKey { case name, description, items, recipients; case replyTo = "reply_to"; case pixKey = "pix_key"; case pixMerchantName = "pix_merchant_name"; case pixMerchantCity = "pix_merchant_city" }
  init(draft: BillingDraft) {
    name = draft.name; description = draft.description; items = draft.items.map(RemoteBillingItemInput.init)
    pixKey = draft.pixOverride?.key ?? ""; pixMerchantName = draft.pixOverride?.merchantName ?? ""; pixMerchantCity = draft.pixOverride?.merchantCity ?? ""
    recipients = draft.recipients.map(RemoteContactInput.init)
    replyTo = draft.replyTo.map(RemoteContactInput.init)
  }
}
struct RemoteOwnerInput: Encodable { let type: String; let uuid: String? }
// Billing items minted client-side (a new row added in the form) carry a 36-char UUID as their
// id; the server only accepts a 26-char Crockford-base32 ULID (or null) for `uuid`, so only
// ids that already look like a server-issued ULID may be sent through — everything else must
// be nil so the server mints its own.
private let ulidAllowedCharacters = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
private func isULID(_ value: String) -> Bool {
  value.count == 26 && value.allSatisfy(ulidAllowedCharacters.contains)
}
struct RemoteBillingItemInput: Encodable {
  let uuid: String?; let description: String; let amount: Int; let itemType: String
  enum CodingKeys: String, CodingKey { case uuid, description, amount; case itemType = "item_type" }
  init(_ item: BillingItem) {
    uuid = isULID(item.id.rawValue) ? item.id.rawValue : nil
    description = item.description; amount = item.amount.centavos; itemType = item.type.rawValue
  }
}
struct RemoteBillCreateDraft: Encodable {
  // Every stored property here must also have a corresponding `container.encode` line in
  // `encode(to:)` below — the hand-written encoder is not kept in sync automatically.
  let referenceMonth: String; let dueDate: String?; let notes: String; let extras: [RemoteBillExtra]
  let variableAmounts: [String: Int]
  enum CodingKeys: String, CodingKey {
    case referenceMonth = "reference_month"; case dueDate = "due_date"; case notes, extras
    case variableAmounts = "variable_amounts"
  }
  init(draft: BillDraft) {
    referenceMonth = draft.referenceMonth.apiValue; dueDate = draft.dueDate?.iso8601; notes = draft.notes
    extras = draft.lineItems.filter { $0.kind == .extra }.map(RemoteBillExtra.init)
    // The server requires the variable_amounts key set to exactly match the billing's own
    // variable BillingItem uuids, so only line items whose id is already a real ULID (i.e. one
    // sourced from the billing's items, not a freshly client-minted id) can be included.
    var amounts: [String: Int] = [:]
    for item in draft.lineItems where item.kind == .variable {
      guard isULID(item.id.rawValue) else { continue }
      amounts[item.id.rawValue] = item.amount.centavos
    }
    variableAmounts = amounts
  }

  // Synthesized `Encodable` uses `encodeIfPresent` for optionals and would drop a nil
  // `due_date` from the body entirely. Write the key unconditionally so nil reaches the server
  // as an explicit JSON null — see `RemoteBillUpdateDraft` for why that distinction matters.
  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(referenceMonth, forKey: .referenceMonth)
    try container.encode(dueDate, forKey: .dueDate)
    try container.encode(notes, forKey: .notes)
    try container.encode(extras, forKey: .extras)
    try container.encode(variableAmounts, forKey: .variableAmounts)
  }
}
struct RemoteBillExtra: Encodable { let description: String; let amount: Int; init(_ item: BillLineItem) { description = item.description; amount = item.amount.centavos } }
struct RemoteBillUpdateDraft: Encodable {
  let dueDate: String?; let notes: String; let lineItems: [RemoteBillLineItemInput]
  enum CodingKeys: String, CodingKey { case dueDate = "due_date"; case notes; case lineItems = "line_items" }
  init(draft: BillDraft) { dueDate = draft.dueDate?.iso8601; notes = draft.notes; lineItems = draft.lineItems.map(RemoteBillLineItemInput.init) }

  // The server's PATCH handler treats an *absent* `due_date` as "leave unchanged" and an
  // explicit `null` as "clear it". Synthesized `Encodable` would omit a nil optional and make
  // clearing a due date impossible, so the key is always written.
  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(dueDate, forKey: .dueDate)
    try container.encode(notes, forKey: .notes)
    try container.encode(lineItems, forKey: .lineItems)
  }
}
struct RemoteBillLineItemInput: Encodable { let description: String; let amount: Int; let itemType: String; enum CodingKeys: String, CodingKey { case description, amount; case itemType = "item_type" }; init(_ item: BillLineItem) { description = item.description; amount = item.amount.centavos; itemType = item.kind.rawValue } }
struct RemoteBillTransition: Encodable {
  let currentStatus, target: String
  enum CodingKeys: String, CodingKey {
    case currentStatus = "current_status"
    case target
  }
}
struct RemoteExpenseCreate: Encodable { let description: String; let category: String; let incurredOn: String; let amount: Int; enum CodingKeys: String, CodingKey { case description, category, amount; case incurredOn = "incurred_on" } }

struct RemoteBillingList: Decodable { let items: [RemoteBillingListItem]; let stats: RemoteBillingStats }
struct RemoteBillingStats: Decodable {
  let received, pending, overdue, totalExpenses, netIncome, paidCount, billedCount: Int
  enum CodingKeys: String, CodingKey {
    case received, pending, overdue
    case totalExpenses = "total_expenses"
    case netIncome = "net_income"
    case paidCount = "paid_count"
    case billedCount = "billed_count"
  }
}
struct RemoteProfile: Decodable {
  let email: String; let pixKey, pixMerchantName, pixMerchantCity: String
  enum CodingKeys: String, CodingKey { case email; case pixKey = "pix_key"; case pixMerchantName = "pix_merchant_name"; case pixMerchantCity = "pix_merchant_city" }
}
struct RemotePixUpdate: Encodable {
  let pixKey, pixMerchantName, pixMerchantCity: String
  enum CodingKeys: String, CodingKey { case pixKey = "pix_key"; case pixMerchantName = "pix_merchant_name"; case pixMerchantCity = "pix_merchant_city" }
  init(pix: PixConfiguration) { pixKey = pix.key; pixMerchantName = pix.merchantName; pixMerchantCity = pix.merchantCity }
}
struct RemotePixUpdateResponse: Decodable { let profile: RemoteProfile }
struct RemoteBillingListItem: Decodable { let uuid, name, description: String; let owner: RemoteOwner; let capabilities: RemoteBillingCapabilities }
struct RemoteBilling: Decodable {
  let uuid, name, description: String
  let owner: RemoteOwner
  let items: [RemoteBillingItem]
  let pixKey, pixMerchantName, pixMerchantCity: String
  let pixNeedsSetup: Bool?
  let recipients, replyTo: [RemoteBillingContact]
  // Optional so a payload without the field keeps decoding; the live billing detail contract
  // always includes it.
  let communicationTemplates: [RemoteCommunicationTemplate]?
  let capabilities: RemoteBillingCapabilities
  enum CodingKeys: String, CodingKey { case uuid, name, description, owner, items, recipients, capabilities; case replyTo = "reply_to"; case pixKey = "pix_key"; case pixMerchantName = "pix_merchant_name"; case pixMerchantCity = "pix_merchant_city"; case pixNeedsSetup = "pix_needs_setup"; case communicationTemplates = "communication_templates" }
}
struct RemoteBillingContact: Decodable { let uuid: String; let name, email: String? }
struct RemoteCommunicationTemplate: Decodable {
  let commType, subject, body: String
  enum CodingKeys: String, CodingKey { case subject, body; case commType = "comm_type" }
}
struct RemoteBillingCapabilities: Decodable {
  let canEdit, canReadBills, canCreateBills, canManageBills, canReadExpenses, canWriteExpenses: Bool
  let canCreateExports, canReadAttachments, canWriteAttachments, canReadTheme, canManageTheme: Bool
  let canUploadBillReceipts, canDelete, canTransfer: Bool
  enum CodingKeys: String, CodingKey {
    case canEdit = "can_edit"; case canReadBills = "can_read_bills"; case canCreateBills = "can_create_bills"
    case canManageBills = "can_manage_bills"; case canReadExpenses = "can_read_expenses"; case canWriteExpenses = "can_write_expenses"
    case canCreateExports = "can_create_exports"; case canReadAttachments = "can_read_attachments"; case canWriteAttachments = "can_write_attachments"
    case canReadTheme = "can_read_theme"; case canManageTheme = "can_manage_theme"; case canUploadBillReceipts = "can_upload_bill_receipts"
    case canDelete = "can_delete"; case canTransfer = "can_transfer"
  }
}
struct RemoteOwner: Decodable { let type: String; let uuid, name: String? }
struct RemoteBillingItem: Decodable { let uuid, description: String; let amount: Int; let itemType: String; enum CodingKeys: String, CodingKey { case uuid, description, amount; case itemType = "item_type" } }
struct RemoteBillList: Decodable { let items: [RemoteBill] }
struct RemoteBill: Decodable {
  let uuid, referenceMonth, notes, status: String
  let dueDate, statusUpdatedAt, createdAt: String?
  let lineItems: [RemoteBillLine]; let receipts: [RemoteReceipt]?
  let communications: [RemoteBillCommunication]?
  let totalAmount: Int
  let availableTransitions: [RemoteAvailableTransition]
  let pdfRenderStatus: String?
  let hasInvoice, hasRecibo: Bool?
  let capabilities: RemoteBillCapabilities?
  enum CodingKeys: String, CodingKey {
    case uuid, notes, status, receipts, communications, capabilities
    case referenceMonth = "reference_month"; case dueDate = "due_date"
    case statusUpdatedAt = "status_updated_at"; case lineItems = "line_items"
    case createdAt = "created_at"
    case totalAmount = "total_amount"; case availableTransitions = "available_transitions"
    case pdfRenderStatus = "pdf_render_status"
    case hasInvoice = "has_invoice"; case hasRecibo = "has_recibo"
  }
}
struct RemoteBillCommunication: Decodable {
  let uuid, commType, status: String
  let createdAt, sentAt, recipientName, recipientEmail, subject: String?
  enum CodingKeys: String, CodingKey {
    case uuid, status, subject
    case commType = "comm_type"
    case createdAt = "created_at"
    case sentAt = "sent_at"
    case recipientName = "recipient_name"
    case recipientEmail = "recipient_email"
  }
}
struct RemoteBillCapabilities: Decodable {
  let canDownloadInvoice, canDownloadRecibo, canSendInvoice, canSendRecibo, canRegenerate: Bool
  let canEdit, canDelete, canTransition, canUploadReceipts, canDeleteReceipts: Bool
  let canReorderReceipts, canCompose: Bool
  let canOpenRecibo: Bool?
  enum CodingKeys: String, CodingKey {
    case canDownloadInvoice = "can_download_invoice"; case canDownloadRecibo = "can_download_recibo"
    case canSendInvoice = "can_send_invoice"; case canSendRecibo = "can_send_recibo"
    case canRegenerate = "can_regenerate"
    case canEdit = "can_edit"; case canDelete = "can_delete"; case canTransition = "can_transition"
    case canUploadReceipts = "can_upload_receipts"; case canDeleteReceipts = "can_delete_receipts"
    case canReorderReceipts = "can_reorder_receipts"; case canCompose = "can_compose"
    case canOpenRecibo = "can_open_recibo"
  }
}
struct RemoteAvailableTransition: Decodable {
  let target, label, style: String
  let requiresConfirmation: Bool
  enum CodingKeys: String, CodingKey {
    case target, label, style
    case requiresConfirmation = "requires_confirmation"
  }
}
struct RemoteBillLine: Decodable { let description: String; let amount: Int; let itemType: String; enum CodingKeys: String, CodingKey { case description, amount; case itemType = "item_type" } }
struct RemoteExpenseList: Decodable { let items: [RemoteExpense] }
struct RemoteExpense: Decodable { let uuid, description, category, incurredOn: String; let amount: Int; enum CodingKeys: String, CodingKey { case uuid, description, category, amount; case incurredOn = "incurred_on" } }

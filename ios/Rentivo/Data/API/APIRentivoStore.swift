import Foundation

@MainActor
public final class APIRentivoStore: AuthRepository, ProfileRepository, BillingRepository,
  BillRepository, ExpenseRepository, AttachmentRepository, CommunicationRepository, FileDownloadRepository, ExportRepository,
  DashboardRepository, ActivityRepository, OrganizationRepository, InvitationRepository,
  SecurityRepository, APIKeyRepository, ThemeRepository
{
  private let client: LiveAPIClient
  private var user = UserProfile(id: 0, email: "")

  public init(inMemoryCredentialStore: Bool = false) {
    let credentials: any CredentialStore = inMemoryCredentialStore
      ? MemoryCredentialStore()
      : KeychainCredentialStore()
    client = LiveAPIClient(credentials: credentials)
  }

  init(client: LiveAPIClient) {
    self.client = client
  }

  public var currentUser: UserProfile { user }
  public var recentActivities: [RecentActivity] { [] }
  public var usesLiveAPI: Bool { true }

  public func exchangeMobileAuthorization(code: String) async throws -> UserProfile {
    user = try await client.exchangeMobileAuthorization(code: code).profile
    return user
  }

  public func restoreSession() async throws -> UserProfile? {
    guard let session = try await client.restoreSession() else { return nil }
    user = session.profile
    return user
  }

  public func mobileLogin(email: String, password: String) async throws -> MobileLoginOutcome {
    switch try await client.mobileLogin(email: email, password: password) {
    case .authenticated(let session): .authenticated(adopt(session))
    case .mfaRequired(let challenge): .mfaRequired(challenge)
    }
  }

  public func mobileSignup(email: String, password: String) async throws -> UserProfile {
    adopt(try await client.mobileSignup(email: email, password: password))
  }

  public func verifyTotp(challenge: MFAChallenge, code: String) async throws -> UserProfile {
    adopt(try await client.verifyTotp(challenge: challenge, code: code))
  }

  public func verifyRecoveryCode(challenge: MFAChallenge, code: String) async throws -> UserProfile {
    adopt(try await client.verifyRecoveryCode(challenge: challenge, code: code))
  }

  public func beginPasskeyAssertion(challenge: MFAChallenge) async throws -> PasskeyRequestOptions {
    try await client.beginPasskeyAssertion(challenge: challenge)
  }

  public func completePasskeyAssertion(
    challenge: MFAChallenge, credential: PasskeyAssertionPayload
  ) async throws -> UserProfile {
    adopt(try await client.completePasskeyAssertion(challenge: challenge, credential: credential))
  }

  /// Records the profile behind a newly established session, exactly as the browser-handoff and
  /// restore paths do, and hands back the public half. The access token never leaves `client`.
  private func adopt(_ session: LiveSession) -> UserProfile {
    user = session.profile
    return user
  }

  public func logout() async {
    try? await execute(path: "/api/v1/auth/logout", method: "POST")
    await client.logout()
    user = UserProfile(id: 0, email: "")
  }

  public func deleteAccount(password: String) async throws {
    struct DeleteAccountPayload: Encodable { let password: String }
    try await execute(
      path: "/api/v1/security/delete-account", method: "POST",
      body: DeleteAccountPayload(password: password)
    )
    await client.logout()
    user = UserProfile(id: 0, email: "")
  }

  public func profile() async throws -> UserProfile {
    // GET /api/v1/profile only returns `CurrentProfileResponse` ({email}); the pix fields live on
    // `SecuritySummaryResponse.profile` (a full `ProfileResponse`), so fetch security instead.
    let response: RemoteSecuritySummary = try await decode(path: "/api/v1/security")
    let remote = response.profile
    user = UserProfile(id: user.id, email: remote.email, pix: pix(key: remote.pixKey, name: remote.pixMerchantName, city: remote.pixMerchantCity))
    return user
  }
  public func updatePix(_ pix: PixConfiguration) async throws -> UserProfile {
    let response: RemotePixUpdateResponse = try await decode(
      path: "/api/v1/security/pix", method: "POST", body: RemotePixUpdate(pix: pix)
    )
    let remote = response.profile
    user = UserProfile(id: user.id, email: remote.email, pix: self.pix(key: remote.pixKey, name: remote.pixMerchantName, city: remote.pixMerchantCity))
    return user
  }
  public func listBillings() async throws -> [Billing] {
    let response: RemoteBillingList = try await decode(path: "/api/v1/billings")
    let remote: [RemoteBilling] = try await details(
      at: response.items.map { "/api/v1/billings/\($0.uuid)" })
    return remote.map(billing(from:))
  }
  public func billing(id: BillingID) async throws -> Billing {
    let response: RemoteBilling = try await decode(path: "/api/v1/billings/\(id.rawValue)")
    return billing(from: response)
  }
  public func createBilling(_ draft: BillingDraft) async throws -> Billing {
    let remote: RemoteBilling = try await decode(
      path: "/api/v1/billings", method: "POST", body: RemoteBillingDraft(draft: draft)
    )
    return billing(from: remote)
  }
  public func updateBilling(id: BillingID, draft: BillingDraft) async throws -> Billing {
    let remote: RemoteBilling = try await decode(
      path: "/api/v1/billings/\(id.rawValue)", method: "PATCH", body: RemoteBillingUpdate(draft: draft)
    )
    return billing(from: remote)
  }
  public func deleteBilling(id: BillingID) async throws {
    try await execute(path: "/api/v1/billings/\(id.rawValue)", method: "DELETE")
  }
  public func listBills(billingID: BillingID) async throws -> [Bill] {
    let response: RemoteBillList = try await decode(path: "/api/v1/billings/\(billingID.rawValue)/bills")
    return try response.items.map { try bill(from: $0, billingID: billingID) }
  }
  public func bill(billingID: BillingID, id: BillID) async throws -> Bill {
    let response: RemoteBill = try await decode(
      path: "/api/v1/billings/\(billingID.rawValue)/bills/\(id.rawValue)"
    )
    return try bill(from: response, billingID: billingID)
  }
  public func createBill(_ draft: BillDraft) async throws -> Bill {
    let remote: RemoteBill = try await decode(
      path: "/api/v1/billings/\(draft.billingID.rawValue)/bills", method: "POST",
      body: RemoteBillCreateDraft(draft: draft)
    )
    return try bill(from: remote, billingID: draft.billingID)
  }
  public func updateBill(billingID: BillingID, billID: BillID, draft: BillDraft) async throws -> Bill {
    let remote: RemoteBill = try await decode(
      path: "/api/v1/billings/\(billingID.rawValue)/bills/\(billID.rawValue)", method: "PATCH",
      body: RemoteBillUpdateDraft(draft: draft)
    )
    return try bill(from: remote, billingID: billingID)
  }
  public func deleteBill(billingID: BillingID, billID: BillID) async throws {
    try await execute(path: "/api/v1/billings/\(billingID.rawValue)/bills/\(billID.rawValue)", method: "DELETE")
  }
  public func transitionBill(
    billingID: BillingID, billID: BillID, from currentStatus: BillStatus, to status: BillStatus
  ) async throws {
    try await execute(
      path: "/api/v1/billings/\(billingID.rawValue)/bills/\(billID.rawValue)/transitions",
      method: "POST",
      body: RemoteBillTransition(currentStatus: currentStatus.rawValue, target: status.rawValue)
    )
  }
  public func regenerateBill(billingID: BillingID, billID: BillID) async throws -> Bill {
    let remote: RemoteBill = try await decode(
      path: "/api/v1/billings/\(billingID.rawValue)/bills/\(billID.rawValue)/regenerate", method: "POST"
    )
    return try bill(from: remote, billingID: billingID)
  }
  public func addReceipt(billingID: BillingID, billID: BillID, upload: FileUpload) async throws -> Receipt {
    let upload = try ReceiptUploadRules.validated(upload)
    let response: RemoteReceiptUpload = try await decodeMultipart(
      path: "/api/v1/billings/\(billingID.rawValue)/bills/\(billID.rawValue)/receipts",
      files: [(field: "receipt_files", upload: upload)]
    )
    guard let receipt = response.items.first else { throw LiveAPIError.invalidResponse }
    return Receipt(id: ReceiptID(rawValue: receipt.uuid), name: receipt.filename, sortOrder: receipt.sortOrder)
  }
  public func reorderReceipts(billingID: BillingID, billID: BillID, receiptIDs: [ReceiptID]) async throws {
    let _: RemoteReceiptList = try await decode(
      path: "/api/v1/billings/\(billingID.rawValue)/bills/\(billID.rawValue)/receipt-order",
      method: "PUT", body: RemoteReceiptOrder(order: receiptIDs.map(\.rawValue))
    )
  }
  public func deleteReceipt(billingID: BillingID, billID: BillID, receiptID: ReceiptID) async throws {
    try await execute(
      path: "/api/v1/billings/\(billingID.rawValue)/bills/\(billID.rawValue)/receipts/\(receiptID.rawValue)",
      method: "DELETE"
    )
  }
  public func listExpenses(billingID: BillingID) async throws -> [Expense] {
    let response: RemoteExpenseList = try await decode(path: "/api/v1/billings/\(billingID.rawValue)/expenses")
    return try response.items.map {
      Expense(
        id: ExpenseID(rawValue: $0.uuid), billingID: billingID, description: $0.description,
        amount: Money(centavos: $0.amount), category: ExpenseCategory(rawValue: $0.category) ?? .other,
        incurredOn: try WireDate.dateOnly($0.incurredOn)
      )
    }
  }
  public func createExpense(billingID: BillingID, description: String, category: ExpenseCategory, incurredOn: DateOnly, amount: Money) async throws -> Expense {
    let remote: RemoteExpense = try await decode(
      path: "/api/v1/billings/\(billingID.rawValue)/expenses", method: "POST",
      body: RemoteExpenseCreate(description: description, category: category.rawValue, incurredOn: incurredOn.iso8601, amount: amount.centavos)
    )
    return Expense(id: ExpenseID(rawValue: remote.uuid), billingID: billingID, description: remote.description,
      amount: Money(centavos: remote.amount), category: ExpenseCategory(rawValue: remote.category) ?? .other,
      incurredOn: try WireDate.dateOnly(remote.incurredOn))
  }
  public func deleteExpense(billingID: BillingID, expenseID: ExpenseID) async throws {
    try await execute(path: "/api/v1/billings/\(billingID.rawValue)/expenses/\(expenseID.rawValue)", method: "DELETE")
  }
  public func listAttachments(billingID: BillingID) async throws -> [Attachment] {
    let response: RemoteAttachmentList = try await decode(path: "/api/v1/billings/\(billingID.rawValue)/attachments")
    return response.items.map(attachment(from:))
  }
  public func addAttachment(billingID: BillingID, upload: FileUpload) async throws -> Attachment {
    let upload = try AttachmentUploadRules.validated(upload)
    let response: RemoteAttachment = try await decodeMultipart(
      path: "/api/v1/billings/\(billingID.rawValue)/attachments",
      name: upload.filename, files: [(field: "file", upload: upload)]
    )
    return attachment(from: response)
  }
  public func deleteAttachment(billingID: BillingID, attachmentID: AttachmentID) async throws {
    try await execute(path: "/api/v1/billings/\(billingID.rawValue)/attachments/\(attachmentID.rawValue)", method: "DELETE")
  }
  public func previewCommunication(
    billingID: BillingID, subject: String, message: String
  ) async throws -> CommunicationPreview {
    let response: RemoteCommunicationPreview = try await decode(
      path: "/api/v1/billings/\(billingID.rawValue)/communications/preview", method: "POST",
      body: RemoteCommunicationPreviewRequest(subject: subject, body: message)
    )
    return CommunicationPreview(
      html: response.html, severeWarnings: response.severe, mildWarnings: response.mild
    )
  }
  @discardableResult
  public func sendCommunication(
    billingID: BillingID,
    billID: BillID,
    commType: CommunicationType,
    recipientIDs: [RecipientID],
    subject: String,
    message: String,
    acknowledgeWarning: Bool,
    saveScope: CommunicationSaveScope?
  ) async throws -> Int {
    guard !recipientIDs.isEmpty else {
      throw LiveAPIError.server(message: "Informe ao menos um destinatário.")
    }
    let response: RemoteCommunicationSend = try await decode(
      path: "/api/v1/billings/\(billingID.rawValue)/communications/send", method: "POST",
      body: RemoteCommunicationSendRequest(
        billID: billID.rawValue, commType: commType.rawValue,
        recipientIDs: recipientIDs.map(\.rawValue),
        subject: subject, message: message,
        acknowledgeWarning: acknowledgeWarning, saveScope: saveScope?.rawValue
      )
    )
    guard response.queuedCount > 0 else { throw LiveAPIError.invalidResponse }
    return response.queuedCount
  }
  public func downloadInvoice(billingID: BillingID, billID: BillID) async throws -> DownloadedFile {
    try await client.download(
      path: "/api/v1/billings/\(billingID.rawValue)/bills/\(billID.rawValue)/invoice",
      filename: "fatura-\(billID.rawValue)"
    )
  }
  public func downloadRecibo(billingID: BillingID, billID: BillID) async throws -> DownloadedFile {
    try await client.download(
      path: "/api/v1/billings/\(billingID.rawValue)/bills/\(billID.rawValue)/recibo",
      filename: "recibo-\(billID.rawValue)"
    )
  }
  public func downloadReceipt(billingID: BillingID, billID: BillID, receiptID: ReceiptID) async throws -> DownloadedFile {
    try await client.download(
      path: "/api/v1/billings/\(billingID.rawValue)/bills/\(billID.rawValue)/receipts/\(receiptID.rawValue)",
      filename: "comprovante-\(receiptID.rawValue)"
    )
  }
  public func downloadAttachment(billingID: BillingID, attachmentID: AttachmentID) async throws -> DownloadedFile {
    try await client.download(
      path: "/api/v1/billings/\(billingID.rawValue)/attachments/\(attachmentID.rawValue)",
      filename: "arquivo-\(attachmentID.rawValue)"
    )
  }
  public func requestExport(billingID: BillingID, format: String) async throws {
    let _: RemoteExport = try await decode(
      path: "/api/v1/billings/\(billingID.rawValue)/exports", method: "POST", body: RemoteExportRequest(format: format)
    )
  }
  public func dashboardSummary() async throws -> DashboardSummary {
    // `GET /api/v1/billings` already returns a `stats` rollup (`BillingStatsResponse`) computed
    // server-side across every billing visible to the user, so a single request gives us every
    // money figure the dashboard needs. This also sidesteps the previous ~3N fan-out entirely,
    // so an individual billing lacking bill/expense read capability can no longer break the
    // whole dashboard (the aggregate isn't gated by those per-billing capabilities).
    let response: RemoteBillingList = try await decode(path: "/api/v1/billings")
    let stats = response.stats
    let collectionRate = stats.billedCount == 0 ? 0 : stats.paidCount * 100 / stats.billedCount
    return DashboardSummary(
      received: Money(centavos: stats.received),
      expenses: Money(centavos: stats.totalExpenses),
      netIncome: Money(centavos: stats.netIncome),
      overdue: Money(centavos: stats.overdue),
      upcoming: Money(centavos: stats.pending),
      collectionRatePercent: collectionRate
    )
  }
  public func listOrganizations() async throws -> [Organization] {
    let response: RemoteOrganizationList = try await decode(path: "/api/v1/organizations")
    let remote: [RemoteOrganization] = try await details(
      at: response.items.map { "/api/v1/organizations/\($0.uuid)" })
    return remote.map(organization(from:))
  }
  public func organization(id: OrganizationID) async throws -> Organization {
    let response: RemoteOrganization = try await decode(path: "/api/v1/organizations/\(id.rawValue)")
    return organization(from: response)
  }
  public func createOrganization(_ draft: OrganizationDraft) async throws -> Organization {
    let response: RemoteOrganization = try await decode(
      path: "/api/v1/organizations", method: "POST", body: RemoteOrganizationCreate(draft: draft)
    )
    return organization(from: response)
  }
  public func updateOrganization(id: OrganizationID, draft: OrganizationDraft) async throws -> Organization {
    let response: RemoteOrganization = try await decode(path: "/api/v1/organizations/\(id.rawValue)", method: "PATCH", body: RemoteOrganizationUpdate(draft: draft))
    return organization(from: response)
  }
  public func deleteOrganization(id: OrganizationID) async throws { try await execute(path: "/api/v1/organizations/\(id.rawValue)", method: "DELETE") }
  public func updateMemberRole(organizationID: OrganizationID, userID: Int, role: OrganizationRole) async throws { try await execute(path: "/api/v1/organizations/\(organizationID.rawValue)/members/\(userID)", method: "PATCH", body: RemoteMemberRole(role: role.rawValue)) }
  public func removeMember(organizationID: OrganizationID, userID: Int) async throws { try await execute(path: "/api/v1/organizations/\(organizationID.rawValue)/members/\(userID)", method: "DELETE") }
  public func inviteMember(organizationID: OrganizationID, email: String, role: OrganizationRole) async throws -> Invitation {
    // Best-effort enrichment for the returned invitation's display name, started *before* the POST
    // rather than after it so the two round trips overlap instead of queueing: the invite doesn't
    // depend on the name, and the name doesn't depend on the invite. A failure here (including a
    // caller who may invite but not read the organization) still falls back to the placeholder,
    // exactly as when this ran sequentially — the invite itself already succeeded.
    async let remoteOrganization: RemoteOrganization? = try? self.decode(
      path: "/api/v1/organizations/\(organizationID.rawValue)")
    let response: RemoteInvitation = try await decode(path: "/api/v1/organizations/\(organizationID.rawValue)/invites", method: "POST", body: RemoteInviteCreate(email: OrganizationInviteEmail.normalized(email), role: role.rawValue))
    let organizationName = await remoteOrganization.map(organization(from:))?.name ?? "Organização"
    return Invitation(id: InvitationID(rawValue: response.uuid), organizationID: organizationID, organizationName: organizationName, email: response.invitedEmail, role: OrganizationRole(rawValue: response.role) ?? .viewer, status: InvitationStatus(rawValue: response.status) ?? .pending)
  }
  public func setOrganizationMFA(
    organizationID: OrganizationID, required: Bool
  ) async throws -> OrganizationMFAPolicy {
    let response: RemoteMFAPolicyResponse = try await decode(
      path: "/api/v1/organizations/\(organizationID.rawValue)/mfa-policy",
      method: "PUT",
      body: RemoteMFAPolicy(enforceMFA: required)
    )
    return OrganizationMFAPolicy(
      enforceMFA: response.enforceMFA,
      mfaSetupRequired: response.mfaSetupRequired
    )
  }
  public func transferBilling(billingID: BillingID, toOrganizationID: OrganizationID) async throws { try await execute(path: "/api/v1/billings/\(billingID.rawValue)/transfer", method: "POST", body: RemoteBillingTransfer(organizationID: toOrganizationID.rawValue)) }
  public func listPendingInvitations() async throws -> [Invitation] {
    let response: RemotePendingInvitationList = try await decode(path: "/api/v1/invites")
    return response.items.map {
      Invitation(
        id: InvitationID(rawValue: $0.uuid), organizationID: OrganizationID(rawValue: $0.organizationUUID),
        organizationName: $0.organizationName, email: user.email,
        role: OrganizationRole(rawValue: $0.role) ?? .viewer, status: .pending
      )
    }
  }
  public func acceptInvitation(id: InvitationID) async throws { try await execute(path: "/api/v1/invites/\(id.rawValue)/accept", method: "POST") }
  public func declineInvitation(id: InvitationID) async throws { try await execute(path: "/api/v1/invites/\(id.rawValue)/decline", method: "POST") }
  public func changePassword(
    currentPassword: String, newPassword: String, confirmPassword: String
  ) async throws {
    try await execute(
      path: "/api/v1/security/change-password", method: "POST",
      body: RemotePasswordChange(
        currentPassword: currentPassword, newPassword: newPassword, confirmPassword: confirmPassword
      )
    )
  }
  public func securitySummary() async throws -> SecuritySummary {
    let response: RemoteSecuritySummary = try await decode(path: "/api/v1/security")
    return SecuritySummary(
      totpEnabled: response.totp.enabled,
      recoveryCodeCount: response.totp.recoveryCodesRemaining,
      passkeys: try response.passkeys.map {
        Passkey(
          id: PasskeyID(rawValue: $0.uuid), name: $0.name,
          createdAt: try WireDate.isoDate($0.createdAt),
          lastUsedAt: try $0.lastUsedAt.map(WireDate.isoDate)
        )
      },
      setupRequired: response.mfa.setupRequired,
      organizationEnforced: response.mfa.organizationEnforced
    )
  }
  public func beginTOTPEnrollment() async throws -> TOTPEnrollment {
    let response: RemoteTOTPSetup = try await decode(path: "/api/v1/security/totp/setup", method: "POST")
    return TOTPEnrollment(secret: response.secret, provisioningURI: response.provisioningURI, qrCodeBase64: response.qrCodeBase64)
  }
  public func confirmTOTPEnrollment(code: String) async throws -> [String] {
    let response: RemoteRecoveryCodes = try await decode(
      path: "/api/v1/security/totp/confirm", method: "POST", body: RemoteTOTPConfirm(code: code)
    )
    return response.recoveryCodes
  }
  public func disableTOTP(password: String) async throws {
    try await execute(path: "/api/v1/security/totp/disable", method: "POST", body: RemoteTOTPDisable(password: password))
  }
  public func regenerateRecoveryCodes() async throws -> [String] {
    let response: RemoteRecoveryCodes = try await decode(path: "/api/v1/security/recovery-codes/regenerate", method: "POST")
    return response.recoveryCodes
  }
  public func deletePasskey(id: PasskeyID) async throws { try await execute(path: "/api/v1/security/passkeys/\(id.rawValue)", method: "DELETE") }
  public func apiKeyOptions() async throws -> APIKeyOptions {
    let response: RemoteAPIKeyOptions = try await decode(path: "/api/v1/api-keys/options")
    let personalType = WorkspaceResourceType(rawValue: response.personalWorkspace.resourceType) ?? .user
    return APIKeyOptions(
      scopes: response.scopes.compactMap(APIKeyScope.init(rawValue:)),
      personalWorkspace: APIKeyWorkspaceOption(
        resourceType: personalType,
        resourceID: WorkspaceID(rawValue: response.personalWorkspace.resourceID),
        name: "Conta pessoal"
      ),
      organizations: response.organizations.compactMap { organization in
        guard let resourceType = WorkspaceResourceType(rawValue: organization.resourceType) else {
          return nil
        }
        return APIKeyWorkspaceOption(
          resourceType: resourceType,
          resourceID: WorkspaceID(rawValue: organization.resourceID),
          name: organization.name
        )
      },
      defaultExpirationDays: response.defaultExpirationDays,
      maxExpirationDays: response.maxExpirationDays
    )
  }
  public func listAPIKeys() async throws -> [APIKeyMetadata] {
    let response: RemoteAPIKeyList = try await decode(path: "/api/v1/api-keys")
    // Revoked integrations remain visible as immutable history, matching the web client.
    return try response.items.map(apiKey(from:))
  }
  public func createAPIKey(_ draft: APIKeyDraft) async throws -> CreatedAPIKeySecret {
    let response: RemoteCreatedAPIKey = try await decode(
      path: "/api/v1/api-keys", method: "POST", body: RemoteAPIKeyCreate(draft: draft)
    )
    return CreatedAPIKeySecret(metadata: try apiKey(from: response.apiKey), secret: response.secret)
  }
  public func updateAPIKey(
    id: APIKeyID, draft: APIKeyDraft, updateGrants: Bool
  ) async throws -> APIKeyMetadata {
    let response: RemoteAPIKey = try await decode(
      path: "/api/v1/api-keys/\(id.rawValue)", method: "PATCH",
      body: RemoteAPIKeyUpdate(draft: draft, updateGrants: updateGrants)
    )
    return try apiKey(from: response)
  }
  public func revokeAPIKey(id: APIKeyID) async throws {
    try await execute(path: "/api/v1/api-keys/\(id.rawValue)", method: "DELETE")
  }
  public func theme(target: ThemeTarget) async throws -> ThemeRecord {
    let response: RemoteTheme = try await decode(path: themePath(for: target))
    return theme(from: response)
  }
  public func updateTheme(target: ThemeTarget, values: ThemeValues) async throws {
    try await execute(path: themePath(for: target), method: "PUT", body: RemoteThemeValues(values))
  }
  public func resetTheme(target: ThemeTarget) async throws {
    try await execute(path: themePath(for: target), method: "DELETE")
  }

  // MARK: - Transport helpers
  //
  // Every helper below is `nonisolated`, and deliberately so. This store is `@MainActor` because it
  // owns `user` and hands Domain values to SwiftUI, but nothing about serialization needs the main
  // actor: as MainActor members these ran JSON decoding of every list payload, JSON encoding of
  // every request body, and the full multipart assembly — which copies a receipt of up to 10 MB —
  // on the thread that also draws the app. In Swift 6 a `nonisolated async` function runs on the
  // global concurrent executor rather than inheriting its caller's actor, so marking them is the
  // whole fix. It is also what makes the concurrent fan-out in `details(at:)` real: child tasks
  // calling a MainActor-isolated helper would just queue back up behind each other on the main
  // actor. The `user` mutations and every `Remote*` → Domain mapping stay on the main actor.

  private nonisolated func decode<Response: Decodable & Sendable>(path: String) async throws -> Response {
    try Self.decode(try await client.request(path: path))
  }

  private nonisolated func decode<Response: Decodable & Sendable>(path: String, method: String) async throws -> Response {
    try Self.decode(try await client.request(path: path, method: method))
  }

  private nonisolated func decode<Response: Decodable & Sendable, Body: Encodable & Sendable>(
    path: String, method: String, body: Body
  ) async throws -> Response {
    try Self.decode(
      try await client.request(path: path, method: method, body: try WireJSON.encoder.encode(body)))
  }

  private nonisolated func decodeMultipart<Response: Decodable & Sendable>(
    path: String, name: String? = nil, files: [(field: String, upload: FileUpload)]
  ) async throws -> Response {
    let boundary = "RentivoBoundary-\(UUID().uuidString)"
    let data = Self.multipartBody(boundary: boundary, name: name, files: files)
    return try Self.decode(
      try await client.request(
        path: path, method: "POST", body: data,
        contentType: "multipart/form-data; boundary=\(boundary)"
      ))
  }

  private nonisolated func execute(path: String, method: String) async throws {
    _ = try await client.request(path: path, method: method)
  }

  private nonisolated func execute<Body: Encodable & Sendable>(path: String, method: String, body: Body) async throws {
    _ = try await client.request(path: path, method: method, body: try WireJSON.encoder.encode(body))
  }

  /// How many detail requests `details(at:)` keeps in flight.
  ///
  /// High enough that a portfolio-sized list finishes in a couple of round trips, low enough that a
  /// large one doesn't queue dozens of requests behind `URLSession`'s own per-host connection limit
  /// (which would serialize them again anyway) or hold every decoded payload in memory at once.
  private nonisolated static let maxConcurrentDetailRequests = 5

  /// Fetches one detail document per path concurrently and returns them in the order given.
  ///
  /// The list endpoints return summaries that omit what the app actually shows — a billing's items
  /// and recipients, an organization's members — so a detail request per row is unavoidable. Doing
  /// them one `await` at a time made the wait grow linearly with the list: ten billings meant ten
  /// serial round trips before anything appeared. The bounded group overlaps them while keeping the
  /// result order the list defined, since that order is what the UI renders. The first failure
  /// cancels the rest and propagates, matching the sequential loop this replaced.
  private nonisolated func details<Response: Decodable & Sendable>(at paths: [String]) async throws -> [Response] {
    guard !paths.isEmpty else { return [] }
    var responses = [Response?](repeating: nil, count: paths.count)
    try await withThrowingTaskGroup(of: (Int, Response).self) { group in
      var next = 0
      while next < min(Self.maxConcurrentDetailRequests, paths.count) {
        let index = next
        group.addTask { (index, try await self.decode(path: paths[index])) }
        next += 1
      }
      while let (index, response) = try await group.next() {
        responses[index] = response
        guard next < paths.count else { continue }
        // Deliberately not `index`: that name is bound to the *completed* task's slot two lines
        // above, and shadowing it here would make the next task's slot read like the finished one's.
        let nextIndex = next
        group.addTask { (nextIndex, try await self.decode(path: paths[nextIndex])) }
        next += 1
      }
    }
    // The group only finishes without throwing once every task has reported, so no slot can still
    // be empty here; the guard is there so a future change can't turn that into a silent short list.
    return try responses.map { response in
      guard let response else { throw LiveAPIError.invalidResponse }
      return response
    }
  }

  private nonisolated static func decode<Response: Decodable>(_ data: Data) throws -> Response {
    do { return try WireJSON.decoder.decode(Response.self, from: data) }
    catch { throw LiveAPIError.invalidResponse }
  }

  private nonisolated static func multipartBody(
    boundary: String, name: String?, files: [(field: String, upload: FileUpload)]
  ) -> Data {
    var body = Data()
    func append(_ string: String) { body.append(string.data(using: .utf8)!) }
    if let name {
      append("--\(boundary)\r\n")
      append("Content-Disposition: form-data; name=\"name\"\r\n\r\n\(name)\r\n")
    }
    for file in files {
      append("--\(boundary)\r\n")
      append("Content-Disposition: form-data; name=\"\(file.field)\"; filename=\"\(Self.sanitizedFilename(file.upload.filename))\"\r\n")
      append("Content-Type: \(file.upload.mediaType)\r\n\r\n")
      body.append(file.upload.data)
      append("\r\n")
    }
    append("--\(boundary)--\r\n")
    return body
  }

  // Strips characters that could break out of the quoted `filename="..."` attribute (or the
  // header line entirely) and inject extra multipart headers/parts.
  private nonisolated static func sanitizedFilename(_ filename: String) -> String {
    var sanitized = filename
    for token in ["\r\n", "\r", "\n", "\""] {
      sanitized = sanitized.replacingOccurrences(of: token, with: "")
    }
    return sanitized
  }

  private func owner(from owner: RemoteOwner) -> BillingOwner {
    if owner.type == "organization", let uuid = owner.uuid {
      return .organization(id: OrganizationID(rawValue: uuid), name: owner.name ?? "Organização")
    }
    return .user(id: user.id, name: owner.name ?? "Pessoal")
  }

  private func pix(key: String, name: String, city: String) -> PixConfiguration? {
    guard !key.isEmpty || !name.isEmpty || !city.isEmpty else { return nil }
    return PixConfiguration(key: key, merchantName: name, merchantCity: city)
  }

  private func paidAt(from remote: RemoteBill) throws -> DateOnly? {
    guard remote.status == "paid", let statusUpdatedAt = remote.statusUpdatedAt else { return nil }
    let datePart = statusUpdatedAt.split(separator: "T", maxSplits: 1).first.map(String.init) ?? statusUpdatedAt
    return try WireDate.dateOnly(datePart)
  }

  private func bill(from remote: RemoteBill, billingID: BillingID) throws -> Bill {
    // `ReferenceMonth`'s failable wire initializer replaces the previous manual split + the
    // precondition-enforcing `ReferenceMonth.init(year:month:)`, so a malformed `reference_month`
    // (e.g. an out-of-range month) now throws a decode error instead of trapping the process.
    guard let referenceMonth = ReferenceMonth(apiValue: remote.referenceMonth) else {
      throw LiveAPIError.invalidResponse
    }
    return Bill(
      id: BillID(rawValue: remote.uuid), billingID: billingID,
      referenceMonth: referenceMonth,
      dueDate: try WireDate.optionalDateOnly(remote.dueDate), paidAt: try paidAt(from: remote),
      notes: remote.notes, status: BillStatus(rawValue: remote.status) ?? .draft,
      lineItems: remote.lineItems.enumerated().map { index, line in
        BillLineItem(id: BillLineItemID(rawValue: "\(remote.uuid)-\(index)"), description: line.description,
          amount: Money(centavos: line.amount), kind: BillLineItemKind(rawValue: line.itemType) ?? .fixed)
      }, receipts: (remote.receipts ?? []).map {
        Receipt(id: ReceiptID(rawValue: $0.uuid), name: $0.filename, sortOrder: $0.sortOrder)
      },
      // Server-authoritative transitions/total for this bill (see `Bill.effectiveTransitions` /
      // `Bill.effectiveTotal`); unrecognized transition targets are dropped rather than failing the
      // whole decode, since a missing action button is a much smaller failure than a hard error.
      availableTransitions: remote.availableTransitions.compactMap { BillStatus(rawValue: $0.target) },
      serverTotal: Money(centavos: remote.totalAmount),
      // An unknown or absent render status means "not rendering" rather than a decode failure,
      // and an absent capabilities object stays permissive so older payloads keep working.
      pdfRenderStatus: remote.pdfRenderStatus.flatMap(PDFRenderStatus.init(rawValue:)),
      hasInvoice: remote.hasInvoice ?? false, hasRecibo: remote.hasRecibo ?? false,
      capabilities: billCapabilities(from: remote.capabilities)
    )
  }

  private func billCapabilities(from remote: RemoteBillCapabilities?) -> BillCapabilities {
    guard let remote else { return .permissive }
    return BillCapabilities(
      canDownloadInvoice: remote.canDownloadInvoice, canDownloadRecibo: remote.canDownloadRecibo,
      canSendInvoice: remote.canSendInvoice, canSendRecibo: remote.canSendRecibo,
      canRegenerate: remote.canRegenerate, canEdit: remote.canEdit, canDelete: remote.canDelete,
      canTransition: remote.canTransition, canUploadReceipts: remote.canUploadReceipts,
      canDeleteReceipts: remote.canDeleteReceipts,
      canReorderReceipts: remote.canReorderReceipts, canCompose: remote.canCompose,
      canOpenRecibo: remote.canOpenRecibo ?? false
    )
  }

  private func billing(from remote: RemoteBilling) -> Billing {
    Billing(
      id: BillingID(rawValue: remote.uuid), name: remote.name, description: remote.description,
      owner: owner(from: remote.owner),
      items: remote.items.enumerated().map { index, item in
        BillingItem(id: BillingItemID(rawValue: item.uuid), description: item.description,
          amount: Money(centavos: item.amount), type: BillingItemType(rawValue: item.itemType) ?? .fixed,
          sortOrder: index)
      },
      pixOverride: pix(key: remote.pixKey, name: remote.pixMerchantName, city: remote.pixMerchantCity),
      pixNeedsSetup: remote.pixNeedsSetup ?? false,
      recipients: remote.recipients.compactMap { contact in
        guard let name = contact.name, let email = contact.email else { return nil }
        return BillingRecipient(id: RecipientID(rawValue: contact.uuid), name: name, email: email)
      },
      replyTo: remote.replyTo.compactMap { contact in
        guard let name = contact.name, let email = contact.email else { return nil }
        return BillingRecipient(id: RecipientID(rawValue: contact.uuid), name: name, email: email)
      },
      // Templates for communication types this app doesn't model are dropped rather than failing
      // the whole billing decode, the same tolerance applied to bill transitions above.
      communicationTemplates: (remote.communicationTemplates ?? []).compactMap { template in
        CommunicationType(rawValue: template.commType).map {
          CommunicationTemplate(commType: $0, subject: template.subject, body: template.body)
        }
      },
      capabilities: capabilities(from: remote.capabilities)
    )
  }

  private func capabilities(from remote: RemoteBillingCapabilities) -> BillingCapabilities {
    BillingCapabilities(
      canEdit: remote.canEdit, canReadBills: remote.canReadBills,
      canCreateBills: remote.canCreateBills, canManageBills: remote.canManageBills,
      canReadExpenses: remote.canReadExpenses, canWriteExpenses: remote.canWriteExpenses,
      canCreateExports: remote.canCreateExports, canReadAttachments: remote.canReadAttachments,
      canWriteAttachments: remote.canWriteAttachments, canReadTheme: remote.canReadTheme,
      canManageTheme: remote.canManageTheme,
      canUploadBillReceipts: remote.canUploadBillReceipts, canDelete: remote.canDelete,
      canTransfer: remote.canTransfer
    )
  }

  private func organization(from remote: RemoteOrganization) -> Organization {
    Organization(id: OrganizationID(rawValue: remote.uuid), name: remote.name,
      pix: remote.settings.flatMap { pix(key: $0.pixKey, name: $0.pixMerchantName, city: $0.pixMerchantCity) },
      members: (remote.members ?? []).map {
        OrganizationMember(userID: $0.userID, email: $0.email, role: OrganizationRole(rawValue: $0.role) ?? .viewer)
      },
      requiresMFA: remote.enforceMFA, currentUserRole: OrganizationRole(rawValue: remote.currentRole) ?? .viewer,
      capabilities: OrganizationCapabilities(canManage: remote.capabilities.canManage, canInvite: remote.capabilities.canInvite,
        canCreateBilling: remote.capabilities.canCreateBilling, canViewBillingStats: remote.capabilities.canViewBillingStats))
  }

  private func apiKey(from remote: RemoteAPIKey) throws -> APIKeyMetadata {
    APIKeyMetadata(
      id: APIKeyID(rawValue: remote.uuid), name: remote.name, hint: remote.hint,
      scopes: Set(remote.scopes.compactMap(APIKeyScope.init(rawValue:))),
      grants: remote.grants.compactMap { grant in
        guard let resourceID = grant.resourceID,
          let resourceType = WorkspaceResourceType(rawValue: grant.resourceType)
        else { return nil }
        return APIKeyGrant(
          resourceType: resourceType, resourceID: WorkspaceID(rawValue: resourceID),
          available: grant.available
        )
      },
      expiresAt: try WireDate.isoDate(remote.expiresAt), lastUsedAt: try remote.lastUsedAt.map(WireDate.isoDate),
      createdAt: try WireDate.isoDate(remote.createdAt), revokedAt: try remote.revokedAt.map(WireDate.isoDate)
    )
  }

  private func attachment(from remote: RemoteAttachment) -> Attachment {
    Attachment(
      id: AttachmentID(rawValue: remote.uuid), name: remote.name,
      mediaType: remote.contentType, byteCount: remote.fileSize
    )
  }

  private func themePath(for target: ThemeTarget) -> String {
    switch target {
    case .user: "/api/v1/themes/user"
    case .organization(let id): "/api/v1/themes/organizations/\(id.rawValue)"
    case .billing(let id): "/api/v1/themes/billings/\(id.rawValue)"
    }
  }

  private func theme(from remote: RemoteTheme) -> ThemeRecord {
    ThemeRecord(
      ownerName: remote.ownerName, stored: remote.stored.map(ThemeValues.init),
      effective: ThemeValues(remote.effective),
      effectiveSource: ThemeSource(rawValue: remote.effectiveSource) ?? .default,
      canEdit: remote.capabilities.canEdit, canReset: remote.capabilities.canReset
    )
  }
}

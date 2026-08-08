package app.rentivo.data.api

import app.rentivo.data.APIKeyRepository
import app.rentivo.data.ActivityRepository
import app.rentivo.data.AppDependencies
import app.rentivo.data.AttachmentRepository
import app.rentivo.data.AuthRepository
import app.rentivo.data.BillRepository
import app.rentivo.data.BillingRepository
import app.rentivo.data.CommunicationRepository
import app.rentivo.data.DashboardRepository
import app.rentivo.data.DashboardSummary
import app.rentivo.data.DemoRepository
import app.rentivo.data.ExpenseRepository
import app.rentivo.data.ExportRepository
import app.rentivo.data.FileDownloadRepository
import app.rentivo.data.InvitationRepository
import app.rentivo.data.OrganizationRepository
import app.rentivo.data.ProfileRepository
import app.rentivo.data.SecurityRepository
import app.rentivo.data.ThemeRepository
import app.rentivo.domain.APIKeyDraft
import app.rentivo.domain.APIKeyGrant
import app.rentivo.domain.APIKeyID
import app.rentivo.domain.APIKeyMetadata
import app.rentivo.domain.APIKeyScope
import app.rentivo.domain.Attachment
import app.rentivo.domain.AttachmentID
import app.rentivo.domain.Bill
import app.rentivo.domain.BillCapabilities
import app.rentivo.domain.BillDraft
import app.rentivo.domain.BillID
import app.rentivo.domain.BillLineItem
import app.rentivo.domain.BillLineItemID
import app.rentivo.domain.BillLineItemKind
import app.rentivo.domain.BillStatus
import app.rentivo.domain.Billing
import app.rentivo.domain.BillingCapabilities
import app.rentivo.domain.BillingDraft
import app.rentivo.domain.BillingID
import app.rentivo.domain.BillingItem
import app.rentivo.domain.BillingItemID
import app.rentivo.domain.BillingItemType
import app.rentivo.domain.BillingOwner
import app.rentivo.domain.BillingRecipient
import app.rentivo.domain.CommunicationPreview
import app.rentivo.domain.CommunicationSaveScope
import app.rentivo.domain.CommunicationTemplate
import app.rentivo.domain.CommunicationType
import app.rentivo.domain.CreatedAPIKeySecret
import app.rentivo.domain.DateOnly
import app.rentivo.domain.DownloadedFile
import app.rentivo.domain.Expense
import app.rentivo.domain.ExpenseCategory
import app.rentivo.domain.ExpenseID
import app.rentivo.domain.FileUpload
import app.rentivo.domain.Invitation
import app.rentivo.domain.InvitationID
import app.rentivo.domain.InvitationStatus
import app.rentivo.domain.Money
import app.rentivo.domain.Organization
import app.rentivo.domain.OrganizationCapabilities
import app.rentivo.domain.OrganizationDraft
import app.rentivo.domain.OrganizationID
import app.rentivo.domain.OrganizationMember
import app.rentivo.domain.OrganizationRole
import app.rentivo.domain.PDFRenderStatus
import app.rentivo.domain.Passkey
import app.rentivo.domain.PasskeyID
import app.rentivo.domain.PixConfiguration
import app.rentivo.domain.Receipt
import app.rentivo.domain.ReceiptID
import app.rentivo.domain.RecentActivity
import app.rentivo.domain.RecipientID
import app.rentivo.domain.ReferenceMonth
import app.rentivo.domain.SecuritySummary
import app.rentivo.domain.TOTPEnrollment
import app.rentivo.domain.ThemeRecord
import app.rentivo.domain.ThemeSource
import app.rentivo.domain.ThemeTarget
import app.rentivo.domain.ThemeValues
import app.rentivo.domain.UserProfile
import app.rentivo.domain.WorkspaceID
import app.rentivo.domain.WorkspaceResourceType
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.encodeToString
import java.util.UUID

/**
 * The live implementation of every repository except [DemoRepository]: it translates the domain
 * calls the app makes into the `/api/v1` contract and back.
 */
class APIRentivoStore(private val client: LiveAPIClient) :
  AuthRepository,
  ProfileRepository,
  BillingRepository,
  BillRepository,
  ExpenseRepository,
  AttachmentRepository,
  CommunicationRepository,
  FileDownloadRepository,
  ExportRepository,
  DashboardRepository,
  ActivityRepository,
  OrganizationRepository,
  InvitationRepository,
  SecurityRepository,
  APIKeyRepository,
  ThemeRepository {

  /**
   * The signed-in user, cached because the API returns owner names and invitation e-mails without
   * repeating the account's own id. Starts empty until a session is exchanged or restored.
   */
  private var user = UserProfile(id = 0, email = "")

  override val currentUser: UserProfile get() = user

  override val recentActivities: List<RecentActivity> get() = emptyList()

  override val usesLiveAPI: Boolean get() = true

  override suspend fun exchangeMobileAuthorization(code: String): UserProfile {
    user = client.exchangeMobileAuthorization(code).profile
    return user
  }

  override suspend fun restoreSession(): UserProfile? {
    val session = client.restoreSession() ?: return null
    user = session.profile
    return user
  }

  override suspend fun logout() {
    try {
      execute(path = "/api/v1/auth/logout", method = "POST")
    } catch (error: CancellationException) {
      throw error
    } catch (error: Exception) {
      // Best effort: the local session is dropped below regardless of what the server answers.
    }
    client.logout()
    user = UserProfile(id = 0, email = "")
  }

  override suspend fun deleteAccount(password: String) {
    execute(
      path = "/api/v1/security/delete-account",
      method = "POST",
      body = RemoteDeleteAccount(password = password),
    )
    client.logout()
    user = UserProfile(id = 0, email = "")
  }

  override suspend fun profile(): UserProfile {
    // GET /api/v1/profile only returns `CurrentProfileResponse` ({email}); the pix fields live on
    // `SecuritySummaryResponse.profile` (a full `ProfileResponse`), so fetch security instead.
    val response = decode<RemoteSecuritySummary>(path = "/api/v1/security")
    val remote = response.profile
    user = UserProfile(
      id = user.id,
      email = remote.email,
      pix = pix(remote.pixKey, remote.pixMerchantName, remote.pixMerchantCity),
    )
    return user
  }

  override suspend fun updatePix(pix: PixConfiguration): UserProfile {
    val response = decode<RemotePixUpdate, RemotePixUpdateResponse>(
      path = "/api/v1/security/pix",
      method = "POST",
      body = RemotePixUpdate.from(pix),
    )
    val remote = response.profile
    user = UserProfile(
      id = user.id,
      email = remote.email,
      pix = pix(remote.pixKey, remote.pixMerchantName, remote.pixMerchantCity),
    )
    return user
  }

  override suspend fun listBillings(): List<Billing> {
    val response = decode<RemoteBillingList>(path = "/api/v1/billings")
    // The list payload carries no recurring items, and the portfolio subtotal needs them, so each
    // row is hydrated through its own detail request.
    return response.items.map { billing(BillingID(rawValue = it.uuid)) }
  }

  override suspend fun billing(id: BillingID): Billing =
    billing(decode<RemoteBilling>(path = "/api/v1/billings/${id.rawValue}"))

  override suspend fun createBilling(draft: BillingDraft): Billing = billing(
    decode<RemoteBillingDraft, RemoteBilling>(
      path = "/api/v1/billings",
      method = "POST",
      body = RemoteBillingDraft.from(draft),
    )
  )

  override suspend fun updateBilling(id: BillingID, draft: BillingDraft): Billing = billing(
    decode<RemoteBillingUpdate, RemoteBilling>(
      path = "/api/v1/billings/${id.rawValue}",
      method = "PATCH",
      body = RemoteBillingUpdate.from(draft),
    )
  )

  override suspend fun deleteBilling(id: BillingID) {
    execute(path = "/api/v1/billings/${id.rawValue}", method = "DELETE")
  }

  override suspend fun listBills(billingID: BillingID): List<Bill> {
    val response = decode<RemoteBillList>(path = "/api/v1/billings/${billingID.rawValue}/bills")
    return response.items.map { bill(it, billingID) }
  }

  override suspend fun bill(billingID: BillingID, id: BillID): Bill = bill(
    decode<RemoteBill>(path = "/api/v1/billings/${billingID.rawValue}/bills/${id.rawValue}"),
    billingID,
  )

  override suspend fun createBill(draft: BillDraft): Bill = bill(
    decode<RemoteBillCreateDraft, RemoteBill>(
      path = "/api/v1/billings/${draft.billingID.rawValue}/bills",
      method = "POST",
      body = RemoteBillCreateDraft.from(draft),
    ),
    draft.billingID,
  )

  override suspend fun updateBill(billingID: BillingID, billID: BillID, draft: BillDraft): Bill =
    bill(
      decode<RemoteBillUpdateDraft, RemoteBill>(
        path = "/api/v1/billings/${billingID.rawValue}/bills/${billID.rawValue}",
        method = "PATCH",
        body = RemoteBillUpdateDraft.from(draft),
      ),
      billingID,
    )

  override suspend fun deleteBill(billingID: BillingID, billID: BillID) {
    execute(
      path = "/api/v1/billings/${billingID.rawValue}/bills/${billID.rawValue}",
      method = "DELETE",
    )
  }

  override suspend fun transitionBill(billingID: BillingID, billID: BillID, status: BillStatus) {
    execute(
      path = "/api/v1/billings/${billingID.rawValue}/bills/${billID.rawValue}/transitions",
      method = "POST",
      body = RemoteBillTransition(target = status.wire),
    )
  }

  override suspend fun regenerateBill(billingID: BillingID, billID: BillID): Bill = bill(
    decode<RemoteBill>(
      path = "/api/v1/billings/${billingID.rawValue}/bills/${billID.rawValue}/regenerate",
      method = "POST",
    ),
    billingID,
  )

  override suspend fun addReceipt(
    billingID: BillingID,
    billID: BillID,
    upload: FileUpload,
  ): Receipt {
    val response = decodeMultipart<RemoteReceiptUpload>(
      path = "/api/v1/billings/${billingID.rawValue}/bills/${billID.rawValue}/receipts",
      files = listOf(MultipartFile(field = "receipt_files", upload = upload)),
    )
    val receipt = response.items.firstOrNull() ?: throw LiveAPIError.InvalidResponse
    return Receipt(
      id = ReceiptID(rawValue = receipt.uuid),
      name = receipt.filename,
      sortOrder = receipt.sortOrder,
    )
  }

  override suspend fun reorderReceipts(
    billingID: BillingID,
    billID: BillID,
    receiptIDs: List<ReceiptID>,
  ) {
    decode<RemoteReceiptOrder, RemoteReceiptList>(
      path = "/api/v1/billings/${billingID.rawValue}/bills/${billID.rawValue}/receipt-order",
      method = "PUT",
      body = RemoteReceiptOrder(order = receiptIDs.map { it.rawValue }),
    )
  }

  override suspend fun deleteReceipt(
    billingID: BillingID,
    billID: BillID,
    receiptID: ReceiptID,
  ) {
    execute(
      path = "/api/v1/billings/${billingID.rawValue}/bills/${billID.rawValue}" +
        "/receipts/${receiptID.rawValue}",
      method = "DELETE",
    )
  }

  override suspend fun listExpenses(billingID: BillingID): List<Expense> {
    val response =
      decode<RemoteExpenseList>(path = "/api/v1/billings/${billingID.rawValue}/expenses")
    return response.items.map { expense(it, billingID) }
  }

  override suspend fun createExpense(
    billingID: BillingID,
    description: String,
    category: ExpenseCategory,
    incurredOn: DateOnly,
    amount: Money,
  ): Expense = expense(
    decode<RemoteExpenseCreate, RemoteExpense>(
      path = "/api/v1/billings/${billingID.rawValue}/expenses",
      method = "POST",
      body = RemoteExpenseCreate(
        description = description,
        category = category.wire,
        incurredOn = incurredOn.iso8601,
        amount = amount.centavos,
      ),
    ),
    billingID,
  )

  override suspend fun deleteExpense(billingID: BillingID, expenseID: ExpenseID) {
    execute(
      path = "/api/v1/billings/${billingID.rawValue}/expenses/${expenseID.rawValue}",
      method = "DELETE",
    )
  }

  override suspend fun listAttachments(billingID: BillingID): List<Attachment> {
    val response =
      decode<RemoteAttachmentList>(path = "/api/v1/billings/${billingID.rawValue}/attachments")
    return response.items.map(::attachment)
  }

  override suspend fun addAttachment(billingID: BillingID, upload: FileUpload): Attachment =
    attachment(
      decodeMultipart<RemoteAttachment>(
        path = "/api/v1/billings/${billingID.rawValue}/attachments",
        name = upload.filename,
        files = listOf(MultipartFile(field = "file", upload = upload)),
      )
    )

  override suspend fun deleteAttachment(billingID: BillingID, attachmentID: AttachmentID) {
    execute(
      path = "/api/v1/billings/${billingID.rawValue}/attachments/${attachmentID.rawValue}",
      method = "DELETE",
    )
  }

  override suspend fun previewCommunication(
    billingID: BillingID,
    subject: String,
    message: String,
  ): CommunicationPreview {
    val response = decode<RemoteCommunicationPreviewRequest, RemoteCommunicationPreview>(
      path = "/api/v1/billings/${billingID.rawValue}/communications/preview",
      method = "POST",
      body = RemoteCommunicationPreviewRequest(subject = subject, body = message),
    )
    return CommunicationPreview(
      html = response.html,
      severeWarnings = response.severe,
      mildWarnings = response.mild,
    )
  }

  override suspend fun sendCommunication(
    billingID: BillingID,
    billID: BillID,
    commType: CommunicationType,
    recipientIDs: List<RecipientID>,
    subject: String,
    message: String,
    acknowledgeWarning: Boolean,
    saveScope: CommunicationSaveScope?,
  ): Int {
    if (recipientIDs.isEmpty()) {
      throw LiveAPIError.Server(message = "Informe ao menos um destinatário.")
    }
    val response = decode<RemoteCommunicationSendRequest, RemoteCommunicationSend>(
      path = "/api/v1/billings/${billingID.rawValue}/communications/send",
      method = "POST",
      body = RemoteCommunicationSendRequest(
        billID = billID.rawValue,
        commType = commType.wire,
        subject = subject,
        body = message,
        recipientIDs = recipientIDs.map { it.rawValue },
        acknowledgeWarning = acknowledgeWarning,
        saveScope = saveScope?.wire,
      ),
    )
    if (response.queuedCount <= 0) throw LiveAPIError.InvalidResponse
    return response.queuedCount
  }

  override suspend fun downloadInvoice(billingID: BillingID, billID: BillID): DownloadedFile =
    client.download(
      path = "/api/v1/billings/${billingID.rawValue}/bills/${billID.rawValue}/invoice",
      filename = "fatura-${billID.rawValue}",
    )

  override suspend fun downloadRecibo(billingID: BillingID, billID: BillID): DownloadedFile =
    client.download(
      path = "/api/v1/billings/${billingID.rawValue}/bills/${billID.rawValue}/recibo",
      filename = "recibo-${billID.rawValue}",
    )

  override suspend fun downloadReceipt(
    billingID: BillingID,
    billID: BillID,
    receiptID: ReceiptID,
  ): DownloadedFile = client.download(
    path = "/api/v1/billings/${billingID.rawValue}/bills/${billID.rawValue}" +
      "/receipts/${receiptID.rawValue}",
    filename = "comprovante-${receiptID.rawValue}",
  )

  override suspend fun downloadAttachment(
    billingID: BillingID,
    attachmentID: AttachmentID,
  ): DownloadedFile = client.download(
    path = "/api/v1/billings/${billingID.rawValue}/attachments/${attachmentID.rawValue}",
    filename = "arquivo-${attachmentID.rawValue}",
  )

  override suspend fun requestExport(billingID: BillingID, format: String) {
    decode<RemoteExportRequest, RemoteExport>(
      path = "/api/v1/billings/${billingID.rawValue}/exports",
      method = "POST",
      body = RemoteExportRequest(format = format),
    )
  }

  override suspend fun dashboardSummary(): DashboardSummary {
    // `GET /api/v1/billings` already returns a `stats` rollup (`BillingStatsResponse`) computed
    // server-side across every billing visible to the user, so a single request gives us every
    // money figure the dashboard needs. This also sidesteps a ~3N fan-out entirely, so an
    // individual billing lacking bill/expense read capability can no longer break the whole
    // dashboard (the aggregate isn't gated by those per-billing capabilities).
    val stats = decode<RemoteBillingList>(path = "/api/v1/billings").stats
    val collectionRate =
      if (stats.billedCount == 0) 0 else stats.paidCount * 100 / stats.billedCount
    return DashboardSummary(
      received = Money(centavos = stats.received),
      expenses = Money(centavos = stats.totalExpenses),
      netIncome = Money(centavos = stats.netIncome),
      overdue = Money(centavos = stats.overdue),
      upcoming = Money(centavos = stats.pending),
      collectionRatePercent = collectionRate,
    )
  }

  override suspend fun listOrganizations(): List<Organization> {
    val response = decode<RemoteOrganizationList>(path = "/api/v1/organizations")
    // The list payload carries no members, and the organization card shows the member count, so
    // each row is hydrated through its own detail request.
    return response.items.map { organization(OrganizationID(rawValue = it.uuid)) }
  }

  override suspend fun organization(id: OrganizationID): Organization =
    organization(decode<RemoteOrganization>(path = "/api/v1/organizations/${id.rawValue}"))

  override suspend fun createOrganization(draft: OrganizationDraft): Organization {
    // OrganizationCreateRequest only accepts `name`; PIX has no create-time slot, so when the
    // draft carries PIX data we follow up with the PATCH that does accept pix fields.
    val response = decode<RemoteOrganizationCreate, RemoteOrganization>(
      path = "/api/v1/organizations",
      method = "POST",
      body = RemoteOrganizationCreate(name = draft.name),
    )
    if (draft.pix == null) return organization(response)
    return try {
      organization(
        decode<RemoteOrganizationUpdate, RemoteOrganization>(
          path = "/api/v1/organizations/${response.uuid}",
          method = "PATCH",
          body = RemoteOrganizationUpdate.from(draft),
        )
      )
    } catch (error: CancellationException) {
      throw error
    } catch (error: Exception) {
      // The organization already exists on the server from the POST above, so throwing here would
      // surface as a failure to the caller, who would retry and create a duplicate organization.
      // Return the created organization (without PIX) instead; the form-side validation makes this
      // follow-up PATCH fail rarely, and the user can still edit the organization afterward.
      organization(response)
    }
  }

  override suspend fun updateOrganization(
    id: OrganizationID,
    draft: OrganizationDraft,
  ): Organization = organization(
    decode<RemoteOrganizationUpdate, RemoteOrganization>(
      path = "/api/v1/organizations/${id.rawValue}",
      method = "PATCH",
      body = RemoteOrganizationUpdate.from(draft),
    )
  )

  override suspend fun deleteOrganization(id: OrganizationID) {
    execute(path = "/api/v1/organizations/${id.rawValue}", method = "DELETE")
  }

  override suspend fun updateMemberRole(
    organizationID: OrganizationID,
    userID: Int,
    role: OrganizationRole,
  ) {
    execute(
      path = "/api/v1/organizations/${organizationID.rawValue}/members/$userID",
      method = "PATCH",
      body = RemoteMemberRole(role = role.wire),
    )
  }

  override suspend fun removeMember(organizationID: OrganizationID, userID: Int) {
    execute(
      path = "/api/v1/organizations/${organizationID.rawValue}/members/$userID",
      method = "DELETE",
    )
  }

  override suspend fun inviteMember(
    organizationID: OrganizationID,
    email: String,
    role: OrganizationRole,
  ): Invitation {
    val response = decode<RemoteInviteCreate, RemoteInvitation>(
      path = "/api/v1/organizations/${organizationID.rawValue}/invites",
      method = "POST",
      body = RemoteInviteCreate(email = email, role = role.wire),
    )
    // Best-effort enrichment: the invite already succeeded, so a failure here shouldn't fail the
    // whole call.
    val organizationName = try {
      organization(organizationID).name
    } catch (error: CancellationException) {
      throw error
    } catch (error: Exception) {
      "Organização"
    }
    return Invitation(
      id = InvitationID(rawValue = response.uuid),
      organizationID = organizationID,
      organizationName = organizationName,
      email = response.invitedEmail,
      role = OrganizationRole.fromWire(response.role) ?: OrganizationRole.VIEWER,
      status = InvitationStatus.fromWire(response.status) ?: InvitationStatus.PENDING,
    )
  }

  override suspend fun setOrganizationMFA(organizationID: OrganizationID, required: Boolean) {
    execute(
      path = "/api/v1/organizations/${organizationID.rawValue}/mfa-policy",
      method = "PUT",
      body = RemoteMFAPolicy(enforceMFA = required),
    )
  }

  override suspend fun transferBilling(
    billingID: BillingID,
    toOrganizationID: OrganizationID,
  ) {
    execute(
      path = "/api/v1/billings/${billingID.rawValue}/transfer",
      method = "POST",
      body = RemoteBillingTransfer(organizationID = toOrganizationID.rawValue),
    )
  }

  override suspend fun listPendingInvitations(): List<Invitation> {
    val response = decode<RemotePendingInvitationList>(path = "/api/v1/invites")
    return response.items.map {
      Invitation(
        id = InvitationID(rawValue = it.uuid),
        organizationID = OrganizationID(rawValue = it.organizationUUID),
        organizationName = it.organizationName,
        // The endpoint only ever lists invitations addressed to the signed-in account, and the
        // payload omits the e-mail, so the cached profile supplies it. Everything listed here is
        // pending by construction.
        email = user.email,
        role = OrganizationRole.fromWire(it.role) ?: OrganizationRole.VIEWER,
        status = InvitationStatus.PENDING,
      )
    }
  }

  override suspend fun acceptInvitation(id: InvitationID) {
    execute(path = "/api/v1/invites/${id.rawValue}/accept", method = "POST")
  }

  override suspend fun declineInvitation(id: InvitationID) {
    execute(path = "/api/v1/invites/${id.rawValue}/decline", method = "POST")
  }

  override suspend fun changePassword(
    currentPassword: String,
    newPassword: String,
    confirmPassword: String,
  ) {
    execute(
      path = "/api/v1/security/change-password",
      method = "POST",
      body = RemotePasswordChange(
        currentPassword = currentPassword,
        newPassword = newPassword,
        confirmPassword = confirmPassword,
      ),
    )
  }

  override suspend fun securitySummary(): SecuritySummary {
    val response = decode<RemoteSecuritySummary>(path = "/api/v1/security")
    return SecuritySummary(
      totpEnabled = response.totp.enabled,
      recoveryCodeCount = response.totp.recoveryCodesRemaining,
      passkeys = response.passkeys.map {
        Passkey(
          id = PasskeyID(rawValue = it.uuid),
          name = it.name,
          createdAt = WireDate.isoDate(it.createdAt),
          lastUsedAt = it.lastUsedAt?.let(WireDate::isoDate),
        )
      },
    )
  }

  override suspend fun beginTOTPEnrollment(): TOTPEnrollment {
    val response = decode<RemoteTOTPSetup>(path = "/api/v1/security/totp/setup", method = "POST")
    return TOTPEnrollment(
      secret = response.secret,
      provisioningURI = response.provisioningURI,
      qrCodeBase64 = response.qrCodeBase64,
    )
  }

  override suspend fun confirmTOTPEnrollment(code: String): List<String> =
    decode<RemoteTOTPConfirm, RemoteRecoveryCodes>(
      path = "/api/v1/security/totp/confirm",
      method = "POST",
      body = RemoteTOTPConfirm(code = code),
    ).recoveryCodes

  override suspend fun disableTOTP(password: String) {
    execute(
      path = "/api/v1/security/totp/disable",
      method = "POST",
      body = RemoteTOTPDisable(password = password),
    )
  }

  override suspend fun regenerateRecoveryCodes(): List<String> = decode<RemoteRecoveryCodes>(
    path = "/api/v1/security/recovery-codes/regenerate",
    method = "POST",
  ).recoveryCodes

  override suspend fun deletePasskey(id: PasskeyID) {
    execute(path = "/api/v1/security/passkeys/${id.rawValue}", method = "DELETE")
  }

  override suspend fun listAPIKeys(): List<APIKeyMetadata> {
    val response = decode<RemoteAPIKeyList>(path = "/api/v1/api-keys")
    // The server returns revoked keys too (it doesn't filter them); match the mock and hide them.
    return response.items.filter { it.revokedAt == null }.map(::apiKey)
  }

  override suspend fun createAPIKey(draft: APIKeyDraft): CreatedAPIKeySecret {
    val response = decode<RemoteAPIKeyCreate, RemoteCreatedAPIKey>(
      path = "/api/v1/api-keys",
      method = "POST",
      body = RemoteAPIKeyCreate.from(draft),
    )
    return CreatedAPIKeySecret(metadata = apiKey(response.apiKey), secret = response.secret)
  }

  override suspend fun updateAPIKey(id: APIKeyID, draft: APIKeyDraft): APIKeyMetadata = apiKey(
    decode<RemoteAPIKeyUpdate, RemoteAPIKey>(
      path = "/api/v1/api-keys/${id.rawValue}",
      method = "PATCH",
      body = RemoteAPIKeyUpdate.from(draft),
    )
  )

  override suspend fun revokeAPIKey(id: APIKeyID) {
    execute(path = "/api/v1/api-keys/${id.rawValue}", method = "DELETE")
  }

  override suspend fun theme(target: ThemeTarget): ThemeRecord =
    theme(decode<RemoteTheme>(path = themePath(target)))

  override suspend fun updateTheme(target: ThemeTarget, values: ThemeValues) {
    execute(path = themePath(target), method = "PUT", body = RemoteThemeValues.from(values))
  }

  override suspend fun resetTheme(target: ThemeTarget) {
    execute(path = themePath(target), method = "DELETE")
  }

  // MARK: - Transport helpers
  //
  // A decode failure is always remapped to `InvalidResponse`: the server answered, but not in a
  // shape this build understands, and the raw serialization error is not user-facing copy.

  private suspend inline fun <reified Response> decode(
    path: String,
    method: String = "GET",
  ): Response = decodeOrInvalid(client.request(path = path, method = method))

  private suspend inline fun <reified Body, reified Response> decode(
    path: String,
    method: String,
    body: Body,
  ): Response = decodeOrInvalid(
    client.request(
      path = path,
      method = method,
      body = apiJson.encodeToString(body).toByteArray(),
    )
  )

  private suspend inline fun <reified Response> decodeMultipart(
    path: String,
    name: String? = null,
    files: List<MultipartFile>,
  ): Response {
    val boundary = "RentivoBoundary-${UUID.randomUUID()}"
    return decodeOrInvalid(
      client.request(
        path = path,
        method = "POST",
        body = multipartBody(boundary = boundary, name = name, files = files),
        contentType = "multipart/form-data; boundary=$boundary",
      )
    )
  }

  private suspend fun execute(path: String, method: String) {
    client.request(path = path, method = method)
  }

  private suspend inline fun <reified Body> execute(path: String, method: String, body: Body) {
    client.request(
      path = path,
      method = method,
      body = apiJson.encodeToString(body).toByteArray(),
    )
  }

  // MARK: - Wire translation

  private fun owner(remote: RemoteOwner): BillingOwner {
    val uuid = remote.uuid
    if (remote.type == "organization" && uuid != null) {
      return BillingOwner.Organization(
        id = OrganizationID(rawValue = uuid),
        name = remote.name ?: "Organização",
      )
    }
    return BillingOwner.User(id = user.id, name = remote.name ?: "Pessoal")
  }

  /** A PIX block is only real when at least one of its three fields carries something. */
  private fun pix(key: String, name: String, city: String): PixConfiguration? {
    if (key.isEmpty() && name.isEmpty() && city.isEmpty()) return null
    return PixConfiguration(key = key, merchantName = name, merchantCity = city)
  }

  /**
   * There is no `paid_at` on the wire: for a paid bill the payment date is the calendar day of the
   * last status change, so it is read off the leading date component of `status_updated_at`.
   */
  private fun paidAt(remote: RemoteBill): DateOnly? {
    if (remote.status != "paid") return null
    val statusUpdatedAt = remote.statusUpdatedAt ?: return null
    return WireDate.dateOnly(statusUpdatedAt.substringBefore("T"))
  }

  private fun bill(remote: RemoteBill, billingID: BillingID): Bill {
    // The failable wire parser keeps a malformed `reference_month` (e.g. an out-of-range month) a
    // decode error instead of letting it reach the `require`-enforcing constructor and crash.
    val referenceMonth = ReferenceMonth.fromApiValue(remote.referenceMonth)
      ?: throw LiveAPIError.InvalidResponse
    return Bill(
      id = BillID(rawValue = remote.uuid),
      billingID = billingID,
      referenceMonth = referenceMonth,
      dueDate = WireDate.optionalDateOnly(remote.dueDate),
      paidAt = paidAt(remote),
      notes = remote.notes,
      status = BillStatus.fromWire(remote.status) ?: BillStatus.DRAFT,
      // Bill lines have no server identity of their own, so a stable per-bill synthetic id keeps
      // list diffing correct without pretending the server issued one.
      lineItems = remote.lineItems.mapIndexed { index, line ->
        BillLineItem(
          id = BillLineItemID(rawValue = "${remote.uuid}-$index"),
          description = line.description,
          amount = Money(centavos = line.amount),
          kind = BillLineItemKind.fromWire(line.itemType) ?: BillLineItemKind.FIXED,
        )
      },
      receipts = (remote.receipts ?: emptyList()).map {
        Receipt(id = ReceiptID(rawValue = it.uuid), name = it.filename, sortOrder = it.sortOrder)
      },
      // Server-authoritative transitions/total for this bill (see `Bill.effectiveTransitions` /
      // `Bill.effectiveTotal`); unrecognized transition targets are dropped rather than failing
      // the whole decode, since a missing action button is a much smaller failure than an error.
      availableTransitions = remote.availableTransitions.mapNotNull {
        BillStatus.fromWire(it.target)
      },
      serverTotal = Money(centavos = remote.totalAmount),
      // An unknown or absent render status means "not rendering" rather than a decode failure,
      // and an absent capabilities object stays permissive so older payloads keep working.
      pdfRenderStatus = PDFRenderStatus.fromWire(remote.pdfRenderStatus),
      hasInvoice = remote.hasInvoice ?: false,
      hasRecibo = remote.hasRecibo ?: false,
      capabilities = billCapabilities(remote.capabilities),
    )
  }

  private fun billCapabilities(remote: RemoteBillCapabilities?): BillCapabilities {
    if (remote == null) return BillCapabilities.permissive
    return BillCapabilities(
      canDownloadInvoice = remote.canDownloadInvoice,
      canDownloadRecibo = remote.canDownloadRecibo,
      canSendInvoice = remote.canSendInvoice,
      canSendRecibo = remote.canSendRecibo,
      canRegenerate = remote.canRegenerate,
    )
  }

  private fun billing(remote: RemoteBilling): Billing = Billing(
    id = BillingID(rawValue = remote.uuid),
    name = remote.name,
    description = remote.description,
    owner = owner(remote.owner),
    // Recurring items keep the server's own uuid; their order in the payload is their sort order.
    items = remote.items.mapIndexed { index, item ->
      BillingItem(
        id = BillingItemID(rawValue = item.uuid),
        description = item.description,
        amount = Money(centavos = item.amount),
        type = BillingItemType.fromWire(item.itemType) ?: BillingItemType.FIXED,
        sortOrder = index,
      )
    },
    pixOverride = pix(remote.pixKey, remote.pixMerchantName, remote.pixMerchantCity),
    recipients = remote.recipients.mapNotNull { contact ->
      val name = contact.name ?: return@mapNotNull null
      val email = contact.email ?: return@mapNotNull null
      BillingRecipient(id = RecipientID(rawValue = contact.uuid), name = name, email = email)
    },
    replyTo = remote.replyTo.firstOrNull()?.email,
    // Templates for communication types this app doesn't model are dropped rather than failing the
    // whole billing decode, the same tolerance applied to bill transitions above.
    communicationTemplates = (remote.communicationTemplates ?: emptyList()).mapNotNull { template ->
      CommunicationType.fromWire(template.commType)?.let {
        CommunicationTemplate(commType = it, subject = template.subject, body = template.body)
      }
    },
    capabilities = capabilities(remote.capabilities),
  )

  private fun capabilities(remote: RemoteBillingCapabilities): BillingCapabilities =
    BillingCapabilities(
      canEdit = remote.canEdit,
      canReadBills = remote.canReadBills,
      canCreateBills = remote.canCreateBills,
      canManageBills = remote.canManageBills,
      canReadExpenses = remote.canReadExpenses,
      canWriteExpenses = remote.canWriteExpenses,
      canCreateExports = remote.canCreateExports,
      canReadAttachments = remote.canReadAttachments,
      canWriteAttachments = remote.canWriteAttachments,
      canReadTheme = remote.canReadTheme,
      canManageTheme = remote.canManageTheme,
      canUploadBillReceipts = remote.canUploadBillReceipts,
      canDelete = remote.canDelete,
      canTransfer = remote.canTransfer,
    )

  private fun organization(remote: RemoteOrganization): Organization = Organization(
    id = OrganizationID(rawValue = remote.uuid),
    name = remote.name,
    pix = remote.settings?.let { pix(it.pixKey, it.pixMerchantName, it.pixMerchantCity) },
    members = (remote.members ?: emptyList()).map {
      OrganizationMember(
        userID = it.userID,
        email = it.email,
        role = OrganizationRole.fromWire(it.role) ?: OrganizationRole.VIEWER,
      )
    },
    requiresMFA = remote.enforceMFA,
    currentUserRole = OrganizationRole.fromWire(remote.currentRole) ?: OrganizationRole.VIEWER,
    capabilities = OrganizationCapabilities(
      canManage = remote.capabilities.canManage,
      canInvite = remote.capabilities.canInvite,
      canCreateBilling = remote.capabilities.canCreateBilling,
      canViewBillingStats = remote.capabilities.canViewBillingStats,
    ),
  )

  private fun apiKey(remote: RemoteAPIKey): APIKeyMetadata = APIKeyMetadata(
    id = APIKeyID(rawValue = remote.uuid),
    name = remote.name,
    hint = remote.hint,
    scopes = remote.scopes.mapNotNull { APIKeyScope.fromWire(it) }.toSet(),
    grants = remote.grants.mapNotNull { grant ->
      val resourceID = grant.resourceID ?: return@mapNotNull null
      val resourceType = WorkspaceResourceType.fromWire(grant.resourceType)
        ?: return@mapNotNull null
      APIKeyGrant(
        resourceType = resourceType,
        resourceID = WorkspaceID(rawValue = resourceID),
        available = grant.available,
      )
    },
    expiresAt = WireDate.isoDate(remote.expiresAt),
    lastUsedAt = remote.lastUsedAt?.let(WireDate::isoDate),
    createdAt = WireDate.isoDate(remote.createdAt),
    revokedAt = remote.revokedAt?.let(WireDate::isoDate),
  )

  private fun attachment(remote: RemoteAttachment): Attachment = Attachment(
    id = AttachmentID(rawValue = remote.uuid),
    name = remote.name,
    mediaType = remote.contentType,
    byteCount = remote.fileSize,
  )

  private fun expense(remote: RemoteExpense, billingID: BillingID): Expense = Expense(
    id = ExpenseID(rawValue = remote.uuid),
    billingID = billingID,
    description = remote.description,
    amount = Money(centavos = remote.amount),
    category = ExpenseCategory.fromWire(remote.category) ?: ExpenseCategory.OTHER,
    incurredOn = WireDate.dateOnly(remote.incurredOn),
  )

  private fun themePath(target: ThemeTarget): String = when (target) {
    is ThemeTarget.User -> "/api/v1/themes/user"
    is ThemeTarget.Organization -> "/api/v1/themes/organizations/${target.id.rawValue}"
    is ThemeTarget.Billing -> "/api/v1/themes/billings/${target.id.rawValue}"
  }

  private fun theme(remote: RemoteTheme): ThemeRecord = ThemeRecord(
    ownerName = remote.ownerName,
    stored = remote.stored?.toDomain(),
    effective = remote.effective.toDomain(),
    effectiveSource = ThemeSource.fromWire(remote.effectiveSource) ?: ThemeSource.DEFAULT,
    canEdit = remote.capabilities.canEdit,
    canReset = remote.capabilities.canReset,
  )
}

/** One file part of a `multipart/form-data` upload. */
internal class MultipartFile(val field: String, val upload: FileUpload)

internal fun multipartBody(
  boundary: String,
  name: String?,
  files: List<MultipartFile>,
): ByteArray {
  val body = java.io.ByteArrayOutputStream()
  fun append(text: String) = body.write(text.toByteArray())
  if (name != null) {
    append("--$boundary\r\n")
    append("Content-Disposition: form-data; name=\"name\"\r\n\r\n$name\r\n")
  }
  for (file in files) {
    append("--$boundary\r\n")
    append(
      "Content-Disposition: form-data; name=\"${file.field}\"; " +
        "filename=\"${sanitizedFilename(file.upload.filename)}\"\r\n"
    )
    append("Content-Type: ${file.upload.mediaType}\r\n\r\n")
    body.write(file.upload.data)
    append("\r\n")
  }
  append("--$boundary--\r\n")
  return body.toByteArray()
}

/**
 * Strips characters that could break out of the quoted `filename="..."` attribute (or the header
 * line entirely) and inject extra multipart headers/parts.
 */
internal fun sanitizedFilename(filename: String): String {
  var sanitized = filename
  for (token in listOf("\r\n", "\r", "\n", "\"")) {
    sanitized = sanitized.replace(token, "")
  }
  return sanitized
}

/**
 * Wires every repository to the live [store]. The demo slot stays a separate, inert repository:
 * callers must never need to know the concrete store, and `usesLiveAPI` is what separates this
 * wiring from the mock one.
 */
fun liveDependencies(store: APIRentivoStore, demo: DemoRepository): AppDependencies =
  AppDependencies(
    auth = store,
    profile = store,
    billings = store,
    bills = store,
    expenses = store,
    attachments = store,
    communications = store,
    downloads = store,
    exports = store,
    dashboard = store,
    activities = store,
    organizations = store,
    invitations = store,
    security = store,
    apiKeys = store,
    themes = store,
    demo = demo,
  )

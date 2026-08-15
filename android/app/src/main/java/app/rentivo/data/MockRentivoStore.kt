package app.rentivo.data

import app.rentivo.domain.APIKeyDraft
import app.rentivo.domain.APIKeyID
import app.rentivo.domain.APIKeyMetadata
import app.rentivo.domain.APIKeyOptions
import app.rentivo.domain.APIKeyScope
import app.rentivo.domain.APIKeyValidation
import app.rentivo.domain.APIKeyWorkspaceOption
import app.rentivo.domain.ActivityKind
import app.rentivo.domain.Attachment
import app.rentivo.domain.AttachmentID
import app.rentivo.domain.AttachmentUploadRules
import app.rentivo.domain.ReceiptUploadRules
import app.rentivo.domain.Bill
import app.rentivo.domain.BillCommunication
import app.rentivo.domain.BillDraft
import app.rentivo.domain.BillID
import app.rentivo.domain.BillStatus
import app.rentivo.domain.Billing
import app.rentivo.domain.BillingCapabilities
import app.rentivo.domain.BillingDraft
import app.rentivo.domain.BillingExportContract
import app.rentivo.domain.BillingID
import app.rentivo.domain.BillingOwner
import app.rentivo.domain.CommunicationContent
import app.rentivo.domain.CommunicationID
import app.rentivo.domain.CommunicationPreview
import app.rentivo.domain.CommunicationRecord
import app.rentivo.domain.CommunicationSaveScope
import app.rentivo.domain.CommunicationTemplate
import app.rentivo.domain.CommunicationType
import app.rentivo.domain.CreatedAPIKeySecret
import app.rentivo.domain.DateOnly
import app.rentivo.domain.DemoError
import app.rentivo.domain.DownloadedFile
import app.rentivo.domain.Expense
import app.rentivo.domain.ExpenseCategory
import app.rentivo.domain.ExpenseInput
import app.rentivo.domain.ExpenseID
import app.rentivo.domain.FileUpload
import app.rentivo.domain.Invitation
import app.rentivo.domain.InvitationAcceptance
import app.rentivo.domain.InvitationID
import app.rentivo.domain.InvitationStatus
import app.rentivo.domain.MFAChallenge
import app.rentivo.domain.MobileLoginOutcome
import app.rentivo.domain.Money
import app.rentivo.domain.Organization
import app.rentivo.domain.OrganizationCapabilities
import app.rentivo.domain.OrganizationDraft
import app.rentivo.domain.OrganizationID
import app.rentivo.domain.OrganizationInviteEmail
import app.rentivo.domain.OrganizationMember
import app.rentivo.domain.OrganizationMFAPolicy
import app.rentivo.domain.OrganizationRole
import app.rentivo.domain.PDFRenderStatus
import app.rentivo.domain.PasskeyAssertionPayload
import app.rentivo.domain.PasskeyID
import app.rentivo.domain.PasskeyRequestOptions
import app.rentivo.domain.PixConfiguration
import app.rentivo.domain.Receipt
import app.rentivo.domain.ReceiptID
import app.rentivo.domain.RecentActivity
import app.rentivo.domain.RecipientID
import app.rentivo.domain.SecuritySummary
import app.rentivo.domain.TOTPEnrollment
import app.rentivo.domain.ThemeRecord
import app.rentivo.domain.ThemeSource
import app.rentivo.domain.ThemeTarget
import app.rentivo.domain.ThemeValues
import app.rentivo.domain.UserProfile
import app.rentivo.domain.WorkspaceID
import app.rentivo.domain.WorkspaceResourceType
import java.text.Normalizer
import java.time.Instant
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.delay

/**
 * The in-memory demo backend: one object implementing every repository, over a snapshot of
 * fixtures that mutations edit in place.
 *
 * Like the iOS `@MainActor` original this is single-threaded, UI-confined state — every caller
 * reaches it from the main dispatcher, so the fields need no locking.
 */
class MockRentivoStore(fixtures: MockFixtures = MockFixtures.canonical) :
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
  ThemeRepository,
  DemoRepository {

  private val baseline: StoreSnapshot = fixtures.snapshot

  private var profileState: UserProfile = baseline.profile
  private val billingsState: MutableList<Billing> = baseline.billings.toMutableList()
  private val billsState: MutableList<Bill> = baseline.bills.toMutableList()
  private val expensesState: MutableList<Expense> = baseline.expenses.toMutableList()
  private val attachmentsState: MutableMap<BillingID, MutableList<Attachment>> =
    baseline.attachments.mapValuesTo(mutableMapOf()) { it.value.toMutableList() }
  private val organizationsState: MutableList<Organization> = baseline.organizations.toMutableList()
  private val invitationsState: MutableList<Invitation> = baseline.invitations.toMutableList()
  private val communicationsState: MutableList<CommunicationRecord> =
    baseline.communications.toMutableList()
  private var securityState: SecuritySummary = baseline.security
  private val apiKeysState: MutableList<APIKeyMetadata> = baseline.apiKeys.toMutableList()
  private val themesState: MutableMap<ThemeTarget, ThemeValues> = baseline.themes.toMutableMap()
  private val activitiesState: MutableList<RecentActivity> = baseline.activities.toMutableList()
  private val ownerCommunicationTemplates:
    MutableMap<CommunicationOwnerKey, MutableMap<CommunicationType, CommunicationTemplate>> = mutableMapOf()
  private val billingTemplateOverrides: MutableMap<BillingID, MutableSet<CommunicationType>> = mutableMapOf()

  private var emptyModeEnabled = false
  private var viewerModeEnabled = false
  private var operationDelayEnabled = false
  private var shouldFailNextOperation = false

  /**
   * Remaining [bill] fetches before a regenerated bill settles back to
   * [PDFRenderStatus.SUCCEEDED], keyed by bill.
   */
  private val pendingRenderTicks: MutableMap<BillID, Int> = mutableMapOf()

  /** A defensive copy of the current state, matching the Swift value-type `snapshot`. */
  val snapshot: StoreSnapshot
    get() = StoreSnapshot(
      profile = profileState,
      billings = billingsState.toList(),
      bills = billsState.toList(),
      expenses = expensesState.toList(),
      attachments = attachmentsState.mapValues { it.value.toList() },
      organizations = organizationsState.toList(),
      invitations = invitationsState.toList(),
      communications = communicationsState.toList(),
      security = securityState,
      apiKeys = apiKeysState.toList(),
      themes = themesState.toMap(),
      activities = activitiesState.toList(),
    )

  override val currentUser: UserProfile get() = profileState

  override val recentActivities: List<RecentActivity> get() = activitiesState.toList()

  override val usesLiveAPI: Boolean get() = false

  override val demoSettings: DemoSettings
    get() = DemoSettings(
      delayEnabled = operationDelayEnabled,
      emptyMode = emptyModeEnabled,
      viewerMode = viewerModeEnabled,
    )

  // The demo store holds no server session: there is never a stored credential to resume, and
  // signing out or deleting the account has nothing to revoke remotely. `AppModel` reaches these
  // only through `AuthRepository`; the demo-specific screen transitions stay in `AppModel`,
  // selected by `usesLiveAPI`.
  override suspend fun restoreSession(): UserProfile? = null

  // The demo has no credentials to check and no second factor to enrol, so native sign-in always
  // succeeds immediately as the demo user and never reports `MfaRequired`. That makes the
  // challenge-bound calls below unreachable from the demo UI; they exist only to satisfy
  // `AuthRepository` and behave as no-op successes if a caller reaches them anyway.
  override suspend fun mobileLogin(email: String, password: String): MobileLoginOutcome =
    MobileLoginOutcome.Authenticated(profileState)

  override suspend fun mobileSignup(email: String, password: String): UserProfile = profileState

  override suspend fun verifyTotp(challenge: MFAChallenge, code: String): UserProfile = profileState

  override suspend fun verifyRecoveryCode(challenge: MFAChallenge, code: String): UserProfile =
    profileState

  override suspend fun beginPasskeyAssertion(challenge: MFAChallenge): PasskeyRequestOptions =
    PasskeyRequestOptions(
      challenge = ByteArray(0),
      relyingPartyIdentifier = "",
      allowedCredentialIDs = emptyList(),
      userVerification = "preferred",
      timeoutMilliseconds = 60_000,
    )

  override suspend fun completePasskeyAssertion(
    challenge: MFAChallenge,
    credential: PasskeyAssertionPayload,
  ): UserProfile = profileState

  override suspend fun logout() = Unit

  override suspend fun deleteAccount(password: String) = Unit

  override fun failNextOperation() {
    shouldFailNextOperation = true
  }

  override fun setEmptyMode(enabled: Boolean) {
    emptyModeEnabled = enabled
  }

  override fun setViewerMode(enabled: Boolean) {
    viewerModeEnabled = enabled
  }

  override fun setDelayEnabled(enabled: Boolean) {
    operationDelayEnabled = enabled
  }

  override fun reset() {
    profileState = baseline.profile
    billingsState.replaceAllWith(baseline.billings)
    billsState.replaceAllWith(baseline.bills)
    expensesState.replaceAllWith(baseline.expenses)
    attachmentsState.clear()
    baseline.attachments.forEach { (id, items) -> attachmentsState[id] = items.toMutableList() }
    organizationsState.replaceAllWith(baseline.organizations)
    invitationsState.replaceAllWith(baseline.invitations)
    communicationsState.replaceAllWith(baseline.communications)
    securityState = baseline.security
    apiKeysState.replaceAllWith(baseline.apiKeys)
    themesState.clear()
    themesState.putAll(baseline.themes)
    activitiesState.replaceAllWith(baseline.activities)
    emptyModeEnabled = false
    viewerModeEnabled = false
    operationDelayEnabled = false
    shouldFailNextOperation = false
    pendingRenderTicks.clear()
    ownerCommunicationTemplates.clear()
    billingTemplateOverrides.clear()
  }

  override suspend fun profile(): UserProfile {
    prepareOperation()
    return profileState
  }

  override suspend fun changePassword(
    currentPassword: String,
    newPassword: String,
    confirmPassword: String,
  ) {
    prepareOperation()
    if (currentPassword.isEmpty() || newPassword.isEmpty() || newPassword != confirmPassword) {
      throw DemoError.operationFailed
    }
  }

  override suspend fun updatePix(pix: PixConfiguration): UserProfile {
    prepareOperation()
    if (viewerModeEnabled) throw DemoError.permissionDenied
    profileState = profileState.copy(pix = pix.takeUnless { it.isEmpty })
    recordActivity(kind = ActivityKind.BILLING, title = "PIX atualizado", detail = pix.key)
    return profileState
  }

  override suspend fun listBillings(): List<Billing> {
    prepareOperation()
    if (emptyModeEnabled) return emptyList()
    return billingsState.map(::restrictIfNeeded)
  }

  override suspend fun billing(id: BillingID): Billing {
    prepareOperation()
    val billing = billingsState.firstOrNull { it.id == id } ?: throw DemoError.resourceNotFound
    return restrictIfNeeded(billing)
  }

  override suspend fun createBilling(draft: BillingDraft): Billing {
    prepareOperation()
    requireWriteAccess()
    var billing = Billing(
      id = BillingID(rawValue = UUID.randomUUID().toString()),
      name = draft.name,
      description = draft.description,
      owner = draft.owner,
      items = draft.items,
      pixOverride = draft.pixOverride,
      recipients = draft.recipients,
      replyTo = draft.replyTo,
      // The server always resolves a template per communication type (billing, then owner,
      // then system default), so a fresh billing is never template-less in production.
      communicationTemplates = MockFixtures.defaultCommunicationTemplates,
    )
    ownerCommunicationTemplates[CommunicationOwnerKey(draft.owner)]?.values?.forEach { template ->
      billing = billing.withCommunicationTemplate(template)
    }
    billingsState.add(0, billing)
    recordActivity(kind = ActivityKind.BILLING, title = "Cobrança criada", detail = billing.name)
    return billing
  }

  override suspend fun updateBilling(id: BillingID, draft: BillingDraft): Billing {
    prepareOperation()
    requireWriteAccess()
    val index = billingsState.indexOfFirst { it.id == id }
    if (index < 0) throw DemoError.resourceNotFound
    val existing = billingsState[index]
    val billing = Billing(
      id = id,
      name = draft.name,
      description = draft.description,
      owner = draft.owner,
      items = draft.items,
      pixOverride = draft.pixOverride,
      recipients = draft.recipients,
      replyTo = draft.replyTo,
      // Editing a billing never touches its templates; the draft does not carry them.
      communicationTemplates = existing.communicationTemplates,
      capabilities = existing.capabilities,
    )
    billingsState[index] = billing
    recordActivity(kind = ActivityKind.BILLING, title = "Cobrança atualizada", detail = billing.name)
    return billing
  }

  override suspend fun deleteBilling(id: BillingID) {
    prepareOperation()
    requireWriteAccess()
    val index = billingsState.indexOfFirst { it.id == id }
    if (index < 0) throw DemoError.resourceNotFound
    val name = billingsState[index].name
    billingsState.removeAt(index)
    billingTemplateOverrides.remove(id)
    billsState.removeAll { it.billingID == id }
    expensesState.removeAll { it.billingID == id }
    attachmentsState.remove(id)
    themesState.remove(ThemeTarget.Billing(id))
    recordActivity(kind = ActivityKind.BILLING, title = "Cobrança excluída", detail = name)
  }

  override suspend fun listBills(billingID: BillingID): List<Bill> {
    prepareOperation()
    if (billingsState.none { it.id == billingID }) throw DemoError.resourceNotFound
    if (emptyModeEnabled) return emptyList()
    return billsState
      .filter { it.billingID == billingID }
      .sortedByDescending { it.referenceMonth }
      .map(::restrictIfNeeded)
  }

  override suspend fun bill(billingID: BillingID, id: BillID): Bill {
    prepareOperation()
    val index = billIndex(billingID = billingID, billID = id) ?: throw DemoError.resourceNotFound
    advancePendingRender(index = index, billID = id)
    return restrictIfNeeded(withCommunicationHistory(billsState[index]))
  }

  private fun withCommunicationHistory(bill: Bill): Bill = bill.copy(
    communications = communicationsState
      .filter { it.billID == bill.id }
      .flatMap { record ->
        record.recipients.mapIndexed { index, email ->
          BillCommunication(
            id = CommunicationID(rawValue = "${record.id.rawValue}-$index"),
            commType = null,
            status = "sent",
            createdAt = record.sentAt,
            sentAt = record.sentAt,
            recipientName = null,
            recipientEmail = email,
            subject = record.subject,
          )
        }
      },
  )

  /**
   * Demo mode fakes the background render: each fetch consumes one tick of the countdown started
   * by [regenerateBill], so the detail screen's poll loop runs for real before settling.
   */
  private fun advancePendingRender(index: Int, billID: BillID) {
    val remaining = pendingRenderTicks[billID] ?: return
    if (remaining > 1) {
      pendingRenderTicks[billID] = remaining - 1
    } else {
      pendingRenderTicks.remove(billID)
      billsState[index] = billsState[index].copy(pdfRenderStatus = PDFRenderStatus.SUCCEEDED)
    }
  }

  override suspend fun createBill(draft: BillDraft): Bill {
    prepareOperation()
    requireWriteAccess()
    if (billingsState.none { it.id == draft.billingID }) throw DemoError.resourceNotFound
    if (draft.validate().isNotEmpty()) throw DemoError.operationFailed
    val bill = Bill(
      id = BillID(rawValue = UUID.randomUUID().toString()),
      billingID = draft.billingID,
      referenceMonth = draft.referenceMonth,
      dueDate = draft.dueDate,
      paidAt = null,
      notes = draft.notes,
      status = BillStatus.DRAFT,
      lineItems = draft.lineItems,
      receipts = emptyList(),
    )
    billsState.add(0, bill)
    recordActivity(
      kind = ActivityKind.BILL,
      title = "Fatura criada",
      detail = draft.referenceMonth.label,
    )
    return bill
  }

  override suspend fun updateBill(
    billingID: BillingID,
    billID: BillID,
    draft: BillDraft,
  ): Bill {
    prepareOperation()
    requireWriteAccess()
    if (draft.billingID != billingID || draft.validate().isNotEmpty()) {
      throw DemoError.operationFailed
    }
    val index = billIndex(billingID = billingID, billID = billID)
      ?: throw DemoError.resourceNotFound
    if (billsState[index].status != BillStatus.DRAFT) throw DemoError.permissionDenied
    billsState[index] = billsState[index].copy(
      referenceMonth = draft.referenceMonth,
      dueDate = draft.dueDate,
      notes = draft.notes,
      lineItems = draft.lineItems,
    )
    recordActivity(
      kind = ActivityKind.BILL,
      title = "Fatura atualizada",
      detail = draft.referenceMonth.label,
    )
    return billsState[index]
  }

  override suspend fun deleteBill(billingID: BillingID, billID: BillID) {
    prepareOperation()
    requireWriteAccess()
    val index = billIndex(billingID = billingID, billID = billID)
      ?: throw DemoError.resourceNotFound
    val reference = billsState[index].referenceMonth.label
    billsState.removeAt(index)
    recordActivity(kind = ActivityKind.BILL, title = "Fatura excluída", detail = reference)
  }

  override suspend fun transitionBill(
    billingID: BillingID,
    billID: BillID,
    currentStatus: BillStatus,
    status: BillStatus,
  ) {
    prepareOperation()
    requireWriteAccess()
    val index = billIndex(billingID = billingID, billID = billID)
      ?: throw DemoError.resourceNotFound
    if (billsState[index].status != currentStatus) throw DemoError.staleBillStatus
    if (!billsState[index].status.canTransition(status)) throw DemoError.invalidBillTransition
    billsState[index] = billsState[index].copy(
      status = status,
      paidAt = if (status == BillStatus.PAID) {
        DateOnly(year = 2026, month = 7, day = 20)
      } else {
        billsState[index].paidAt
      },
    )
    val billingName = billingsState.firstOrNull { it.id == billingID }?.name ?: "Cobrança"
    recordActivity(
      kind = ActivityKind.BILL,
      title = "Fatura ${status.label.lowercase(Locale.ROOT)}",
      detail = billingName,
    )
  }

  override suspend fun regenerateBill(billingID: BillingID, billID: BillID): Bill {
    prepareOperation()
    requireWriteAccess()
    val index = billIndex(billingID = billingID, billID = billID)
      ?: throw DemoError.resourceNotFound
    billsState[index] = billsState[index].copy(pdfRenderStatus = PDFRenderStatus.PENDING)
    pendingRenderTicks[billID] = PENDING_RENDER_TICK_COUNT
    return billsState[index]
  }

  override suspend fun addReceipt(
    billingID: BillingID,
    billID: BillID,
    upload: FileUpload,
  ): Receipt {
    prepareOperation()
    requireWriteAccess()
    val index = billIndex(billingID = billingID, billID = billID)
      ?: throw DemoError.resourceNotFound
    val validatedUpload = ReceiptUploadRules.validated(upload)
    val receipt = Receipt(
      id = ReceiptID(rawValue = UUID.randomUUID().toString()),
      name = validatedUpload.filename,
      sortOrder = billsState[index].receipts.size,
      mediaType = validatedUpload.mediaType,
      byteCount = validatedUpload.byteCount,
      createdAt = Instant.now(),
    )
    billsState[index] = billsState[index].copy(
      receipts = billsState[index].receipts + receipt,
    )
    recordActivity(
      kind = ActivityKind.BILL,
      title = "Comprovante adicionado",
      detail = validatedUpload.filename,
    )
    return receipt
  }

  override suspend fun reorderReceipts(
    billingID: BillingID,
    billID: BillID,
    receiptIDs: List<ReceiptID>,
  ) {
    prepareOperation()
    requireWriteAccess()
    val index = billIndex(billingID = billingID, billID = billID)
      ?: throw DemoError.resourceNotFound
    val current = billsState[index].receipts
    if (current.map { it.id }.toSet() != receiptIDs.toSet() || current.size != receiptIDs.size) {
      throw DemoError.operationFailed
    }
    val byID = current.associateBy { it.id }
    billsState[index] = billsState[index].copy(
      receipts = receiptIDs.mapIndexedNotNull { offset, id ->
        byID[id]?.copy(sortOrder = offset)
      },
    )
  }

  override suspend fun deleteReceipt(
    billingID: BillingID,
    billID: BillID,
    receiptID: ReceiptID,
  ) {
    prepareOperation()
    requireWriteAccess()
    val index = billIndex(billingID = billingID, billID = billID)
      ?: throw DemoError.resourceNotFound
    if (billsState[index].receipts.none { it.id == receiptID }) throw DemoError.resourceNotFound
    billsState[index] = billsState[index].copy(
      receipts = billsState[index].receipts
        .filterNot { it.id == receiptID }
        .mapIndexed { offset, receipt -> receipt.copy(sortOrder = offset) },
    )
  }

  override suspend fun listExpenses(billingID: BillingID): List<Expense> {
    prepareOperation()
    if (billingsState.none { it.id == billingID }) throw DemoError.resourceNotFound
    if (emptyModeEnabled) return emptyList()
    return expensesState
      .filter { it.billingID == billingID }
      .sortedByDescending { it.incurredOn }
  }

  override suspend fun createExpense(
    billingID: BillingID,
    description: String,
    category: ExpenseCategory,
    incurredOn: DateOnly,
    amount: Money,
  ): Expense {
    prepareOperation()
    requireWriteAccess()
    if (billingsState.none { it.id == billingID }) throw DemoError.resourceNotFound
    // Matches the server contract: `ExpenseCreateRequest.amount` requires
    // `exclusiveMinimum: 0`, so a zero or negative expense always 422s.
    if (amount.centavos <= 0) throw DemoError.invalidAmount
    if (!ExpenseInput.isValidDescription(description)) throw DemoError.invalidDescription
    val normalizedDescription = ExpenseInput.normalizedDescription(description)
    val expense = Expense(
      id = ExpenseID(rawValue = UUID.randomUUID().toString()),
      billingID = billingID,
      description = normalizedDescription,
      amount = amount,
      category = category,
      incurredOn = incurredOn,
    )
    expensesState.add(0, expense)
    recordActivity(
      kind = ActivityKind.EXPENSE,
      title = "Despesa adicionada",
      detail = normalizedDescription,
    )
    return expense
  }

  override suspend fun deleteExpense(billingID: BillingID, expenseID: ExpenseID) {
    prepareOperation()
    requireWriteAccess()
    val index = expensesState.indexOfFirst { it.billingID == billingID && it.id == expenseID }
    if (index < 0) throw DemoError.resourceNotFound
    val description = expensesState[index].description
    expensesState.removeAt(index)
    recordActivity(kind = ActivityKind.EXPENSE, title = "Despesa excluída", detail = description)
  }

  override suspend fun listAttachments(billingID: BillingID): List<Attachment> {
    prepareOperation()
    if (billingsState.none { it.id == billingID }) throw DemoError.resourceNotFound
    if (emptyModeEnabled) return emptyList()
    return attachmentsState[billingID]?.toList() ?: emptyList()
  }

  override suspend fun addAttachment(billingID: BillingID, upload: FileUpload): Attachment {
    prepareOperation()
    requireWriteAccess()
    val upload = AttachmentUploadRules.validated(upload)
    if (billingsState.none { it.id == billingID }) throw DemoError.resourceNotFound
    val attachment = Attachment(
      id = AttachmentID(rawValue = UUID.randomUUID().toString()),
      name = upload.filename,
      mediaType = upload.mediaType,
      byteCount = upload.byteCount,
    )
    attachmentsState.getOrPut(billingID) { mutableListOf() }.add(attachment)
    recordActivity(
      kind = ActivityKind.BILLING,
      title = "Arquivo adicionado",
      detail = upload.filename,
    )
    return attachment
  }

  override suspend fun deleteAttachment(billingID: BillingID, attachmentID: AttachmentID) {
    prepareOperation()
    requireWriteAccess()
    val attachments = attachmentsState[billingID]
    if (attachments?.any { it.id == attachmentID } != true) throw DemoError.resourceNotFound
    attachments.removeAll { it.id == attachmentID }
  }

  override suspend fun previewCommunication(
    billingID: BillingID,
    subject: String,
    message: String,
  ): CommunicationPreview {
    prepareOperation()
    if (billingsState.none { it.id == billingID }) throw DemoError.resourceNotFound
    // A deliberately tiny stand-in for the server-side moderation scan, just so demo mode can
    // exercise the "reconheço o aviso" warning flow and the blocking one. Both lists below are
    // small subsets of the real PT-BR lexicons in backend/rentivo/communications/moderation.py
    // (`_MILD` and `_SEVERE_PHRASES`), so demo mode never flags text the server accepts. Unlike
    // the server it only folds case and accents — no leetspeak folding, no word boundaries.
    val mildTerms = listOf("babaca", "otario")
    val severeTerms = listOf("vou te matar")
    val scanned = fold("$subject\n$message")
    val mild = mildTerms.filter { scanned.contains(it) }
    val severe = severeTerms.filter { scanned.contains(it) }
    return CommunicationPreview(html = message, severeWarnings = severe, mildWarnings = mild)
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
    prepareOperation()
    requireWriteAccess()
    val billing = billingsState.firstOrNull { it.id == billingID }
    if (billing == null || recipientIDs.isEmpty()) throw DemoError.operationFailed
    if (billIndex(billingID = billingID, billID = billID) == null) throw DemoError.resourceNotFound
    if (saveScope == CommunicationSaveScope.OWNER && !billing.capabilities.canEdit) {
      throw DemoError.permissionDenied
    }
    val byID = billing.recipients.associateBy { it.id }
    val selected = recipientIDs.mapNotNull { byID[it] }
    if (selected.size != recipientIDs.size) throw DemoError.operationFailed
    val validationMessage = CommunicationContent.validationMessage(subject = subject, message = message)
    if (validationMessage != null) throw DemoError(message = validationMessage)
    val normalizedSubject = CommunicationContent.normalizedSubject(subject)
    val normalizedMessage = CommunicationContent.normalizedMessage(message)
    val communication = CommunicationRecord(
      id = CommunicationID(rawValue = UUID.randomUUID().toString()),
      billingID = billingID,
      billID = billID,
      recipients = selected.map { it.email },
      subject = normalizedSubject,
      message = normalizedMessage,
      sentAt = Instant.now(),
    )
    communicationsState.add(0, communication)
    if (saveScope != null) {
      saveCommunicationTemplate(
        scope = saveScope,
        billing = billing,
        commType = commType,
        subject = normalizedSubject,
        body = normalizedMessage,
      )
    }
    recordActivity(kind = ActivityKind.BILL, title = "Comunicação simulada", detail = normalizedSubject)
    return selected.size
  }

  override suspend fun downloadInvoice(billingID: BillingID, billID: BillID): DownloadedFile =
    throw DemoError.operationFailed

  override suspend fun downloadRecibo(billingID: BillingID, billID: BillID): DownloadedFile =
    throw DemoError.operationFailed

  override suspend fun downloadReceipt(
    billingID: BillingID,
    billID: BillID,
    receiptID: ReceiptID,
  ): DownloadedFile = throw DemoError.operationFailed

  override suspend fun downloadAttachment(
    billingID: BillingID,
    attachmentID: AttachmentID,
  ): DownloadedFile = throw DemoError.operationFailed

  override suspend fun requestExport(billingID: BillingID, format: String) {
    prepareOperation()
    requireWriteAccess()
    if (billingsState.none { it.id == billingID }) throw DemoError.resourceNotFound
    if (format !in BillingExportContract.formats) throw DemoError("Escolha CSV ou XLSX.")
    recordActivity(
      kind = ActivityKind.BILLING,
      title = "Exportação solicitada",
      detail = format.uppercase(),
    )
  }

  override suspend fun dashboardSummary(): DashboardSummary {
    prepareOperation()
    if (emptyModeEnabled) {
      return DashboardSummary(
        received = Money.zero,
        expenses = Money.zero,
        netIncome = Money.zero,
        overdue = Money.zero,
        upcoming = Money.zero,
        collectionRatePercent = 0,
      )
    }
    val activeBills = billsState.filter { it.status != BillStatus.CANCELLED }
    val received = total(activeBills.filter { it.status == BillStatus.PAID })
    val overdue = total(activeBills.filter { it.status == BillStatus.DELAYED_PAYMENT })
    val upcomingStatuses = setOf(BillStatus.DRAFT, BillStatus.PUBLISHED, BillStatus.SENT)
    val upcoming = total(activeBills.filter { upcomingStatuses.contains(it.status) })
    val expenses = expensesState.fold(Money.zero) { running, expense -> running + expense.amount }
    val eligibleCount = activeBills.size
    val paidCount = activeBills.count { it.status == BillStatus.PAID }
    // Integer math only, matching the live store and the repo's no-float rule.
    val collectionRate = if (eligibleCount == 0) 0 else (paidCount * 100) / eligibleCount
    return DashboardSummary(
      received = received,
      expenses = expenses,
      netIncome = received - expenses,
      overdue = overdue,
      upcoming = upcoming,
      collectionRatePercent = collectionRate,
    )
  }

  override suspend fun listOrganizations(): List<Organization> {
    prepareOperation()
    if (emptyModeEnabled) return emptyList()
    return organizationsState
      .filter { organization -> organization.members.any { it.userID == profileState.id } }
      .map(::restrictIfNeeded)
  }

  override suspend fun organization(id: OrganizationID): Organization {
    prepareOperation()
    val organization = organizationsState.firstOrNull { it.id == id }
      ?: throw DemoError.resourceNotFound
    return restrictIfNeeded(organization)
  }

  override suspend fun createOrganization(draft: OrganizationDraft): Organization {
    prepareOperation()
    requireWriteAccess()
    if (!draft.isValid) throw DemoError.operationFailed
    val organization = Organization(
      id = OrganizationID(rawValue = UUID.randomUUID().toString()),
      name = draft.name,
      pix = draft.pix,
      members = listOf(
        OrganizationMember(
          userID = profileState.id,
          email = profileState.email,
          role = OrganizationRole.ADMIN,
        )
      ),
      requiresMFA = false,
      currentUserRole = OrganizationRole.ADMIN,
    )
    organizationsState.add(0, organization)
    recordActivity(
      kind = ActivityKind.ORGANIZATION,
      title = "Organização criada",
      detail = organization.name,
    )
    return organization
  }

  override suspend fun updateOrganization(
    id: OrganizationID,
    draft: OrganizationDraft,
  ): Organization {
    prepareOperation()
    requireWriteAccess()
    requireOrganizationCapability(id) { it.canManage }
    if (!draft.isValid) throw DemoError.operationFailed
    val index = organizationIndex(id) ?: throw DemoError.resourceNotFound
    organizationsState[index] = organizationsState[index].copy(name = draft.name, pix = draft.pix)
    for (billingIndex in billingsState.indices) {
      val owner = billingsState[billingIndex].owner
      if (owner is BillingOwner.Organization && owner.id == id) {
        billingsState[billingIndex] = billingsState[billingIndex].copy(
          owner = BillingOwner.Organization(id = id, name = draft.name),
        )
      }
    }
    recordActivity(
      kind = ActivityKind.ORGANIZATION,
      title = "Organização atualizada",
      detail = draft.name,
    )
    return organizationsState[index]
  }

  override suspend fun deleteOrganization(id: OrganizationID) {
    prepareOperation()
    requireWriteAccess()
    requireOrganizationCapability(id) { it.canManage }
    val index = organizationIndex(id) ?: throw DemoError.resourceNotFound
    val hasBillings = billingsState.any { billing ->
      val owner = billing.owner
      owner is BillingOwner.Organization && owner.id == id
    }
    if (hasBillings) throw DemoError.operationFailed
    val name = organizationsState[index].name
    organizationsState.removeAt(index)
    themesState.remove(ThemeTarget.Organization(id))
    recordActivity(kind = ActivityKind.ORGANIZATION, title = "Organização excluída", detail = name)
  }

  override suspend fun updateMemberRole(
    organizationID: OrganizationID,
    userID: Int,
    role: OrganizationRole,
  ) {
    prepareOperation()
    requireWriteAccess()
    requireOrganizationCapability(organizationID) { it.canManage }
    val index = organizationIndex(organizationID) ?: throw DemoError.resourceNotFound
    val memberIndex = organizationsState[index].members.indexOfFirst { it.userID == userID }
    if (memberIndex < 0) throw DemoError.resourceNotFound
    val members = organizationsState[index].members.toMutableList()
    members[memberIndex] = members[memberIndex].copy(role = role)
    organizationsState[index] = organizationsState[index].copy(members = members.toList())
    recordActivity(
      kind = ActivityKind.ORGANIZATION,
      title = "Função atualizada",
      detail = members[memberIndex].email,
    )
  }

  override suspend fun removeMember(organizationID: OrganizationID, userID: Int) {
    prepareOperation()
    requireWriteAccess()
    requireOrganizationCapability(organizationID) { it.canManage }
    val index = organizationIndex(organizationID) ?: throw DemoError.resourceNotFound
    val member = organizationsState[index].members.firstOrNull { it.userID == userID }
      ?: throw DemoError.resourceNotFound
    organizationsState[index] = organizationsState[index].copy(
      members = organizationsState[index].members.filterNot { it.userID == userID },
    )
    recordActivity(
      kind = ActivityKind.ORGANIZATION,
      title = "Membro removido",
      detail = member.email,
    )
  }

  override suspend fun inviteMember(
    organizationID: OrganizationID,
    email: String,
    role: OrganizationRole,
  ): Invitation {
    prepareOperation()
    requireWriteAccess()
    requireOrganizationCapability(organizationID) { it.canInvite }
    val index = organizationIndex(organizationID)
    if (index == null || !OrganizationInviteEmail.isValid(email)) throw DemoError.operationFailed
    val normalizedEmail = OrganizationInviteEmail.normalized(email)
    val invitation = Invitation(
      id = InvitationID(rawValue = UUID.randomUUID().toString()),
      organizationID = organizationID,
      organizationName = organizationsState[index].name,
      email = normalizedEmail,
      role = role,
      status = InvitationStatus.PENDING,
    )
    invitationsState.add(0, invitation)
    recordActivity(kind = ActivityKind.INVITATION, title = "Convite criado", detail = normalizedEmail)
    return invitation
  }

  override suspend fun setOrganizationMFA(
    organizationID: OrganizationID,
    required: Boolean,
  ): OrganizationMFAPolicy {
    prepareOperation()
    requireWriteAccess()
    requireOrganizationCapability(organizationID) { it.canManage }
    val index = organizationIndex(organizationID) ?: throw DemoError.resourceNotFound
    organizationsState[index] = organizationsState[index].copy(requiresMFA = required)
    val organizationEnforced = organizationsState.any { it.requiresMFA }
    securityState = securityState.copy(
      organizationEnforced = organizationEnforced,
      setupRequired = organizationEnforced &&
        !securityState.totpEnabled &&
        securityState.passkeys.isEmpty(),
    )
    recordActivity(
      kind = ActivityKind.SECURITY,
      title = if (required) "MFA obrigatório" else "MFA opcional",
      detail = organizationsState[index].name,
    )
    return OrganizationMFAPolicy(
      enforceMFA = required,
      mfaSetupRequired = securityState.setupRequired,
    )
  }

  override suspend fun transferBilling(
    billingID: BillingID,
    toOrganizationID: OrganizationID,
  ) {
    prepareOperation()
    requireWriteAccess()
    requireOrganizationCapability(toOrganizationID) { it.canCreateBilling }
    val billingIndex = billingsState.indexOfFirst { it.id == billingID }
    val organizationIndex = organizationIndex(toOrganizationID)
    if (billingIndex < 0 || organizationIndex == null) throw DemoError.resourceNotFound
    val organization = organizationsState[organizationIndex]
    if (organization.members.none { it.userID == profileState.id }) {
      throw DemoError.permissionDenied
    }
    billingsState[billingIndex] = billingsState[billingIndex].copy(
      owner = BillingOwner.Organization(id = organization.id, name = organization.name),
    )
    for (commType in CommunicationType.entries) {
      if (billingTemplateOverrides[billingID]?.contains(commType) == true) continue
      val template = ownerCommunicationTemplates[CommunicationOwnerKey(billingsState[billingIndex].owner)]?.get(commType)
        ?: MockFixtures.defaultCommunicationTemplates.firstOrNull { it.commType == commType }
      if (template != null) {
        billingsState[billingIndex] = billingsState[billingIndex].withCommunicationTemplate(template)
      }
    }
    recordActivity(
      kind = ActivityKind.BILLING,
      title = "Cobrança transferida",
      detail = organization.name,
    )
  }

  override suspend fun listPendingInvitations(): List<Invitation> {
    prepareOperation()
    if (emptyModeEnabled) return emptyList()
    return invitationsState.filter { it.status == InvitationStatus.PENDING }
  }

  override suspend fun acceptInvitation(id: InvitationID): InvitationAcceptance {
    respondToInvitation(id = id, status = InvitationStatus.ACCEPTED)
    val invitation = invitationsState.firstOrNull { it.id == id }
      ?: throw DemoError.resourceNotFound
    return InvitationAcceptance(
      organizationID = invitation.organizationID,
      mfaSetupRequired = securityState.setupRequired,
    )
  }

  override suspend fun declineInvitation(id: InvitationID) {
    respondToInvitation(id = id, status = InvitationStatus.DECLINED)
  }

  override suspend fun securitySummary(): SecuritySummary {
    prepareOperation()
    return securityState
  }

  private suspend fun setTOTPEnabled(enabled: Boolean) {
    prepareOperation()
    requireWriteAccess()
    if (!enabled && securityState.organizationEnforced && securityState.passkeys.isEmpty()) {
      throw DemoError.permissionDenied
    }
    securityState = securityState.copy(
      totpEnabled = enabled,
      recoveryCodeCount = if (enabled) securityState.recoveryCodeCount else 0,
      setupRequired = securityState.organizationEnforced &&
        !enabled &&
        securityState.passkeys.isEmpty(),
    )
    recordActivity(
      kind = ActivityKind.SECURITY,
      title = if (enabled) "TOTP ativado" else "TOTP desativado",
      detail = profileState.email,
    )
  }

  override suspend fun beginTOTPEnrollment(): TOTPEnrollment {
    prepareOperation()
    requireWriteAccess()
    return TOTPEnrollment(
      secret = "JBSWY3DPEHPK3PXP",
      provisioningURI = "otpauth://totp/Rentivo:demo",
      qrCodeBase64 = "",
    )
  }

  override suspend fun confirmTOTPEnrollment(code: String): List<String> {
    if (code.trim().isEmpty()) throw DemoError.operationFailed
    setTOTPEnabled(true)
    return regenerateRecoveryCodes()
  }

  override suspend fun disableTOTP(password: String) {
    if (password.trim().isEmpty()) throw DemoError.operationFailed
    setTOTPEnabled(false)
  }

  override suspend fun regenerateRecoveryCodes(): List<String> {
    prepareOperation()
    requireWriteAccess()
    if (!securityState.totpEnabled) throw DemoError.operationFailed
    val codes = listOf(
      "RNTV-7K2P", "RNTV-4M9Q", "RNTV-8X3L", "RNTV-2N6C",
      "RNTV-5B1W", "RNTV-9J4R", "RNTV-3F8T", "RNTV-6D2H",
    )
    securityState = securityState.copy(recoveryCodeCount = codes.size)
    recordActivity(
      kind = ActivityKind.SECURITY,
      title = "Códigos renovados",
      detail = "${codes.size} códigos",
    )
    return codes
  }

  override suspend fun deletePasskey(id: PasskeyID) {
    prepareOperation()
    requireWriteAccess()
    if (securityState.passkeys.none { it.id == id }) throw DemoError.resourceNotFound
    if (
      securityState.organizationEnforced &&
      !securityState.totpEnabled &&
      securityState.passkeys.size == 1
    ) {
      throw DemoError.permissionDenied
    }
    securityState = securityState.copy(
      passkeys = securityState.passkeys.filterNot { it.id == id },
      setupRequired = securityState.organizationEnforced &&
        !securityState.totpEnabled &&
        securityState.passkeys.size == 1,
    )
    recordActivity(
      kind = ActivityKind.SECURITY,
      title = "Chave de acesso removida",
      detail = profileState.email,
    )
  }

  override suspend fun apiKeyOptions(): APIKeyOptions {
    prepareOperation()
    return APIKeyOptions(
      scopes = APIKeyScope.integrationCases,
      personalWorkspace = APIKeyWorkspaceOption(
        resourceType = WorkspaceResourceType.USER,
        resourceID = WorkspaceID.personal,
        name = "Conta pessoal",
      ),
      organizations = organizationsState.map { organization ->
        APIKeyWorkspaceOption(
          resourceType = WorkspaceResourceType.ORGANIZATION,
          resourceID = WorkspaceID(rawValue = organization.id.rawValue),
          name = organization.name,
        )
      },
      defaultExpirationDays = 90,
      maxExpirationDays = 365,
    )
  }

  override suspend fun listAPIKeys(): List<APIKeyMetadata> {
    prepareOperation()
    if (emptyModeEnabled) return emptyList()
    return apiKeysState.toList()
  }

  override suspend fun createAPIKey(draft: APIKeyDraft): CreatedAPIKeySecret {
    prepareOperation()
    requireWriteAccess()
    val metadata = APIKeyMetadata(
      id = APIKeyID(rawValue = UUID.randomUUID().toString()),
      name = draft.name,
      hint = "rntv-v1-demo••42",
      scopes = draft.scopes,
      grants = draft.grants,
      expiresAt = draft.expiresAt,
      lastUsedAt = null,
      createdAt = Instant.now(),
      revokedAt = null,
    )
    apiKeysState.add(0, metadata)
    recordActivity(
      kind = ActivityKind.API_KEY,
      title = "Chave de API criada",
      detail = metadata.name,
    )
    return CreatedAPIKeySecret(metadata = metadata, secret = "rntv-v1-demo-8K2P-N4M7-X9Q3")
  }

  override suspend fun updateAPIKey(
    id: APIKeyID,
    draft: APIKeyDraft,
    updateGrants: Boolean,
  ): APIKeyMetadata {
    prepareOperation()
    requireWriteAccess()
    if (
      !APIKeyValidation.isValidName(draft.name) ||
      draft.scopes.isEmpty() ||
      (updateGrants && draft.grants.isEmpty())
    ) {
      throw DemoError.operationFailed
    }
    val index = apiKeysState.indexOfFirst { it.id == id && it.revokedAt == null }
    if (index < 0) throw DemoError.resourceNotFound
    apiKeysState[index] = apiKeysState[index].copy(
      name = draft.name,
      scopes = draft.scopes,
      grants = if (updateGrants) draft.grants else apiKeysState[index].grants,
    )
    recordActivity(
      kind = ActivityKind.API_KEY,
      title = "Chave de API atualizada",
      detail = apiKeysState[index].name,
    )
    return apiKeysState[index]
  }

  override suspend fun revokeAPIKey(id: APIKeyID) {
    prepareOperation()
    requireWriteAccess()
    val index = apiKeysState.indexOfFirst { it.id == id && it.revokedAt == null }
    if (index < 0) throw DemoError.resourceNotFound
    apiKeysState[index] = apiKeysState[index].copy(revokedAt = Instant.now())
    recordActivity(
      kind = ActivityKind.API_KEY,
      title = "Chave de API revogada",
      detail = apiKeysState[index].name,
    )
  }

  override suspend fun theme(target: ThemeTarget): ThemeRecord {
    prepareOperation()
    val stored = themesState[target]
    val inherited = inheritedTheme(target)
    val canEdit = canEditTheme(target)
    return ThemeRecord(
      ownerName = ownerName(target),
      stored = stored,
      effective = stored ?: inherited.values,
      effectiveSource = if (stored != null) source(target) else inherited.source,
      canEdit = canEdit,
      canReset = canEdit && stored != null,
    )
  }

  override suspend fun updateTheme(target: ThemeTarget, values: ThemeValues) {
    prepareOperation()
    if (!canEditTheme(target)) throw DemoError.permissionDenied
    themesState[target] = values
    recordActivity(kind = ActivityKind.THEME, title = "Tema atualizado", detail = ownerName(target))
  }

  override suspend fun resetTheme(target: ThemeTarget) {
    prepareOperation()
    if (!canEditTheme(target)) throw DemoError.permissionDenied
    themesState.remove(target)
    recordActivity(kind = ActivityKind.THEME, title = "Tema restaurado", detail = ownerName(target))
  }

  private suspend fun prepareOperation() {
    if (operationDelayEnabled) {
      delay(OPERATION_DELAY_MILLIS)
    }
    if (shouldFailNextOperation) {
      shouldFailNextOperation = false
      throw DemoError.operationFailed
    }
  }

  private fun requireWriteAccess() {
    if (viewerModeEnabled) throw DemoError.permissionDenied
  }

  private fun requireOrganizationCapability(
    id: OrganizationID,
    capability: (OrganizationCapabilities) -> Boolean,
  ) {
    val organization = organizationsState.firstOrNull { it.id == id }
      ?: throw DemoError.resourceNotFound
    val capabilities = OrganizationCapabilities.forRole(organization.currentUserRole)
    if (!capability(capabilities)) throw DemoError.permissionDenied
  }

  private fun canEditTheme(target: ThemeTarget): Boolean {
    if (viewerModeEnabled) return false
    return when (target) {
      is ThemeTarget.User -> true
      is ThemeTarget.Organization -> {
        val organization = organizationsState.firstOrNull { it.id == target.id }
          ?: return false
        OrganizationCapabilities.forRole(organization.currentUserRole).canManage
      }
      is ThemeTarget.Billing ->
        billingsState.firstOrNull { it.id == target.id }?.capabilities?.canManageTheme == true
    }
  }

  private fun restrictIfNeeded(billing: Billing): Billing =
    if (viewerModeEnabled) billing.copy(capabilities = BillingCapabilities.viewer) else billing

  private fun restrictIfNeeded(organization: Organization): Organization =
    if (viewerModeEnabled) {
      organization.copy(
        currentUserRole = OrganizationRole.VIEWER,
        capabilities = OrganizationCapabilities.viewer,
      )
    } else {
      organization.copy(
        capabilities = OrganizationCapabilities.forRole(organization.currentUserRole),
      )
    }

  private fun restrictIfNeeded(bill: Bill): Bill = if (viewerModeEnabled) {
    bill.copy(
      capabilities = bill.capabilities.copy(
        canEdit = false,
        canDelete = false,
        canTransition = false,
        canRegenerate = false,
        canUploadReceipts = false,
        canDeleteReceipts = false,
        canReorderReceipts = false,
        canCompose = false,
        canSendInvoice = false,
        canSendRecibo = false,
      ),
      communications = bill.communications.map {
        it.copy(recipientName = null, recipientEmail = null, subject = null)
      },
    )
  } else {
    bill
  }

  private fun total(bills: List<Bill>): Money =
    bills.fold(Money.zero) { running, bill -> running + bill.total }

  private fun billIndex(billingID: BillingID, billID: BillID): Int? =
    billsState.indexOfFirst { it.billingID == billingID && it.id == billID }
      .takeIf { it >= 0 }

  private fun organizationIndex(id: OrganizationID): Int? =
    organizationsState.indexOfFirst { it.id == id }.takeIf { it >= 0 }

  private fun saveCommunicationTemplate(
    scope: CommunicationSaveScope,
    billing: Billing,
    commType: CommunicationType,
    subject: String,
    body: String,
  ) {
    val template = CommunicationTemplate(commType = commType, subject = subject, body = body)
    when (scope) {
      CommunicationSaveScope.BILLING -> {
        billingTemplateOverrides.getOrPut(billing.id, ::mutableSetOf).add(commType)
        billingsState.replaceAll { candidate ->
          if (candidate.id == billing.id) candidate.withCommunicationTemplate(template) else candidate
        }
      }
      CommunicationSaveScope.OWNER -> {
        val ownerKey = CommunicationOwnerKey(billing.owner)
        ownerCommunicationTemplates.getOrPut(ownerKey, ::mutableMapOf)[commType] = template
        billingsState.replaceAll { candidate ->
          if (
            CommunicationOwnerKey(candidate.owner) == ownerKey &&
            billingTemplateOverrides[candidate.id]?.contains(commType) != true
          ) candidate.withCommunicationTemplate(template) else candidate
        }
      }
    }
  }

  private data class CommunicationOwnerKey(val type: String, val id: String) {
    constructor(owner: BillingOwner) : this(
      type = if (owner is BillingOwner.User) "user" else "organization",
      id = when (owner) {
        is BillingOwner.User -> owner.id.toString()
        is BillingOwner.Organization -> owner.id.rawValue
      },
    )
  }

  private fun Billing.withCommunicationTemplate(template: CommunicationTemplate): Billing {
    val templates = communicationTemplates.toMutableList()
    val index = templates.indexOfFirst { it.commType == template.commType }
    if (index >= 0) templates[index] = template else templates.add(template)
    return copy(communicationTemplates = templates)
  }

  private fun recordActivity(kind: ActivityKind, title: String, detail: String) {
    activitiesState.add(
      0,
      RecentActivity(
        id = UUID.randomUUID(),
        kind = kind,
        title = title,
        detail = detail,
        occurredAt = Instant.now(),
      ),
    )
  }

  private suspend fun respondToInvitation(id: InvitationID, status: InvitationStatus) {
    prepareOperation()
    requireWriteAccess()
    val invitationIndex = invitationsState.indexOfFirst {
      it.id == id && it.status == InvitationStatus.PENDING
    }
    if (invitationIndex < 0) throw DemoError.resourceNotFound
    invitationsState[invitationIndex] = invitationsState[invitationIndex].copy(status = status)
    val invitation = invitationsState[invitationIndex]
    val organizationIndex = organizationsState.indexOfFirst { it.id == invitation.organizationID }
    if (status == InvitationStatus.ACCEPTED && organizationIndex >= 0) {
      val membership = OrganizationMember(
        userID = profileState.id,
        email = profileState.email,
        role = invitation.role,
        isCurrentUser = true,
      )
      organizationsState[organizationIndex] = organizationsState[organizationIndex].copy(
        members = organizationsState[organizationIndex].members + membership,
        currentUserRole = invitation.role,
        capabilities = OrganizationCapabilities.forRole(invitation.role),
      )
      val organizationEnforced = organizationsState.any { organization ->
        organization.requiresMFA && organization.members.any { it.userID == profileState.id }
      }
      securityState = securityState.copy(
        organizationEnforced = organizationEnforced,
        setupRequired = organizationEnforced &&
          !securityState.totpEnabled && securityState.passkeys.isEmpty(),
      )
    }
    recordActivity(
      kind = ActivityKind.INVITATION,
      title = if (status == InvitationStatus.ACCEPTED) "Convite aceito" else "Convite recusado",
      detail = invitation.organizationName,
    )
  }

  private data class InheritedTheme(val values: ThemeValues, val source: ThemeSource)

  private fun inheritedTheme(target: ThemeTarget): InheritedTheme = when (target) {
    is ThemeTarget.User -> InheritedTheme(ThemeValues.rentivo, ThemeSource.DEFAULT)
    is ThemeTarget.Organization ->
      themesState[ThemeTarget.User]?.let { InheritedTheme(it, ThemeSource.USER) }
        ?: InheritedTheme(ThemeValues.rentivo, ThemeSource.DEFAULT)
    is ThemeTarget.Billing -> {
      val owner = billingsState.firstOrNull { it.id == target.id }?.owner
      val organizationValues = (owner as? BillingOwner.Organization)?.let {
        themesState[ThemeTarget.Organization(it.id)]
      }
      when {
        organizationValues != null -> InheritedTheme(organizationValues, ThemeSource.ORGANIZATION)
        else -> themesState[ThemeTarget.User]?.let { InheritedTheme(it, ThemeSource.USER) }
          ?: InheritedTheme(ThemeValues.rentivo, ThemeSource.DEFAULT)
      }
    }
  }

  private fun source(target: ThemeTarget): ThemeSource = when (target) {
    is ThemeTarget.User -> ThemeSource.USER
    is ThemeTarget.Organization -> ThemeSource.ORGANIZATION
    is ThemeTarget.Billing -> ThemeSource.BILLING
  }

  private fun ownerName(target: ThemeTarget): String = when (target) {
    is ThemeTarget.User -> profileState.email
    is ThemeTarget.Organization ->
      organizationsState.firstOrNull { it.id == target.id }?.name ?: "Organização"
    is ThemeTarget.Billing ->
      billingsState.firstOrNull { it.id == target.id }?.name ?: "Cobrança"
  }

  /** Case- and accent-insensitive folding, the Kotlin analogue of Swift's `String.folding`. */
  private fun fold(text: String): String =
    Normalizer.normalize(text.lowercase(Locale.ROOT), Normalizer.Form.NFD)
      .replace(COMBINING_MARKS, "")

  private companion object {
    const val OPERATION_DELAY_MILLIS = 350L
    const val PENDING_RENDER_TICK_COUNT = 2
    val COMBINING_MARKS = Regex("\\p{Mn}+")
  }
}

private fun <Element> MutableList<Element>.replaceAllWith(elements: List<Element>) {
  clear()
  addAll(elements)
}

/** Wires one demo store into every repository slot the app resolves through. */
fun mockDependencies(store: MockRentivoStore = MockRentivoStore()): AppDependencies =
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
    demo = store,
  )

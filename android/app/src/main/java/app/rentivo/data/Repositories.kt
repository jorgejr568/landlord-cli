package app.rentivo.data

import app.rentivo.domain.APIKeyDraft
import app.rentivo.domain.APIKeyID
import app.rentivo.domain.APIKeyMetadata
import app.rentivo.domain.Attachment
import app.rentivo.domain.AttachmentID
import app.rentivo.domain.Bill
import app.rentivo.domain.BillDraft
import app.rentivo.domain.BillID
import app.rentivo.domain.BillStatus
import app.rentivo.domain.Billing
import app.rentivo.domain.BillingDraft
import app.rentivo.domain.BillingID
import app.rentivo.domain.CommunicationPreview
import app.rentivo.domain.CommunicationRecord
import app.rentivo.domain.CommunicationSaveScope
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
import app.rentivo.domain.Money
import app.rentivo.domain.Organization
import app.rentivo.domain.OrganizationDraft
import app.rentivo.domain.OrganizationID
import app.rentivo.domain.OrganizationRole
import app.rentivo.domain.PasskeyID
import app.rentivo.domain.PixConfiguration
import app.rentivo.domain.Receipt
import app.rentivo.domain.ReceiptID
import app.rentivo.domain.RecentActivity
import app.rentivo.domain.RecipientID
import app.rentivo.domain.SecuritySummary
import app.rentivo.domain.TOTPEnrollment
import app.rentivo.domain.ThemeRecord
import app.rentivo.domain.ThemeTarget
import app.rentivo.domain.ThemeValues
import app.rentivo.domain.UserProfile

interface AuthRepository {
  val currentUser: UserProfile

  /**
   * Whether this store is backed by the real Rentivo API rather than the in-memory demo data.
   * Screens use it to pick their copy ("conectado ao Rentivo" versus "demonstração"), and
   * `AppModel` uses it for the flows that only exist against a server: browser-based
   * authorization, token revocation, and account deletion.
   */
  val usesLiveAPI: Boolean

  /**
   * Returns the profile behind an already-stored credential, or `null` when there is no session
   * to resume.
   */
  suspend fun restoreSession(): UserProfile?

  /** Trades a one-time authorization code minted by the web sign-in flow for an API session. */
  suspend fun exchangeMobileAuthorization(code: String): UserProfile

  /**
   * Best-effort revocation of the current session; never throws, so callers can always drop local
   * state afterwards.
   */
  suspend fun logout()

  suspend fun deleteAccount(password: String)
}

interface ProfileRepository {
  suspend fun profile(): UserProfile

  suspend fun updatePix(pix: PixConfiguration): UserProfile
}

interface BillingRepository {
  suspend fun listBillings(): List<Billing>

  suspend fun billing(id: BillingID): Billing

  suspend fun createBilling(draft: BillingDraft): Billing

  suspend fun updateBilling(id: BillingID, draft: BillingDraft): Billing

  suspend fun deleteBilling(id: BillingID)
}

interface BillRepository {
  suspend fun listBills(billingID: BillingID): List<Bill>

  suspend fun bill(billingID: BillingID, id: BillID): Bill

  suspend fun createBill(draft: BillDraft): Bill

  suspend fun updateBill(billingID: BillingID, billID: BillID, draft: BillDraft): Bill

  suspend fun deleteBill(billingID: BillingID, billID: BillID)

  suspend fun transitionBill(billingID: BillingID, billID: BillID, status: BillStatus)

  suspend fun regenerateBill(billingID: BillingID, billID: BillID): Bill

  suspend fun addReceipt(billingID: BillingID, billID: BillID, upload: FileUpload): Receipt

  suspend fun reorderReceipts(billingID: BillingID, billID: BillID, receiptIDs: List<ReceiptID>)

  suspend fun deleteReceipt(billingID: BillingID, billID: BillID, receiptID: ReceiptID)
}

interface ExpenseRepository {
  suspend fun listExpenses(billingID: BillingID): List<Expense>

  suspend fun createExpense(
    billingID: BillingID,
    description: String,
    category: ExpenseCategory,
    incurredOn: DateOnly,
    amount: Money,
  ): Expense

  suspend fun deleteExpense(billingID: BillingID, expenseID: ExpenseID)
}

interface AttachmentRepository {
  suspend fun listAttachments(billingID: BillingID): List<Attachment>

  suspend fun addAttachment(billingID: BillingID, upload: FileUpload): Attachment

  suspend fun deleteAttachment(billingID: BillingID, attachmentID: AttachmentID)
}

interface CommunicationRepository {
  suspend fun previewCommunication(
    billingID: BillingID,
    subject: String,
    message: String,
  ): CommunicationPreview

  /** Returns the `queued_count` reported by the server. */
  suspend fun sendCommunication(
    billingID: BillingID,
    billID: BillID,
    commType: CommunicationType,
    recipientIDs: List<RecipientID>,
    subject: String,
    message: String,
    acknowledgeWarning: Boolean,
    saveScope: CommunicationSaveScope?,
  ): Int
}

interface FileDownloadRepository {
  suspend fun downloadInvoice(billingID: BillingID, billID: BillID): DownloadedFile

  suspend fun downloadRecibo(billingID: BillingID, billID: BillID): DownloadedFile

  suspend fun downloadReceipt(
    billingID: BillingID,
    billID: BillID,
    receiptID: ReceiptID,
  ): DownloadedFile

  suspend fun downloadAttachment(
    billingID: BillingID,
    attachmentID: AttachmentID,
  ): DownloadedFile
}

interface ExportRepository {
  suspend fun requestExport(billingID: BillingID, format: String)
}

interface DashboardRepository {
  suspend fun dashboardSummary(): DashboardSummary
}

interface ActivityRepository {
  val recentActivities: List<RecentActivity>
}

interface OrganizationRepository {
  suspend fun listOrganizations(): List<Organization>

  suspend fun organization(id: OrganizationID): Organization

  suspend fun createOrganization(draft: OrganizationDraft): Organization

  suspend fun updateOrganization(id: OrganizationID, draft: OrganizationDraft): Organization

  suspend fun deleteOrganization(id: OrganizationID)

  suspend fun updateMemberRole(
    organizationID: OrganizationID,
    userID: Int,
    role: OrganizationRole,
  )

  suspend fun removeMember(organizationID: OrganizationID, userID: Int)

  suspend fun inviteMember(
    organizationID: OrganizationID,
    email: String,
    role: OrganizationRole,
  ): Invitation

  suspend fun setOrganizationMFA(organizationID: OrganizationID, required: Boolean)

  suspend fun transferBilling(billingID: BillingID, toOrganizationID: OrganizationID)
}

interface InvitationRepository {
  suspend fun listPendingInvitations(): List<Invitation>

  suspend fun acceptInvitation(id: InvitationID)

  suspend fun declineInvitation(id: InvitationID)
}

interface SecurityRepository {
  suspend fun changePassword(
    currentPassword: String,
    newPassword: String,
    confirmPassword: String,
  )

  suspend fun securitySummary(): SecuritySummary

  suspend fun beginTOTPEnrollment(): TOTPEnrollment

  suspend fun confirmTOTPEnrollment(code: String): List<String>

  suspend fun disableTOTP(password: String)

  suspend fun regenerateRecoveryCodes(): List<String>

  suspend fun deletePasskey(id: PasskeyID)
}

interface APIKeyRepository {
  suspend fun listAPIKeys(): List<APIKeyMetadata>

  suspend fun createAPIKey(draft: APIKeyDraft): CreatedAPIKeySecret

  suspend fun updateAPIKey(id: APIKeyID, draft: APIKeyDraft): APIKeyMetadata

  suspend fun revokeAPIKey(id: APIKeyID)
}

interface ThemeRepository {
  suspend fun theme(target: ThemeTarget): ThemeRecord

  suspend fun updateTheme(target: ThemeTarget, values: ThemeValues)

  suspend fun resetTheme(target: ThemeTarget)
}

data class DemoSettings(
  val delayEnabled: Boolean,
  val emptyMode: Boolean,
  val viewerMode: Boolean,
) {
  companion object {
    val standard = DemoSettings(delayEnabled = false, emptyMode = false, viewerMode = false)
  }
}

interface DemoRepository {
  val demoSettings: DemoSettings

  fun failNextOperation()

  fun setEmptyMode(enabled: Boolean)

  fun setViewerMode(enabled: Boolean)

  fun setDelayEnabled(enabled: Boolean)

  fun reset()
}

/** The 17 repositories every screen resolves its data through. */
data class AppDependencies(
  val auth: AuthRepository,
  val profile: ProfileRepository,
  val billings: BillingRepository,
  val bills: BillRepository,
  val expenses: ExpenseRepository,
  val attachments: AttachmentRepository,
  val communications: CommunicationRepository,
  val downloads: FileDownloadRepository,
  val exports: ExportRepository,
  val dashboard: DashboardRepository,
  val activities: ActivityRepository,
  val organizations: OrganizationRepository,
  val invitations: InvitationRepository,
  val security: SecurityRepository,
  val apiKeys: APIKeyRepository,
  val themes: ThemeRepository,
  val demo: DemoRepository,
)

data class DashboardSummary(
  val received: Money,
  val expenses: Money,
  val netIncome: Money,
  val overdue: Money,
  val upcoming: Money,
  val collectionRatePercent: Int,
)

data class StoreSnapshot(
  val profile: UserProfile,
  val billings: List<Billing>,
  val bills: List<Bill>,
  val expenses: List<Expense>,
  val attachments: Map<BillingID, List<Attachment>>,
  val organizations: List<Organization>,
  val invitations: List<Invitation>,
  val communications: List<CommunicationRecord>,
  val security: SecuritySummary,
  val apiKeys: List<APIKeyMetadata>,
  val themes: Map<ThemeTarget, ThemeValues>,
  val activities: List<RecentActivity>,
)

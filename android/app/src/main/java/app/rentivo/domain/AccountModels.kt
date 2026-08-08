package app.rentivo.domain

import java.time.Instant

/**
 * Mirrors the server's role contract exactly (`admin`, `manager`, `viewer`). There is no "owner"
 * role on the wire: `OrganizationMemberUpdateRequest.role` and every invite/member response enum
 * accept only these three values, so no case here may be excluded from mutation paths or role
 * pickers.
 */
enum class OrganizationRole(val wire: String) {
  ADMIN("admin"),
  MANAGER("manager"),
  VIEWER("viewer"),
  ;

  val label: String
    get() = when (this) {
      ADMIN -> "Administrador"
      MANAGER -> "Gerente"
      VIEWER -> "Visualizador"
    }

  companion object {
    fun fromWire(wire: String?): OrganizationRole? = entries.firstOrNull { it.wire == wire }
  }
}

data class OrganizationCapabilities(
  val canManage: Boolean,
  val canInvite: Boolean,
  val canCreateBilling: Boolean,
  val canViewBillingStats: Boolean,
) {
  companion object {
    val full = OrganizationCapabilities(
      canManage = true, canInvite = true, canCreateBilling = true, canViewBillingStats = true,
    )

    val manager = OrganizationCapabilities(
      canManage = false, canInvite = true, canCreateBilling = true, canViewBillingStats = true,
    )

    val viewer = OrganizationCapabilities(
      canManage = false, canInvite = false, canCreateBilling = false, canViewBillingStats = true,
    )

    fun forRole(role: OrganizationRole): OrganizationCapabilities = when (role) {
      OrganizationRole.ADMIN -> full
      OrganizationRole.MANAGER -> manager
      OrganizationRole.VIEWER -> viewer
    }
  }
}

data class OrganizationMember(
  val userID: Int,
  val email: String,
  val role: OrganizationRole,
) {
  val id: Int get() = userID
}

data class Organization(
  val id: OrganizationID,
  val name: String,
  val pix: PixConfiguration?,
  val members: List<OrganizationMember>,
  val requiresMFA: Boolean,
  val currentUserRole: OrganizationRole,
  val capabilities: OrganizationCapabilities = OrganizationCapabilities.full,
)

data class OrganizationDraft(
  val name: String,
  val pix: PixConfiguration?,
) {
  val isValid: Boolean get() = name.trim().isNotEmpty()
}

enum class InvitationStatus(val wire: String) {
  PENDING("pending"),
  ACCEPTED("accepted"),
  DECLINED("declined"),
  ;

  companion object {
    fun fromWire(wire: String?): InvitationStatus? = entries.firstOrNull { it.wire == wire }
  }
}

data class Invitation(
  val id: InvitationID,
  val organizationID: OrganizationID,
  val organizationName: String,
  val email: String,
  val role: OrganizationRole,
  val status: InvitationStatus,
)

data class Passkey(
  val id: PasskeyID,
  val name: String,
  val createdAt: Instant,
  val lastUsedAt: Instant?,
)

data class SecuritySummary(
  val totpEnabled: Boolean,
  val recoveryCodeCount: Int,
  val passkeys: List<Passkey>,
)

data class TOTPEnrollment(
  val secret: String,
  val provisioningURI: String,
  val qrCodeBase64: String,
)

enum class APIKeyScope(val wire: String) {
  PROFILE_READ("profile:read"),
  ACCOUNT_WRITE("account:write"),
  SECURITY_MANAGE("security:manage"),
  API_KEYS_MANAGE("api_keys:manage"),
  ORGANIZATIONS_READ("organizations:read"),
  ORGANIZATIONS_WRITE("organizations:write"),
  ORGANIZATIONS_MEMBERS("organizations:members"),
  BILLINGS_READ("billings:read"),
  BILLINGS_WRITE("billings:write"),
  BILLS_READ("bills:read"),
  BILLS_WRITE("bills:write"),
  EXPENSES_READ("expenses:read"),
  EXPENSES_WRITE("expenses:write"),
  FILES_READ("files:read"),
  FILES_WRITE("files:write"),
  COMMUNICATIONS_READ("communications:read"),
  COMMUNICATIONS_SEND("communications:send"),
  THEMES_READ("themes:read"),
  THEMES_WRITE("themes:write"),
  EXPORTS_CREATE("exports:create"),
  ;

  companion object {
    /** The scopes an integration key may request — privileged account operations are excluded. */
    val integrationCases: List<APIKeyScope> = listOf(
      PROFILE_READ, ORGANIZATIONS_READ, BILLINGS_READ, BILLINGS_WRITE, BILLS_READ,
      BILLS_WRITE, EXPENSES_READ, EXPENSES_WRITE, FILES_READ, FILES_WRITE,
      COMMUNICATIONS_READ, COMMUNICATIONS_SEND, THEMES_READ, THEMES_WRITE, EXPORTS_CREATE,
    )

    fun fromWire(wire: String?): APIKeyScope? = entries.firstOrNull { it.wire == wire }
  }
}

enum class WorkspaceResourceType(val wire: String) {
  USER("user"),
  ORGANIZATION("organization"),
  ;

  companion object {
    fun fromWire(wire: String?): WorkspaceResourceType? = entries.firstOrNull { it.wire == wire }
  }
}

data class APIKeyGrant(
  val resourceType: WorkspaceResourceType,
  val resourceID: WorkspaceID,
  val available: Boolean = true,
)

data class APIKeyMetadata(
  val id: APIKeyID,
  val name: String,
  val hint: String,
  val scopes: Set<APIKeyScope>,
  val grants: List<APIKeyGrant>,
  val expiresAt: Instant,
  val lastUsedAt: Instant?,
  val createdAt: Instant,
  val revokedAt: Instant?,
)

data class APIKeyDraft(
  val name: String,
  val scopes: Set<APIKeyScope>,
  val grants: List<APIKeyGrant>,
  val expiresAt: Instant,
) {
  companion object {
    val demo = APIKeyDraft(
      name = "Painel financeiro",
      scopes = setOf(APIKeyScope.PROFILE_READ, APIKeyScope.BILLINGS_READ),
      grants = listOf(
        APIKeyGrant(
          resourceType = WorkspaceResourceType.USER,
          resourceID = WorkspaceID.personal,
        )
      ),
      expiresAt = Instant.ofEpochSecond(1_798_761_600L),
    )
  }
}

data class CreatedAPIKeySecret(
  val metadata: APIKeyMetadata,
  val secret: String,
)

enum class ThemeFont(val wire: String) {
  MONTSERRAT("Montserrat"),
  ROBOTO("Roboto"),
  LORA("Lora"),
  PLAYFAIR_DISPLAY("Playfair Display"),
  OPEN_SANS("Open Sans"),
  SOURCE_SANS_3("Source Sans 3"),
  MERRIWEATHER("Merriweather"),
  RALEWAY("Raleway"),
  OSWALD("Oswald"),
  NUNITO("Nunito"),
  ;

  companion object {
    fun fromWire(wire: String?): ThemeFont? = entries.firstOrNull { it.wire == wire }
  }
}

data class ThemeValues(
  val headerFont: ThemeFont,
  val textFont: ThemeFont,
  val primary: String,
  val primaryLight: String,
  val secondary: String,
  val secondaryDark: String,
  val textColor: String,
  val textContrast: String,
) {
  companion object {
    val rentivo = ThemeValues(
      headerFont = ThemeFont.MONTSERRAT, textFont = ThemeFont.OPEN_SANS,
      primary = "#07875F", primaryLight = "#DDF6EC",
      secondary = "#252635", secondaryDark = "#171822",
      textColor = "#252635", textContrast = "#FFFFFF",
    )

    val sunset = ThemeValues(
      headerFont = ThemeFont.PLAYFAIR_DISPLAY, textFont = ThemeFont.LORA,
      primary = "#C95A3D", primaryLight = "#FAE5DF",
      secondary = "#47324A", secondaryDark = "#2B1D2D",
      textColor = "#2B1D2D", textContrast = "#FFFFFF",
    )
  }
}

enum class ThemeSource(val wire: String) {
  BILLING("billing"),
  ORGANIZATION("organization"),
  USER("user"),
  DEFAULT("default"),
  ;

  companion object {
    fun fromWire(wire: String?): ThemeSource? = entries.firstOrNull { it.wire == wire }
  }
}

sealed class ThemeTarget {
  data object User : ThemeTarget()

  data class Organization(val id: OrganizationID) : ThemeTarget()

  data class Billing(val id: BillingID) : ThemeTarget()
}

data class ThemeRecord(
  val ownerName: String,
  val stored: ThemeValues?,
  val effective: ThemeValues,
  val effectiveSource: ThemeSource,
  val canEdit: Boolean,
  val canReset: Boolean,
)

import Foundation

public struct AccountDeletionReadiness: Hashable, Codable, Sendable {
  public enum BlockingReason: String, Hashable, Codable, Sendable {
    case soleOrganizationAdmin = "sole_organization_admin"
  }

  public let canDelete: Bool
  public let reason: BlockingReason?

  public init(canDelete: Bool, reason: BlockingReason? = nil) {
    self.canDelete = canDelete
    self.reason = reason
  }
}

/// Mirrors the server's role contract exactly (`admin`, `manager`, `viewer`).
/// There is no "owner" role on the wire: `OrganizationMemberUpdateRequest.role`
/// and every invite/member response enum accept only these three values, so no
/// case here may be excluded from mutation paths or role pickers.
public enum OrganizationRole: String, CaseIterable, Codable, Sendable {
  case admin
  case manager
  case viewer

  public var label: String {
    switch self {
    case .admin: "Administrador"
    case .manager: "Gerente"
    case .viewer: "Visualizador"
    }
  }
}

public struct OrganizationCapabilities: Hashable, Codable, Sendable {
  public var canManage: Bool
  public var canInvite: Bool
  public var canCreateBilling: Bool
  public var canViewBillingStats: Bool

  public init(canManage: Bool, canInvite: Bool, canCreateBilling: Bool, canViewBillingStats: Bool) {
    self.canManage = canManage
    self.canInvite = canInvite
    self.canCreateBilling = canCreateBilling
    self.canViewBillingStats = canViewBillingStats
  }

  public static let full = OrganizationCapabilities(
    canManage: true, canInvite: true, canCreateBilling: true, canViewBillingStats: true
  )

  public static let manager = OrganizationCapabilities(
    canManage: false, canInvite: false, canCreateBilling: true, canViewBillingStats: true
  )

  public static let viewer = OrganizationCapabilities(
    canManage: false, canInvite: false, canCreateBilling: false, canViewBillingStats: true
  )

  public static func forRole(_ role: OrganizationRole) -> OrganizationCapabilities {
    switch role {
    case .admin: .full
    case .manager: .manager
    case .viewer: .viewer
    }
  }
}

public struct OrganizationMember: Identifiable, Hashable, Codable, Sendable {
  public var id: Int { userID }
  public let userID: Int
  public var email: String
  public var role: OrganizationRole
  public var isCurrentUser: Bool

  public init(
    userID: Int, email: String, role: OrganizationRole, isCurrentUser: Bool = false
  ) {
    self.userID = userID
    self.email = email
    self.role = role
    self.isCurrentUser = isCurrentUser
  }
}

public struct Organization: Identifiable, Hashable, Codable, Sendable {
  public let id: OrganizationID
  public var name: String
  public var pix: PixConfiguration?
  public var members: [OrganizationMember]
  public var requiresMFA: Bool
  public var currentUserRole: OrganizationRole
  public var capabilities: OrganizationCapabilities

  public init(
    id: OrganizationID,
    name: String,
    pix: PixConfiguration?,
    members: [OrganizationMember],
    requiresMFA: Bool,
    currentUserRole: OrganizationRole,
    capabilities: OrganizationCapabilities = .full
  ) {
    self.id = id
    self.name = name
    self.pix = pix
    self.members = members
    self.requiresMFA = requiresMFA
    self.currentUserRole = currentUserRole
    self.capabilities = capabilities
  }

  /// A billing can be created in this workspace only when the server says the current principal
  /// has that capability. Roles alone are not authoritative for API-key principals.
  public var billingOwnerForCreation: BillingOwner? {
    guard capabilities.canCreateBilling else { return nil }
    return .organization(id: id, name: name)
  }
}

/// The effective result returned after changing an organization's MFA policy.
/// `mfaSetupRequired` is user-specific: the server sets it when enforcing MFA
/// leaves the current administrator without any enrolled MFA method.
public struct OrganizationMFAPolicy: Hashable, Codable, Sendable {
  public let enforceMFA: Bool
  public let mfaSetupRequired: Bool

  public init(enforceMFA: Bool, mfaSetupRequired: Bool) {
    self.enforceMFA = enforceMFA
    self.mfaSetupRequired = mfaSetupRequired
  }
}

public struct OrganizationDraft: Hashable, Sendable {
  public static let nameLimit = 255

  public var name: String
  public var pix: PixConfiguration?

  public init(name: String, pix: PixConfiguration?) {
    self.name = name
    self.pix = pix
  }

  public var isValid: Bool {
    Self.nameValidationMessage(name) == nil
      && pix.map {
        Self.pixValidationMessage(
          key: $0.key, merchantName: $0.merchantName, city: $0.merchantCity
        ) == nil
      } ?? true
  }

  public static func nameValidationMessage(_ name: String) -> String? {
    let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.isEmpty { return "Informe o nome da organização." }
    if normalized.unicodeScalars.count > nameLimit {
      return "O nome da organização deve ter até 255 caracteres."
    }
    return nil
  }

  public static func pixValidationMessage(
    key: String, merchantName: String, city: String
  ) -> String? {
    let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedName = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalizedKey.isEmpty { return nil }
    if normalizedName.isEmpty || normalizedCity.isEmpty {
      return "Informe o nome e a cidade do recebedor para usar uma chave PIX."
    }
    if normalizedName.unicodeScalars.count > 25 {
      return "O nome do recebedor deve ter até 25 caracteres."
    }
    if normalizedCity.unicodeScalars.count > 15 {
      return "A cidade do recebedor deve ter até 15 caracteres."
    }
    return nil
  }
}

/// Validation for the deliberately permissive organization-invite address accepted by
/// `OrganizationInviteCreateRequest`. This is not the stricter billing-contact contract:
/// the API accepts addresses such as `a@b` here as long as both sides are present.
public enum OrganizationInviteEmail {
  public static let maximumLength = 320

  public static func normalized(_ email: String) -> String {
    email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  public static func validationMessage(_ email: String) -> String? {
    let value = normalized(email)
    if value.isEmpty { return "Informe o e-mail." }
    if value.unicodeScalars.count > maximumLength {
      return "O e-mail deve ter até 320 caracteres."
    }
    guard value.filter({ $0 == "@" }).count == 1,
      !value.contains(where: \.isWhitespace)
    else { return "Informe um e-mail válido." }

    let parts = value.split(separator: "@", omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
      return "Informe um e-mail válido."
    }
    return nil
  }

  public static func isValid(_ email: String) -> Bool {
    validationMessage(email) == nil
  }
}

public enum InvitationStatus: String, CaseIterable, Codable, Sendable {
  case pending
  case accepted
  case declined
}

public struct Invitation: Identifiable, Hashable, Codable, Sendable {
  public let id: InvitationID
  public let organizationID: OrganizationID
  public var organizationName: String
  public var email: String
  public var role: OrganizationRole
  public var status: InvitationStatus
  public var invitedByEmail: String?
  public var organizationEnforcesMFA: Bool

  public init(
    id: InvitationID,
    organizationID: OrganizationID,
    organizationName: String,
    email: String,
    role: OrganizationRole,
    status: InvitationStatus,
    invitedByEmail: String? = nil,
    organizationEnforcesMFA: Bool = false
  ) {
    self.id = id
    self.organizationID = organizationID
    self.organizationName = organizationName
    self.email = email
    self.role = role
    self.status = status
    self.invitedByEmail = invitedByEmail
    self.organizationEnforcesMFA = organizationEnforcesMFA
  }
}

public struct InvitationAcceptance: Hashable, Sendable {
  public let organizationID: OrganizationID
  public let mfaSetupRequired: Bool

  public init(organizationID: OrganizationID, mfaSetupRequired: Bool) {
    self.organizationID = organizationID
    self.mfaSetupRequired = mfaSetupRequired
  }
}

public struct Passkey: Identifiable, Hashable, Codable, Sendable {
  public let id: PasskeyID
  public var name: String
  public var createdAt: Date
  public var lastUsedAt: Date?

  public init(id: PasskeyID, name: String, createdAt: Date, lastUsedAt: Date?) {
    self.id = id
    self.name = name
    self.createdAt = createdAt
    self.lastUsedAt = lastUsedAt
  }
}

public struct SecuritySummary: Hashable, Codable, Sendable {
  public var totpEnabled: Bool
  public var recoveryCodeCount: Int
  public var passkeys: [Passkey]
  public var setupRequired: Bool
  public var organizationEnforced: Bool

  public init(
    totpEnabled: Bool,
    recoveryCodeCount: Int,
    passkeys: [Passkey],
    setupRequired: Bool = false,
    organizationEnforced: Bool = false
  ) {
    self.totpEnabled = totpEnabled
    self.recoveryCodeCount = recoveryCodeCount
    self.passkeys = passkeys
    self.setupRequired = setupRequired
    self.organizationEnforced = organizationEnforced
  }
}

public struct TOTPEnrollment: Hashable, Sendable {
  public let secret: String
  public let provisioningURI: String
  public let qrCodeBase64: String

  public init(secret: String, provisioningURI: String, qrCodeBase64: String) {
    self.secret = secret
    self.provisioningURI = provisioningURI
    self.qrCodeBase64 = qrCodeBase64
  }
}

public enum APIKeyScope: String, CaseIterable, Codable, Sendable {
  case profileRead = "profile:read"
  case accountWrite = "account:write"
  case securityManage = "security:manage"
  case apiKeysManage = "api_keys:manage"
  case organizationsRead = "organizations:read"
  case organizationsWrite = "organizations:write"
  case organizationsMembers = "organizations:members"
  case billingsRead = "billings:read"
  case billingsWrite = "billings:write"
  case billsRead = "bills:read"
  case billsWrite = "bills:write"
  case expensesRead = "expenses:read"
  case expensesWrite = "expenses:write"
  case filesRead = "files:read"
  case filesWrite = "files:write"
  case communicationsRead = "communications:read"
  case communicationsSend = "communications:send"
  case themesRead = "themes:read"
  case themesWrite = "themes:write"
  case exportsCreate = "exports:create"

  public static let integrationCases: [APIKeyScope] = [
    .profileRead, .organizationsRead, .billingsRead, .billingsWrite, .billsRead,
    .billsWrite, .expensesRead, .expensesWrite, .filesRead, .filesWrite,
    .communicationsRead, .communicationsSend, .themesRead, .themesWrite, .exportsCreate,
  ]
}

public enum WorkspaceResourceType: String, Codable, Sendable {
  case user
  case organization
}

public struct APIKeyWorkspaceOption: Identifiable, Hashable, Codable, Sendable {
  public var id: WorkspaceID { resourceID }
  public let resourceType: WorkspaceResourceType
  public let resourceID: WorkspaceID
  public let name: String

  public init(resourceType: WorkspaceResourceType, resourceID: WorkspaceID, name: String) {
    self.resourceType = resourceType
    self.resourceID = resourceID
    self.name = name
  }
}

public struct APIKeyOptions: Hashable, Codable, Sendable {
  public let scopes: [APIKeyScope]
  public let personalWorkspace: APIKeyWorkspaceOption
  public let organizations: [APIKeyWorkspaceOption]
  public let defaultExpirationDays: Int
  public let maxExpirationDays: Int

  public init(
    scopes: [APIKeyScope],
    personalWorkspace: APIKeyWorkspaceOption,
    organizations: [APIKeyWorkspaceOption],
    defaultExpirationDays: Int,
    maxExpirationDays: Int
  ) {
    self.scopes = scopes
    self.personalWorkspace = personalWorkspace
    self.organizations = organizations
    self.defaultExpirationDays = defaultExpirationDays
    self.maxExpirationDays = maxExpirationDays
  }

  public func defaultExpiration(from now: Date = Date()) -> Date {
    now.addingTimeInterval(TimeInterval(defaultExpirationDays) * 86_400)
  }

  /// Keep the same one-minute request-latency buffer as the web client so a value selected at the
  /// upper boundary remains valid when it reaches the server.
  public func maximumExpiration(from now: Date = Date()) -> Date {
    now.addingTimeInterval(TimeInterval(maxExpirationDays) * 86_400 - 60)
  }

  public func clampedExpiration(_ selected: Date, from now: Date = Date()) -> Date {
    min(max(selected, now.addingTimeInterval(60)), maximumExpiration(from: now))
  }
}

public enum APIKeyValidation {
  public static func isValidName(_ name: String) -> Bool {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && trimmed.unicodeScalars.count <= 255
  }
}

public struct APIKeyGrant: Hashable, Codable, Sendable {
  public var resourceType: WorkspaceResourceType
  public var resourceID: WorkspaceID
  public var available: Bool

  public init(resourceType: WorkspaceResourceType, resourceID: WorkspaceID, available: Bool = true) {
    self.resourceType = resourceType
    self.resourceID = resourceID
    self.available = available
  }
}

public struct APIKeyMetadata: Identifiable, Hashable, Codable, Sendable {
  public let id: APIKeyID
  public var name: String
  public var hint: String
  public var scopes: Set<APIKeyScope>
  public var grants: [APIKeyGrant]
  public var unsupportedScopeCount: Int
  public var unavailableGrantCount: Int
  public var expiresAt: Date
  public var lastUsedAt: Date?
  public var createdAt: Date
  public var revokedAt: Date?

  public init(
    id: APIKeyID,
    name: String,
    hint: String,
    scopes: Set<APIKeyScope>,
    grants: [APIKeyGrant],
    expiresAt: Date,
    lastUsedAt: Date?,
    createdAt: Date,
    revokedAt: Date?,
    unavailableGrantCount: Int = 0,
    unsupportedScopeCount: Int = 0
  ) {
    self.id = id
    self.name = name
    self.hint = hint
    self.scopes = scopes
    self.grants = grants
    self.unsupportedScopeCount = unsupportedScopeCount
    self.unavailableGrantCount = unavailableGrantCount
    self.expiresAt = expiresAt
    self.lastUsedAt = lastUsedAt
    self.createdAt = createdAt
    self.revokedAt = revokedAt
  }
}

public struct APIKeyDraft: Hashable, Sendable {
  public var name: String
  public var scopes: Set<APIKeyScope>
  public var grants: [APIKeyGrant]
  public var expiresAt: Date
  /// PATCH omits scopes when the server returned a scope this client version cannot represent.
  /// Sending only the recognized values would silently revoke forward-compatible permissions.
  public var shouldUpdateScopes: Bool
  /// PATCH omits grants when the edit form did not change the visible selection. This preserves
  /// server-redacted grants whose resource identifiers cannot be round-tripped by any client.
  public var shouldUpdateGrants: Bool

  public init(
    name: String, scopes: Set<APIKeyScope>, grants: [APIKeyGrant], expiresAt: Date,
    shouldUpdateGrants: Bool = true,
    shouldUpdateScopes: Bool = true
  ) {
    self.name = name
    self.scopes = scopes
    self.grants = grants
    self.expiresAt = expiresAt
    self.shouldUpdateGrants = shouldUpdateGrants
    self.shouldUpdateScopes = shouldUpdateScopes
  }

  public static let demo = APIKeyDraft(
    name: "Painel financeiro",
    scopes: [.profileRead, .billingsRead],
    grants: [APIKeyGrant(resourceType: .user, resourceID: .personal)],
    expiresAt: Date(timeIntervalSince1970: 1_798_761_600)
  )
}

public struct CreatedAPIKeySecret: Hashable, Sendable {
  public let metadata: APIKeyMetadata
  public let secret: String

  public init(metadata: APIKeyMetadata, secret: String) {
    self.metadata = metadata
    self.secret = secret
  }
}

public enum ThemeFont: String, CaseIterable, Codable, Sendable {
  case montserrat = "Montserrat"
  case roboto = "Roboto"
  case lora = "Lora"
  case playfairDisplay = "Playfair Display"
  case openSans = "Open Sans"
  case sourceSans3 = "Source Sans 3"
  case merriweather = "Merriweather"
  case raleway = "Raleway"
  case oswald = "Oswald"
  case nunito = "Nunito"
}

public struct ThemeValues: Hashable, Codable, Sendable {
  public var headerFont: ThemeFont
  public var textFont: ThemeFont
  public var primary: String
  public var primaryLight: String
  public var secondary: String
  public var secondaryDark: String
  public var textColor: String
  public var textContrast: String

  public init(
    headerFont: ThemeFont,
    textFont: ThemeFont,
    primary: String,
    primaryLight: String,
    secondary: String,
    secondaryDark: String,
    textColor: String,
    textContrast: String
  ) {
    self.headerFont = headerFont
    self.textFont = textFont
    self.primary = primary
    self.primaryLight = primaryLight
    self.secondary = secondary
    self.secondaryDark = secondaryDark
    self.textColor = textColor
    self.textContrast = textContrast
  }

  public static let rentivo = ThemeValues(
    headerFont: .montserrat, textFont: .openSans,
    primary: "#07875F", primaryLight: "#DDF6EC",
    secondary: "#252635", secondaryDark: "#171822",
    textColor: "#252635", textContrast: "#FFFFFF"
  )

  public static let sunset = ThemeValues(
    headerFont: .playfairDisplay, textFont: .lora,
    primary: "#C95A3D", primaryLight: "#FAE5DF",
    secondary: "#47324A", secondaryDark: "#2B1D2D",
    textColor: "#2B1D2D", textContrast: "#FFFFFF"
  )
}

public enum ThemeSource: String, CaseIterable, Codable, Sendable {
  case billing
  case organization
  case user
  case `default`
}

public enum ThemeTarget: Hashable, Sendable {
  case user
  case organization(OrganizationID)
  case billing(BillingID)
}

public struct ThemeRecord: Hashable, Sendable {
  public var ownerName: String
  public var stored: ThemeValues?
  public var effective: ThemeValues
  public var effectiveSource: ThemeSource
  public var canEdit: Bool
  public var canReset: Bool

  public init(
    ownerName: String,
    stored: ThemeValues?,
    effective: ThemeValues,
    effectiveSource: ThemeSource,
    canEdit: Bool,
    canReset: Bool
  ) {
    self.ownerName = ownerName
    self.stored = stored
    self.effective = effective
    self.effectiveSource = effectiveSource
    self.canEdit = canEdit
    self.canReset = canReset
  }
}

import Foundation
import Security

public protocol CredentialStore: Sendable {
  func readAccessToken() async throws -> String?
  func saveAccessToken(_ token: String) async throws
  func deleteAccessToken() async throws
}

public enum CredentialStoreError: Error, LocalizedError, Sendable {
  case keychain(status: Int32)

  public var errorDescription: String? {
    "Não foi possível acessar a sessão segura neste dispositivo."
  }
}

public actor MemoryCredentialStore: CredentialStore {
  private var token: String?

  public init(token: String? = nil) {
    self.token = token
  }

  public func readAccessToken() -> String? { token }
  public func saveAccessToken(_ token: String) { self.token = token }
  public func deleteAccessToken() { token = nil }
}

/// Which keychain implementation the `SecItem` calls address.
///
/// iOS only has the data-protection keychain, so the flag is implicit there.
/// On macOS a plain `SecItem` call lands in the legacy file-based keychain and
/// the data-protection keychain has to be requested with
/// `kSecUseDataProtectionKeychain`; the system rejects that request with
/// `errSecMissingEntitlement` when the process has no provisioned
/// application-identifier (ad-hoc signed local builds, test runners), which is
/// what the legacy fallback exists for.
enum KeychainBackend: Sendable {
  /// iOS: the data-protection keychain is the only keychain.
  case implicitDataProtection
  /// macOS: the data-protection keychain, requested explicitly.
  case explicitDataProtection
  /// macOS: the legacy file-based keychain, used when the entitlement is missing.
  case legacyFile

  /// The backend every store starts with on this platform.
  static var platformDefault: KeychainBackend {
    #if os(macOS)
      .explicitDataProtection
    #else
      .implicitDataProtection
    #endif
  }

  /// Whether queries must carry `kSecUseDataProtectionKeychain`.
  var declaresDataProtection: Bool { self == .explicitDataProtection }

  /// The legacy macOS keychain predates the data-protection accessibility
  /// classes and rejects items carrying one.
  var supportsAccessibilityClass: Bool { self != .legacyFile }

  /// The backend to retry the failed operation with, or `nil` when the status
  /// is not the missing-entitlement rejection this fallback handles.
  func fallback(after status: OSStatus) -> KeychainBackend? {
    self == .explicitDataProtection && status == errSecMissingEntitlement ? .legacyFile : nil
  }
}

public actor KeychainCredentialStore: CredentialStore {
  private let service: String
  private let account = "rentivo.access-token"
  private var backend = KeychainBackend.platformDefault

  public init(service: String = Bundle.main.bundleIdentifier ?? "app.rentivo.demo") {
    self.service = service
  }

  public func readAccessToken() throws -> String? {
    let (status, data) = perform { backend in
      var lookup = query(for: backend)
      lookup[kSecReturnData as String] = true
      lookup[kSecMatchLimit as String] = kSecMatchLimitOne

      var item: CFTypeRef?
      let status = SecItemCopyMatching(lookup as CFDictionary, &item)
      return (status, item as? Data)
    }
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data,
      let token = String(data: data, encoding: .utf8)
    else { throw CredentialStoreError.keychain(status: status) }
    return token
  }

  public func saveAccessToken(_ token: String) throws {
    let status = performStatus { backend in
      let attributes = Self.valueAttributes(token: token, backend: backend)
      let updateStatus = SecItemUpdate(
        query(for: backend) as CFDictionary, attributes as CFDictionary)
      guard updateStatus == errSecItemNotFound else { return updateStatus }

      let add = query(for: backend).merging(attributes) { _, attribute in attribute }
      return SecItemAdd(add as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw CredentialStoreError.keychain(status: status) }
  }

  public func deleteAccessToken() throws {
    let status = performStatus { SecItemDelete(query(for: $0) as CFDictionary) }
    guard status == errSecSuccess || status == errSecItemNotFound
    else { throw CredentialStoreError.keychain(status: status) }
  }

  /// Runs `body` against the current backend and, when the data-protection
  /// keychain rejects it for a missing entitlement, once more against the
  /// legacy keychain. The fallback is remembered so later operations do not
  /// repeat the failing attempt.
  private func perform<Value>(
    _ body: (KeychainBackend) -> (OSStatus, Value)
  ) -> (OSStatus, Value) {
    let attempt = body(backend)
    guard let fallback = backend.fallback(after: attempt.0) else { return attempt }
    backend = fallback
    return body(fallback)
  }

  private func performStatus(_ body: (KeychainBackend) -> OSStatus) -> OSStatus {
    perform { (body($0), ()) }.0
  }

  private func query(for backend: KeychainBackend) -> [String: Any] {
    Self.itemQuery(service: service, account: account, backend: backend)
  }

  /// The attributes identifying this store's single keychain item.
  static func itemQuery(
    service: String, account: String, backend: KeychainBackend
  ) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    if backend.declaresDataProtection {
      query[kSecUseDataProtectionKeychain as String] = true
    }
    return query
  }

  /// The attributes written by every save. The accessibility class is
  /// re-asserted on every update: an item created before this attribute was
  /// enforced (or by a future laxer write) would otherwise keep whatever class
  /// it was originally saved with.
  static func valueAttributes(token: String, backend: KeychainBackend) -> [String: Any] {
    var attributes: [String: Any] = [kSecValueData as String: Data(token.utf8)]
    if backend.supportsAccessibilityClass {
      attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    }
    return attributes
  }
}

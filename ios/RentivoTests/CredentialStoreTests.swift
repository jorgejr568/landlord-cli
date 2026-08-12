import Foundation
import Security
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

@Test func memoryCredentialStoreRoundTripsAndDeletesToken() async {
  let credentials = MemoryCredentialStore()

  #expect(await credentials.readAccessToken() == nil)

  await credentials.saveAccessToken("session-token")
  #expect(await credentials.readAccessToken() == "session-token")

  await credentials.deleteAccessToken()
  #expect(await credentials.readAccessToken() == nil)
}

@Test func keychainQueryIdentifiesTheItemAndOptsIntoDataProtection() {
  func query(_ backend: KeychainBackend) -> [String: Any] {
    KeychainCredentialStore.itemQuery(
      service: "app.rentivo.tests", account: "rentivo.access-token", backend: backend)
  }

  for backend in [
    KeychainBackend.implicitDataProtection, .explicitDataProtection, .legacyFile,
  ] {
    let attributes = query(backend)
    #expect((attributes[kSecClass as String] as? String) == (kSecClassGenericPassword as String))
    #expect((attributes[kSecAttrService as String] as? String) == "app.rentivo.tests")
    #expect((attributes[kSecAttrAccount as String] as? String) == "rentivo.access-token")
  }

  let dataProtectionKey = kSecUseDataProtectionKeychain as String
  #expect(query(.explicitDataProtection)[dataProtectionKey] as? Bool == true)
  #expect(query(.implicitDataProtection)[dataProtectionKey] == nil)
  #expect(query(.legacyFile)[dataProtectionKey] == nil)
}

@Test func keychainValueAttributesAssertAccessibilityOutsideTheLegacyKeychain() {
  func attributes(_ backend: KeychainBackend) -> [String: Any] {
    KeychainCredentialStore.valueAttributes(token: "session-token", backend: backend)
  }

  let accessibleKey = kSecAttrAccessible as String
  let afterFirstUnlock = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String

  for backend in [KeychainBackend.implicitDataProtection, .explicitDataProtection] {
    #expect(attributes(backend)[kSecValueData as String] as? Data == Data("session-token".utf8))
    #expect((attributes(backend)[accessibleKey] as? String) == afterFirstUnlock)
  }

  // The legacy macOS keychain rejects the data-protection accessibility classes.
  #expect(attributes(.legacyFile)[kSecValueData as String] as? Data == Data("session-token".utf8))
  #expect(attributes(.legacyFile)[accessibleKey] == nil)
}

@Test func keychainFallsBackToTheLegacyKeychainOnlyForAMissingEntitlement() {
  #expect(KeychainBackend.explicitDataProtection.fallback(after: errSecMissingEntitlement) == .legacyFile)

  for status in [errSecSuccess, errSecItemNotFound, errSecAuthFailed, errSecInteractionNotAllowed] {
    #expect(KeychainBackend.explicitDataProtection.fallback(after: status) == nil)
  }

  // Only the explicit opt-in can be rejected for a missing entitlement, so the
  // other backends never retry.
  #expect(KeychainBackend.implicitDataProtection.fallback(after: errSecMissingEntitlement) == nil)
  #expect(KeychainBackend.legacyFile.fallback(after: errSecMissingEntitlement) == nil)
}

@Test func keychainBackendDefaultsToTheDataProtectionKeychainPerPlatform() {
  #if os(macOS)
    #expect(KeychainBackend.platformDefault == .explicitDataProtection)
  #else
    #expect(KeychainBackend.platformDefault == .implicitDataProtection)
  #endif
}

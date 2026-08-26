import Foundation
import RentivoCore
import SwiftUI
import Testing

@testable import Rentivo

@Suite("macOS account PIX form")
@MainActor
struct AccountProfilePIXTests {
  @Test("the PIX form round-trips through the app model and back into the loaded profile")
  func pixFormRoundTripsThroughTheAppModel() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    app.signIn()
    var form = ProfilePIXForm(profile: try await app.loadProfile())
    form.key = "jorge@example.com"
    form.merchantName = "JORGE JUNIOR"
    form.merchantCity = "SALVADOR"

    let saved = ProfilePIXForm(profile: try await app.updateProfilePIX(form.configuration))

    #expect(saved.key == "jorge@example.com")
    #expect(saved.merchantName == "JORGE JUNIOR")
    #expect(saved.merchantCity == "SALVADOR")
    // The screen's Salvar button is gated on this, and a reload has to agree with what was sent.
    #expect(saved.configuration?.isComplete == true)
    #expect(ProfilePIXForm(profile: try await app.loadProfile()) == saved)
  }

  @Test("the macOS type picker makes a non-UUID PIX key savable")
  func pixTypePickerMakesANonUUIDKeySavable() {
    var form = ProfilePIXForm()
    #expect(form.isSavable == false)
    #expect(form.configuration == nil)
    // ProfilePixView's "Tipo de chave" Picker writes this same property. Selecting E-mail must
    // move the form off its default random/UUID validation before the key is entered.
    form.keyType = .email
    form.key = "jorge@example.com"
    #expect(form.isSavable == false)
    #expect(form.configuration == nil)
    form.merchantName = "JORGE JUNIOR"
    #expect(form.isSavable == false)
    #expect(form.configuration == nil)
    form.merchantCity = "SALVADOR"
    #expect(form.isSavable)
    #expect(form.configuration?.isComplete == true)
    form.merchantName = String(repeating: "N", count: 256)
    #expect(form.isSavable == false)
    form.merchantName = "JORGE JUNIOR"
    form.merchantCity = String(repeating: "C", count: 256)
    #expect(form.isSavable == false)
  }

  @Test("the explicit removal action clears persisted PIX and confirms it")
  func explicitRemovalClearsPersistedPIX() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    app.signIn()
    #expect(try await app.loadProfile().pix != nil)

    let form = try await ProfilePIXRemoval.perform(in: app)

    #expect(form == ProfilePIXForm(profile: try await app.loadProfile()))
    #expect(try await app.loadProfile().pix == nil)
    #expect(app.notice?.message == "PIX pessoal removido.")
  }

  @Test("demo viewer mode locks the PIX section but still reads the profile")
  func viewerModeLocksThePIXSection() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    app.signIn()
    app.setViewerMode(true)

    // `isDemoViewerLocked` in ProfilePixView is exactly this pair; reading stays allowed so the
    // screen can still show the account's current configuration.
    #expect(app.usesLiveAPI == false)
    #expect(app.demoSettings.viewerMode)
    _ = try await app.loadProfile()
    await #expect(throws: DemoError.permissionDenied) {
      try await app.updateProfilePIX(
        PixConfiguration(key: "k", merchantName: "N", merchantCity: "C")
      )
    }
  }
}

@Suite("macOS API key form rules")
struct APIKeyFormRulesTests {
  @Test("a key needs a name, a scope, and a resource before it can be saved")
  func savableRequiresNameScopeAndResource() {
    #expect(
      APIKeyFormRules.isSavable(name: "", scopes: [.profileRead], resourceIDs: [.personal]) == false
    )
    #expect(APIKeyFormRules.isSavable(name: "CRM", scopes: [], resourceIDs: [.personal]) == false)
    #expect(APIKeyFormRules.isSavable(name: "CRM", scopes: [.profileRead], resourceIDs: []) == false)
    #expect(APIKeyFormRules.isSavable(name: "CRM", scopes: [.profileRead], resourceIDs: [.personal]))
    #expect(APIKeyFormRules.isSavable(name: "   ", scopes: [.profileRead], resourceIDs: [.personal]) == false)
    #expect(
      APIKeyFormRules.isSavable(
        name: String(repeating: "a", count: 256),
        scopes: [.profileRead],
        resourceIDs: [.personal]
      ) == false
    )
  }

  @Test("existing grants are reused, new ones are typed by resource, and the order is stable")
  func grantsReuseTheOriginalAndSortStably() throws {
    // The server marks a grant unavailable when the key still references a workspace the user
    // lost access to; rebuilding it from scratch would silently flip that flag back to true.
    let original = APIKeyGrant(resourceType: .user, resourceID: .personal, available: false)
    let organizationID = WorkspaceID(rawValue: "aaa-organization")

    let grants = APIKeyFormRules.grants(
      for: [.personal, organizationID],
      original: [original.resourceID: original]
    )

    #expect(grants.count == 2)
    #expect(grants == grants.sorted { $0.resourceID.rawValue < $1.resourceID.rawValue })
    let personal = try #require(grants.first { $0.resourceID == .personal })
    #expect(personal.available == false)
    let organization = try #require(grants.first { $0.resourceID == organizationID })
    #expect(organization.resourceType == .organization)
    #expect(organization.available)
  }

  @Test("dropping a resource drops its grant")
  func droppingAResourceDropsItsGrant() {
    let original = APIKeyGrant(resourceType: .user, resourceID: .personal)

    let grants = APIKeyFormRules.grants(for: [], original: [original.resourceID: original])

    #expect(grants.isEmpty)
  }
}

@Suite("macOS API key lifecycle")
@MainActor
struct APIKeyLifecycleTests {
  @Test("creating a key returns a one-time secret and lists the new metadata")
  func creatingAKeyReturnsAOneTimeSecret() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let draft = APIKeyDraft(
      name: "CRM",
      scopes: [.profileRead, .billingsRead],
      grants: APIKeyFormRules.grants(for: [.personal], original: [:]),
      expiresAt: Date(timeIntervalSince1970: 1_798_761_600)
    )

    let created = try await app.dependencies.apiKeys.createAPIKey(draft)

    #expect(created.secret.isEmpty == false)
    #expect(created.id == created.metadata.id)
    let keys = try await app.dependencies.apiKeys.listAPIKeys()
    #expect(keys.contains { $0.id == created.metadata.id })
  }

  @Test("revoking a key preserves it as revoked history")
  func revokingAKeyPreservesItAsRevokedHistory() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let key = try #require(await app.dependencies.apiKeys.listAPIKeys().first)

    try await app.dependencies.apiKeys.revokeAPIKey(id: key.id)

    let revoked = try #require(
      try await app.dependencies.apiKeys.listAPIKeys().first { $0.id == key.id }
    )
    #expect(revoked.revokedAt != nil)
  }

  @Test("demo viewer mode refuses to create or revoke keys")
  func viewerModeRefusesKeyMutations() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let key = try #require(await app.dependencies.apiKeys.listAPIKeys().first)
    app.setViewerMode(true)

    await #expect(throws: DemoError.permissionDenied) {
      try await app.dependencies.apiKeys.createAPIKey(.demo)
    }
    await #expect(throws: DemoError.permissionDenied) {
      try await app.dependencies.apiKeys.revokeAPIKey(id: key.id)
    }
  }
}

@Suite("macOS theme editing")
@MainActor
struct ThemeEditingTests {
  @Test("saving user theme values stores them and marks the user as the effective source")
  func savingUserThemeValuesStoresThem() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))

    try await app.dependencies.themes.updateTheme(target: .user, values: .sunset)

    let record = try await app.dependencies.themes.theme(target: .user)
    #expect(record.stored == .sunset)
    #expect(record.effective == .sunset)
    #expect(record.effectiveSource == .user)
    #expect(record.canEdit)
  }

  @Test("resetting a theme restores inheritance from the default")
  func resettingAThemeRestoresInheritance() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    try await app.dependencies.themes.updateTheme(target: .user, values: .sunset)

    try await app.dependencies.themes.resetTheme(target: .user)

    let record = try await app.dependencies.themes.theme(target: .user)
    #expect(record.stored == nil)
    #expect(record.effectiveSource == .default)
    #expect(record.canReset == false)
  }

  @Test("demo viewer mode makes the theme read-only, hiding Salvar")
  func viewerModeMakesTheThemeReadOnly() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    app.setViewerMode(true)

    let record = try await app.dependencies.themes.theme(target: .user)

    #expect(record.canEdit == false)
  }
}

@Suite("macOS theme hex colors")
struct ThemeColorHexTests {
  @Test("hex strings round-trip through the ColorPicker binding")
  func hexStringsRoundTrip() throws {
    // The API stores hex, the macOS ColorPicker speaks Color; the editor is only trustworthy if
    // a picked color writes back the same value it was seeded with.
    for hex in ["#07744F", "#FFFFFF", "#000000", "#4B2FA7"] {
      let color = try #require(Color(hex: hex))
      #expect(color.hexString == hex)
    }
  }

  @Test("hex parsing accepts a missing # and rejects malformed values")
  func hexParsingRejectsMalformedValues() {
    #expect(Color(hex: "07744F") != nil)
    #expect(Color(hex: "#07744") == nil)
    #expect(Color(hex: "#07744FF") == nil)
    #expect(Color(hex: "#GGGGGG") == nil)
    #expect(Color(hex: "") == nil)
  }
}

@Suite("macOS PT-BR date formatting")
struct PTBRDateFormattingTests {
  @Test("dates render in pt-BR regardless of the host locale")
  func datesRenderInPTBR() {
    // The API key cards and passkey rows drop these straight into Portuguese sentences, so an
    // en-US test machine must not leak "Jan 16, 2026" into the copy. The timestamp is midnight
    // UTC, so a westward host time zone can shift the day but never the month.
    let date = Date(timeIntervalSince1970: 1_768_521_600)

    let formatted = date.formattedPTBR()

    #expect(formatted.contains("2026"))
    #expect(formatted.contains("jan"))
    #expect(formatted.contains(" de "))
  }
}

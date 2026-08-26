import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

@Test func profilePIXFormUsesTheAuthoritativeProfileValues() {
  let savedPIX = PixConfiguration(
    key: "jorge@example.com", merchantName: "JORGE JUNIOR", merchantCity: "SALVADOR"
  )
  let profile = UserProfile(id: 7, email: "jorge@example.com", pix: savedPIX)

  let form = ProfilePIXForm(profile: profile)

  #expect(form.configuration == savedPIX)
}

@Test func profilePIXFormRequiresACompleteConfigurationToSave() {
  var form = ProfilePIXForm()
  #expect(!form.isSavable)

  form.keyType = .email
  form.key = "ana@example.com"
  #expect(!form.isSavable)
  form.merchantName = "ANA"
  #expect(!form.isSavable)
  form.merchantCity = "RECIFE"
  #expect(form.isSavable)

  form.merchantName = String(repeating: "N", count: 256)
  #expect(!form.isSavable)
  form.merchantName = "ANA"
  form.merchantCity = String(repeating: "C", count: 256)
  #expect(!form.isSavable)
}

@Test func profilePIXFormPreservesAnUnclassifiedLegacyKeyWithoutMakingItSavable() {
  let profile = UserProfile(
    id: 7,
    email: "ana@example.com",
    pix: PixConfiguration(key: "chave-legada", merchantName: "ANA", merchantCity: "RECIFE")
  )

  let form = ProfilePIXForm(profile: profile)

  #expect(form.keyType == .random)
  #expect(form.key == "chave-legada")
  #expect(form.preservesUnclassifiedLegacyKey)
  #expect(!form.isSavable)
  #expect(form.validationMessage == "Esta chave não corresponde ao tipo selecionado.")
}

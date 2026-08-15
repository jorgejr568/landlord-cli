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

@Test func profilePIXFormAllowsClearingOrSavingACompleteConfiguration() {
  var form = ProfilePIXForm()
  #expect(form.isSavable)

  form.key = "ana@example.com"
  #expect(!form.isSavable)
  form.merchantName = "ANA"
  #expect(!form.isSavable)
  form.merchantCity = "RECIFE"
  #expect(form.isSavable)
}

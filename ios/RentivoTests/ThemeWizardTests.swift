import Testing

#if canImport(Rentivo)
  @testable import Rentivo

  @Test func themeColorsRequireExactSixDigitHexValues() {
    #expect(ThemeWizardRules.colorValidationMessage("#12ABef") == nil)
    #expect(
      ThemeWizardRules.colorValidationMessage("12ABEF")
        == "Use uma cor hexadecimal no formato #RRGGBB."
    )
    #expect(
      ThemeWizardRules.colorValidationMessage("#12345")
        == "Use uma cor hexadecimal no formato #RRGGBB."
    )
    #expect(
      ThemeWizardRules.colorValidationMessage("#12345G")
        == "Use uma cor hexadecimal no formato #RRGGBB."
    )
  }

  @Test func themeLoadNeverAppliesAfterTheDraftChangesInFlight() {
    var editedDraft = ThemeValues.rentivo
    editedDraft.primary = "#123456"
    #expect(
      ThemeWizardRules.loadedValuesToApply(
        .sunset,
        requestDraft: .rentivo,
        currentDraft: .rentivo,
        requestDraftRevision: 4,
        currentDraftRevision: 5
      ) == nil
    )
    #expect(
      ThemeWizardRules.loadedValuesToApply(
        .sunset,
        requestDraft: .rentivo,
        currentDraft: editedDraft,
        requestDraftRevision: 4,
        currentDraftRevision: 4
      ) == nil
    )
    #expect(
      ThemeWizardRules.loadedValuesToApply(
        .sunset,
        requestDraft: .rentivo,
        currentDraft: .rentivo,
        requestDraftRevision: 4,
        currentDraftRevision: 4
      ) == .sunset
    )
  }

  @Test func themeLoadPolicyProtectsDirtyDrafts() {
    #expect(ThemeWizardRules.shouldLoad(isDirty: false, force: false))
    #expect(!ThemeWizardRules.shouldLoad(isDirty: true, force: false))
    #expect(ThemeWizardRules.shouldLoad(isDirty: true, force: true))
  }
#endif

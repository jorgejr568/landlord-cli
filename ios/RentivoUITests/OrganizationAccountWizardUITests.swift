import XCTest

@MainActor
final class OrganizationAccountWizardUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testOrganizationWizardStartsWithIdentity() throws {
    let app = launchAndSignIn()

    app.tabBars.buttons["Organizações"].tap()
    let create = app.buttons["organization.create"]
    XCTAssertTrue(create.waitForExistence(timeout: 3))
    create.tap()

    XCTAssertTrue(app.staticTexts["Etapa 1 de 3"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.staticTexts["Organização"].exists)
  }

  func testProfilePIXWizardStartsWithKeyStep() throws {
    let app = launchAndSignIn()

    app.tabBars.buttons["Conta"].tap()
    let pix = app.buttons["account.pix"]
    XCTAssertTrue(pix.waitForExistence(timeout: 3))
    pix.tap()

    XCTAssertTrue(app.staticTexts["Etapa 1 de 3"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.staticTexts["Chave"].exists)
    XCTAssertTrue(app.buttons["profile.pix.key-type"].exists)
    let remove = app.buttons["profile.pix.remove"]
    XCTAssertTrue(remove.waitForExistence(timeout: 3))
    remove.tap()
    XCTAssertTrue(app.staticTexts["Remover chave PIX?"].waitForExistence(timeout: 2))
    app.buttons["Cancelar"].tap()

    let continueButton = app.buttons["wizard.continue"]
    XCTAssertTrue(waitForEnabled(continueButton))
    continueButton.tap()
    XCTAssertTrue(app.staticTexts["Etapa 2 de 3"].waitForExistence(timeout: 2))
    continueButton.tap()
    XCTAssertTrue(app.staticTexts["Etapa 3 de 3"].waitForExistence(timeout: 2))
    XCTAssertFalse(app.staticTexts["Ambiente"].exists)

    let reveal = app.buttons["profile.pix.review.reveal"]
    XCTAssertEqual(reveal.label, "Mostrar chave")
    reveal.tap()
    XCTAssertEqual(reveal.label, "Ocultar chave")
    app.buttons["wizard.back"].tap()
    continueButton.tap()
    XCTAssertEqual(app.buttons["profile.pix.review.reveal"].label, "Mostrar chave")
  }

  func testChangePasswordShowsAllFieldsWithoutWizardChrome() throws {
    let app = launchAndSignIn()

    app.tabBars.buttons["Conta"].tap()
    app.buttons["Segurança"].tap()
    XCTAssertTrue(app.buttons["security.password.change"].waitForExistence(timeout: 3))
    app.buttons["security.password.change"].tap()

    XCTAssertFalse(app.staticTexts["Etapa 1 de 3"].exists)
    XCTAssertTrue(app.secureTextFields["password.form.current"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.secureTextFields["password.form.new"].exists)
    XCTAssertTrue(app.secureTextFields["password.form.confirmation"].exists)
    XCTAssertTrue(app.buttons["password.form.submit"].exists)

    app.buttons["password.form.submit"].tap()
    XCTAssertTrue(app.staticTexts["Informe sua senha atual."].waitForExistence(timeout: 2))
    XCTAssertTrue(waitForKeyboardFocus(on: app.secureTextFields["password.form.current"]))

    app.secureTextFields["password.form.current"].typeText("segredo")
    app.secureTextFields["password.form.new"].tap()
    app.secureTextFields["password.form.new"].typeText("segredo-novo")
    app.secureTextFields["password.form.confirmation"].tap()
    app.secureTextFields["password.form.confirmation"].typeText("segredo-novo")

    for identifier in ["password.form.current", "password.form.new", "password.form.confirmation"] {
      let reveal = app.buttons["\(identifier).reveal"]
      reveal.tap()
      XCTAssertTrue(app.textFields[identifier].waitForExistence(timeout: 2))
      XCTAssertFalse((app.textFields[identifier].value as? String ?? "").isEmpty)
      reveal.tap()
      XCTAssertTrue(app.secureTextFields[identifier].waitForExistence(timeout: 2))
    }

    app.buttons["password.form.submit"].tap()
    XCTAssertTrue(app.staticTexts["Senha alterada com sucesso."].waitForExistence(timeout: 3))
  }

  func testAPIKeyWizardUsesFourStepsAndCombinesScopesWithExpiration() throws {
    let app = launchAndSignIn()

    app.tabBars.buttons["Conta"].tap()
    app.buttons["Chaves de integração"].tap()
    let create = app.buttons["api-key.create"]
    XCTAssertTrue(create.waitForExistence(timeout: 3))
    create.tap()

    XCTAssertTrue(app.staticTexts["Etapa 1 de 4"].waitForExistence(timeout: 2))
    app.buttons["wizard.continue"].tap()
    XCTAssertTrue(app.staticTexts["Escopos e validade"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.staticTexts["Validade da chave"].exists)
    XCTAssertTrue(app.datePickers["api-key.form.expiration"].exists)
    app.buttons["wizard.continue"].tap()
    XCTAssertTrue(app.staticTexts["Etapa 3 de 4"].waitForExistence(timeout: 2))
    app.buttons["wizard.continue"].tap()
    XCTAssertTrue(app.staticTexts["Etapa 4 de 4"].waitForExistence(timeout: 2))
  }

  func testRejectedOrganizationStepFocusesTheNameField() throws {
    let app = launchAndSignIn()

    app.tabBars.buttons["Organizações"].tap()
    let create = app.buttons["organization.create"]
    XCTAssertTrue(create.waitForExistence(timeout: 3))
    create.tap()
    app.buttons["wizard.continue"].tap()

    let name = app.textFields["Nome"]
    XCTAssertTrue(app.staticTexts["Informe o nome da organização."].waitForExistence(timeout: 2))
    XCTAssertTrue(waitForKeyboardFocus(on: name))
  }

  func testThemeRejectsAnInvalidPrimaryColorAndFocusesIt() throws {
    let app = launchAndSignInAndOpenTheme()

    app.buttons["wizard.continue"].tap()
    let primary = app.textFields["Primária"]
    XCTAssertTrue(primary.waitForExistence(timeout: 2))
    primary.tap()
    primary.typeText("Z")
    app.textFields["Primária clara"].tap()
    app.buttons["wizard.continue"].tap()

    XCTAssertTrue(
      app.staticTexts["Use uma cor hexadecimal no formato #RRGGBB."]
        .waitForExistence(timeout: 2)
    )
    XCTAssertTrue(waitForKeyboardFocus(on: primary))
    XCTAssertTrue(app.staticTexts["Etapa 2 de 5"].exists)
  }

  func testThemeResetWaitsForReviewCommit() throws {
    let app = launchAndSignInAndOpenTheme()

    for _ in 0..<3 {
      app.buttons["wizard.continue"].tap()
    }
    let reset = app.buttons["Restaurar herança"]
    XCTAssertTrue(reset.waitForExistence(timeout: 2))
    reset.tap()

    XCTAssertFalse(app.staticTexts["Herança de tema restaurada."].waitForExistence(timeout: 2))
    XCTAssertTrue(app.staticTexts["Restauração selecionada"].exists)
    app.buttons["wizard.continue"].tap()
    XCTAssertTrue(app.staticTexts["Restaurar herança"].exists)
    app.buttons["wizard.commit"].tap()
    XCTAssertTrue(app.staticTexts["Herança de tema restaurada."].waitForExistence(timeout: 3))
  }

  private func launchAndSignInAndOpenTheme() -> XCUIApplication {
    let app = launchAndSignIn()
    app.tabBars.buttons["Conta"].tap()
    let theme = app.buttons["account.theme"]
    XCTAssertTrue(theme.waitForExistence(timeout: 3))
    theme.tap()
    XCTAssertTrue(app.buttons["wizard.continue"].waitForExistence(timeout: 2))
    return app
  }

  private func waitForKeyboardFocus(on element: XCUIElement) -> Bool {
    XCTWaiter.wait(
      for: [
        XCTNSPredicateExpectation(
          predicate: NSPredicate(format: "hasKeyboardFocus == true"),
          object: element
        )
      ],
      timeout: 2
    ) == .completed
  }

  private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
    XCTWaiter.wait(
      for: [
        XCTNSPredicateExpectation(
          predicate: NSPredicate(format: "isEnabled == true"),
          object: element
        )
      ],
      timeout: timeout
    ) == .completed
  }

  private func launchAndSignIn() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()

    let email = app.textFields["login.email"]
    XCTAssertTrue(email.waitForExistence(timeout: 10))
    email.tap()
    email.typeText("ana@rentivo.com.br")

    let password = app.secureTextFields["login.password"]
    password.tap()
    password.typeText("segredo")
    app.buttons["login.submit"].tap()

    let savePasswordSheet = app.sheets.firstMatch
    if savePasswordSheet.waitForExistence(timeout: 5) {
      savePasswordSheet.buttons.element(boundBy: 0).tap()
    }
    XCTAssertTrue(app.tabBars.buttons["Início"].waitForExistence(timeout: 5))
    return app
  }
}

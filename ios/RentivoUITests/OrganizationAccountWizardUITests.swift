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

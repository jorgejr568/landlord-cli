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

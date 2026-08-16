import XCTest

@MainActor
final class BillingWizardUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testBillingWizardRequiresEssentialsThenReachesReview() throws {
    let app = launchAndSignIn()
    app.tabBars.buttons["Cobranças"].tap()
    app.buttons["billing.create"].tap()
    XCTAssertTrue(app.staticTexts["Etapa 1 de 5"].waitForExistence(timeout: 2))
    let continueButton = app.buttons["wizard.continue"]
    XCTAssertTrue(waitForEnabled(continueButton))
    continueButton.tap()
    XCTAssertTrue(app.staticTexts["Informe o nome da cobrança."].exists)
  }

  func testBillingWizardFocusesNameWhenEssentialsAreInvalid() throws {
    let app = launchAndSignIn()
    app.tabBars.buttons["Cobranças"].tap()
    app.buttons["billing.create"].tap()
    let continueButton = app.buttons["wizard.continue"]
    XCTAssertTrue(waitForEnabled(continueButton))
    continueButton.tap()

    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
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
      XCTAssertTrue(savePasswordSheet.waitForNonExistence(timeout: 5))
    }
    XCTAssertTrue(app.tabBars.buttons["Início"].waitForExistence(timeout: 5))
    return app
  }

  private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isEnabled == true"),
      object: element
    )
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
  }

}

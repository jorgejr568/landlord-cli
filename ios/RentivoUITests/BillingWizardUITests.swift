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

  func testRecurringItemUsesSharedBrazilianCurrencyInput() throws {
    let app = launchAndSignIn()
    app.tabBars.buttons["Cobranças"].tap()
    app.buttons["billing.create"].tap()

    let name = app.textFields["Nome"]
    XCTAssertTrue(name.waitForExistence(timeout: 2))
    name.tap()
    name.typeText("Apartamento 202")
    app.buttons["wizard.continue"].tap()

    app.buttons["billing.form.items.add"].tap()
    let description = app.textFields["billing.form.item.0.description"]
    description.tap()
    description.typeText("Aluguel")
    let amount = app.textFields["billing.form.item.0.amount"]
    amount.tap()
    amount.typeText("350")

    XCTAssertTrue(waitForValue(of: amount, containing: "R$ 3,50"))
  }

  private func launchAndSignIn() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [
      "--ui-testing", "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR",
    ]
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
      let dismissSavePassword = savePasswordSheet.buttons.element(boundBy: 0)
      dismissSavePassword.tap()
      XCTAssertTrue(dismissSavePassword.waitForNonExistence(timeout: 5))
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

  private func waitForValue(
    of element: XCUIElement, containing substring: String, timeout: TimeInterval = 3
  ) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value CONTAINS %@", substring), object: element)
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
  }

}

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
    XCTAssertTrue(
      app.staticTexts["Inválido. Informe o nome da cobrança."].waitForExistence(timeout: 2)
    )
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

  func testBillingFieldsStaySeparateAndCurrencyFormatsAsBRL() throws {
    let app = launchAndSignIn()
    app.tabBars.buttons["Cobranças"].tap()
    app.buttons["billing.create"].tap()
    let continueButton = app.buttons["wizard.continue"]
    XCTAssertTrue(waitForEnabled(continueButton))

    // Fill the lower multiline control first, before the keyboard can cover its hit region.
    let description = app.descendants(matching: .any)["billing.form.description"]
    XCTAssertTrue(description.isHittable)
    description.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.2)).tap()
    let focusedDescription = app.descendants(matching: .any)["billing.form.description"]
    focusedDescription.typeText("Aluguel e encargos apartamento 202")

    let name = app.textFields["billing.form.name"]
    XCTAssertTrue(name.isHittable)
    name.tap()
    XCTAssertTrue(waitForKeyboardFocus(on: name))
    name.typeText("Apartamento 202")

    XCTAssertEqual(app.textFields["billing.form.name"].value as? String, "Apartamento 202")
    XCTAssertEqual(
      app.descendants(matching: .any)["billing.form.description"].value as? String,
      "Aluguel e encargos apartamento 202"
    )
    continueButton.tap()

    app.buttons["billing.form.items.add"].tap()
    let itemDescription = app.textFields["billing.form.item.0.description"]
    itemDescription.tap()
    itemDescription.typeText("Aluguel")
    var amount = app.textFields["billing.form.item.0.amount"]
    amount.tap()
    amount = app.textFields["billing.form.item.0.amount"]
    XCTAssertTrue(waitForKeyboardFocus(on: amount))
    for (digit, formattedValue) in [
      ("1", "R$ 0,01"),
      ("2", "R$ 0,12"),
      ("0", "R$ 1,20"),
      ("0", "R$ 12,00"),
      ("0", "R$ 120,00"),
      ("0", "R$ 1.200,00"),
    ] {
      amount.typeText(digit)
      XCTAssertTrue(waitForValue(of: amount, containing: formattedValue))
    }

    XCTAssertEqual(itemDescription.value as? String, "Aluguel")
    XCTAssertEqual(amount.value as? String, "R$ 1.200,00")

    continueButton.tap()
    continueButton.tap()
    continueButton.tap()
    XCTAssertTrue(app.staticTexts["Etapa 5 de 5"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.staticTexts["Apartamento 202"].exists)
    XCTAssertTrue(app.staticTexts["R$ 1.200,00"].exists)
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

  private func waitForKeyboardFocus(on element: XCUIElement) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: element)
    return XCTWaiter().wait(for: [expectation], timeout: 2) == .completed
  }

  private func waitForValue(
    of element: XCUIElement, containing substring: String, timeout: TimeInterval = 3
  ) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value CONTAINS %@", substring), object: element)
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
  }

}

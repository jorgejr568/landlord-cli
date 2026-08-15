import XCTest

@MainActor
final class BillOperationsWizardUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  /// Catches a regression that presents the bill editor as one long form instead of starting the
  /// five-step workflow at the competência step.
  func testBillWizardMovesFromCompetenceToReview() throws {
    let app = launchAndSignInAndOpenCanonicalBilling()

    let createBill = app.buttons["bill.create"]
    scrollTo(createBill, in: app)
    createBill.tap()

    XCTAssertTrue(app.staticTexts["Etapa 1 de 5"].waitForExistence(timeout: 2))
  }

  /// Catches a regression that combines an expense's descriptive details with its amount and
  /// date, instead of beginning the three-step flow with the details step.
  func testExpenseWizardSeparatesDetailsFromAmount() throws {
    let app = launchAndSignInAndOpenExpenses()

    app.buttons["Adicionar"].tap()

    XCTAssertTrue(app.staticTexts["Etapa 1 de 3"].waitForExistence(timeout: 2))
  }

  func testBillWizardFocusesFirstInvalidLine() throws {
    let app = launchAndSignInAndOpenCanonicalBilling()

    let createBill = app.buttons["bill.create"]
    scrollTo(createBill, in: app)
    createBill.tap()
    app.buttons["wizard.continue"].tap()
    XCTAssertTrue(app.staticTexts["Etapa 2 de 5"].waitForExistence(timeout: 2))
    app.buttons["wizard.continue"].tap()
    XCTAssertTrue(app.staticTexts["Etapa 3 de 5"].waitForExistence(timeout: 2))
    let descriptions = app.textFields.matching(
      NSPredicate(format: "placeholderValue == %@", "Descrição")
    )
    XCTAssertGreaterThan(descriptions.count, 0)
    let firstDescription = descriptions.firstMatch
    firstDescription.tap()
    firstDescription.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 255))
    app.buttons["wizard.continue"].tap()

    XCTAssertTrue(app.staticTexts["Descreva todos os itens da fatura."].waitForExistence(timeout: 2))
    assertFocused(firstDescription)
  }

  func testBillWizardFocusesInvalidExtraAmount() throws {
    let app = launchAndSignInAndOpenCanonicalBilling()

    let createBill = app.buttons["bill.create"]
    scrollTo(createBill, in: app)
    createBill.tap()
    app.buttons["wizard.continue"].tap()
    XCTAssertTrue(app.staticTexts["Etapa 2 de 5"].waitForExistence(timeout: 2))
    app.buttons["wizard.continue"].tap()
    XCTAssertTrue(app.staticTexts["Etapa 3 de 5"].waitForExistence(timeout: 2))
    app.buttons["Adicionar item extra"].tap()

    let descriptions = app.textFields.matching(
      NSPredicate(format: "placeholderValue == %@", "Descrição")
    )
    let extraDescription = descriptions.element(boundBy: descriptions.count - 1)
    extraDescription.tap()
    extraDescription.typeText("Ajuste")
    let amounts = app.textFields.matching(
      NSPredicate(format: "label == %@", "Valor em centavos")
    )
    let extraAmount = amounts.element(boundBy: amounts.count - 1)
    app.buttons["wizard.continue"].tap()

    XCTAssertTrue(
      app.staticTexts["Os itens extras devem ter valor maior que zero."].waitForExistence(timeout: 2)
    )
    assertFocused(extraAmount)
  }

  func testExpenseWizardFocusesDescriptionWhenDetailsAreInvalid() throws {
    let app = launchAndSignInAndOpenExpenses()

    app.buttons["Adicionar"].tap()
    let description = app.textFields["Descrição"]
    app.buttons["wizard.continue"].tap()

    assertFocused(description)
  }

  func testExpenseWizardFocusesAmountWhenValueIsInvalid() throws {
    let app = launchAndSignInAndOpenExpenses()

    app.buttons["Adicionar"].tap()
    let description = app.textFields["Descrição"]
    description.tap()
    description.typeText("Reparo")
    app.buttons["wizard.continue"].tap()
    XCTAssertTrue(app.staticTexts["Etapa 2 de 3"].waitForExistence(timeout: 2))

    let amount = app.textFields["Valor em centavos"]
    app.buttons["wizard.continue"].tap()

    XCTAssertTrue(app.staticTexts["Informe um valor maior que zero."].waitForExistence(timeout: 2))
    assertFocused(amount)
  }

  func testCommunicationWizardDisablesCommitWhilePDFIsRendering() throws {
    let app = launchAndSignInAndOpenCanonicalBilling()
    let draft = app.buttons["bill.card.00000000-0000-0000-0000-000000001001"]
    scrollTo(draft, in: app)
    draft.tap()

    let regenerate = app.buttons["Regenerar documento"]
    scrollTo(regenerate, in: app)
    regenerate.tap()
    XCTAssertTrue(app.staticTexts["Renderizando…"].waitForExistence(timeout: 2))

    let communicate = app.buttons["Enviar comunicação"]
    scrollTo(communicate, in: app)
    communicate.tap()
    for _ in 0..<4 {
      app.buttons["wizard.continue"].tap()
    }

    XCTAssertFalse(app.buttons["wizard.commit"].isEnabled)
    let backButtons = app.buttons.matching(identifier: "wizard.back")
    XCTAssertGreaterThan(backButtons.count, 0)
    XCTAssertTrue(backButtons.element(boundBy: backButtons.count - 1).isEnabled)
  }

  private func launchAndSignInAndOpenCanonicalBilling() -> XCUIApplication {
    let app = launchAndSignIn()
    app.tabBars.buttons["Cobranças"].tap()

    let billing = app.buttons["billing.card.00000000-0000-0000-0000-000000000101"]
    XCTAssertTrue(billing.waitForExistence(timeout: 3))
    billing.tap()
    XCTAssertTrue(app.navigationBars["Detalhes"].waitForExistence(timeout: 2))
    return app
  }

  private func launchAndSignInAndOpenExpenses() -> XCUIApplication {
    let app = launchAndSignInAndOpenCanonicalBilling()
    let expenses = app.buttons["Despesas"]
    scrollTo(expenses, in: app)
    expenses.tap()
    XCTAssertTrue(app.navigationBars["Despesas"].waitForExistence(timeout: 2))
    return app
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

  private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
    var attempts = 0
    while !element.exists && attempts < 8 {
      app.swipeUp()
      attempts += 1
    }
    XCTAssertTrue(element.exists)
  }

  private func assertFocused(_ element: XCUIElement, timeout: TimeInterval = 2) {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "hasFocus == true"), object: element
    )
    XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed)
  }
}

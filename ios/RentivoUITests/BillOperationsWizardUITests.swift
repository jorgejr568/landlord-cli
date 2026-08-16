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
    XCTAssertEqual(app.buttons["wizard.continue"].label, "Continuar")
    XCTAssertTrue(app.buttons["wizard.close"].exists)

    app.buttons["wizard.continue"].tap()
    app.buttons["wizard.close"].tap()
    XCTAssertTrue(app.staticTexts["Descartar alterações?"].waitForExistence(timeout: 2))
    let keepEditing = app.buttons["xmark"]
    XCTAssertTrue(keepEditing.waitForExistence(timeout: 2))
    keepEditing.tap()
    XCTAssertTrue(app.staticTexts["Etapa 2 de 5"].exists)
  }

  /// Catches a regression that combines an expense's descriptive details with its amount and
  /// date, instead of beginning the three-step flow with the details step.
  func testExpenseWizardSeparatesDetailsFromAmount() throws {
    let app = launchAndSignInAndOpenExpenses()

    app.buttons["Adicionar"].tap()

    XCTAssertTrue(app.staticTexts["Etapa 1 de 3"].waitForExistence(timeout: 2))
    let description = app.textFields["Descrição"]
    description.tap()
    description.typeText("Manutenção")
    app.buttons["wizard.continue"].tap()

    let amount = app.textFields["Valor em centavos"]
    XCTAssertTrue(amount.waitForExistence(timeout: 2))
    amount.tap()
    amount.typeText("1000")
    app.buttons["wizard.continue"].tap()

    XCTAssertEqual(app.buttons["wizard.commit"].label, "Salvar despesa")
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

  func testSuccessfulExportDismissesTheWizardAndShowsConfirmation() throws {
    let app = launchAndSignInAndOpenCanonicalBilling()
    let export = app.buttons["Exportar dados"]
    scrollTo(export, in: app)
    export.tap()

    XCTAssertTrue(app.staticTexts["Etapa 1 de 3"].waitForExistence(timeout: 2))
    app.buttons["wizard.continue"].tap()
    app.buttons["wizard.continue"].tap()
    app.buttons["wizard.commit"].tap()

    XCTAssertTrue(app.navigationBars["Detalhes"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["Exportação CSV enfileirada."].waitForExistence(timeout: 3))
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
}

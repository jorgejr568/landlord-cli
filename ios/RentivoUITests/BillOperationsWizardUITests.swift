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
    XCTAssertTrue(app.staticTexts["Ano"].exists)
    let year = app.descendants(matching: .any)["bill.form.year"]
    XCTAssertTrue(year.exists)
    XCTAssertEqual(year.value as? String, "2026")
    XCTAssertFalse(
      app.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "2.026", "2.026")
      ).firstMatch.exists
    )
    XCTAssertEqual(app.buttons["wizard.continue"].label, "Continuar")
    XCTAssertTrue(app.buttons["wizard.close"].exists)

    app.buttons["wizard.continue"].tap()
    app.buttons["wizard.close"].tap()
    let discardTitle = app.staticTexts["Descartar alterações?"]
    XCTAssertTrue(discardTitle.waitForExistence(timeout: 2))
    XCTAssertTrue(app.sheets["Descartar alterações?"].exists)
    // iOS 26 exposes this confirmation dialog's cancel row without its SwiftUI label.
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
    XCTAssertTrue(discardTitle.waitForNonExistence(timeout: 2))
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

    let amount = app.textFields["expense.form.amount"]
    XCTAssertTrue(amount.waitForExistence(timeout: 2))
    amount.tap()
    amount.typeText("350")
    XCTAssertTrue(waitForValue(of: amount, containing: "R$ 3,50"))
    app.buttons["wizard.continue"].tap()

    XCTAssertEqual(app.buttons["wizard.commit"].label, "Salvar despesa")
  }

  func testBillVariableAmountFormatsContinuouslyAsBRL() throws {
    let app = launchAndSignInAndOpenCanonicalBilling()
    let createBill = app.buttons["bill.create"]
    scrollTo(createBill, in: app)
    createBill.tap()

    app.buttons["wizard.continue"].tap()
    app.buttons["wizard.continue"].tap()

    let amount = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH 'bill.form.line.' AND identifier ENDSWITH '.amount'")
    ).firstMatch
    XCTAssertTrue(amount.waitForExistence(timeout: 2))
    amount.tap()
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
    XCTAssertEqual(amount.value as? String, "R$ 1.200,00")
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

  func testCSVAndXLSXExportsShowTheSameEmailDeliveryConfirmation() throws {
    let app = launchAndSignInAndOpenCanonicalBilling()
    requestExport(format: "CSV", in: app)
    requestExport(format: "XLSX", in: app)
  }

  func testInvoiceOpensHumanNamedQuickLookPreview() throws {
    let app = launchAndSignInAndOpenCanonicalBilling()
    let augustBill = app.buttons["bill.card.00000000-0000-0000-0000-000000001002"]
    scrollTo(augustBill, in: app)
    augustBill.tap()

    XCTAssertTrue(app.staticTexts["Agosto de 2026"].waitForExistence(timeout: 2))
    let openInvoice = app.buttons["Abrir fatura em PDF"]
    scrollTo(openInvoice, in: app)
    openInvoice.tap()

    XCTAssertTrue(app.navigationBars["Prévia"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["Fatura - Apt 101 - Edifício Aurora - agosto 2026"].exists)
    XCTAssertTrue(app.buttons["Fechar"].exists)
    XCTAssertTrue(app.buttons["Compartilhar ou salvar arquivo"].exists)
    XCTAssertTrue(app.descendants(matching: .any)["document.preview.quicklook"].exists)
    XCTAssertFalse(app.images["doc.text.fill"].exists)
    XCTAssertFalse(app.staticTexts["Arquivo baixado do Rentivo."].exists)
  }

  func testFilesShowHumanNameTypeSizeAndCreationDate() throws {
    let app = launchAndSignInAndOpenCanonicalBilling()
    let files = app.buttons["Arquivos"]
    scrollTo(files, in: app)
    files.tap()

    XCTAssertTrue(app.staticTexts["Contrato de locação"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.staticTexts["184 kB • 15/01/2026"].exists)
    XCTAssertTrue(app.images["attachment.type.doc.richtext.fill"].exists)
    XCTAssertTrue(app.staticTexts["vistoria-entrada.jpg"].exists)
    XCTAssertTrue(app.staticTexts["92 kB"].exists)
    XCTAssertTrue(app.images["attachment.type.photo.fill"].exists)
  }

  private func requestExport(format: String, in app: XCUIApplication) {
    let export = app.buttons["Exportar dados"]
    scrollTo(export, in: app)
    export.tap()

    XCTAssertTrue(app.staticTexts["Etapa 1 de 3"].waitForExistence(timeout: 2))
    if format == "XLSX" {
      app.buttons["XLSX"].tap()
    }
    app.buttons["wizard.continue"].tap()
    app.buttons["wizard.continue"].tap()
    app.buttons["wizard.commit"].tap()

    let toast = app.descendants(matching: .any)["notice.toast"]
    XCTAssertTrue(toast.waitForExistence(timeout: 7))
    XCTAssertTrue(
      toast.staticTexts[
        "Sucesso: Exportação solicitada. O arquivo será enviado para seu e-mail."
      ].exists
    )
    XCTAssertTrue(app.navigationBars["Detalhes"].waitForExistence(timeout: 3))
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

  private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
    var attempts = 0
    while !element.exists && attempts < 8 {
      app.swipeUp()
      attempts += 1
    }
    XCTAssertTrue(element.exists)
  }

  private func waitForValue(
    of element: XCUIElement, containing substring: String, timeout: TimeInterval = 3
  ) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value CONTAINS %@", substring), object: element)
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
  }

  private func waitForKeyboardFocus(on element: XCUIElement) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: element)
    return XCTWaiter().wait(for: [expectation], timeout: 2) == .completed
  }
}

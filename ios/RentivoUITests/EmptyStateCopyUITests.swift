import XCTest

@MainActor
final class EmptyStateCopyUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testEditableTopLevelEmptyStatesUseFeatureCopyAndInlineActions() {
    let app = launchAuthenticated("--ui-testing-empty")

    app.tabBars.buttons["Cobranças"].tap()
    assertText("Nenhuma cobrança ainda", in: app)
    assertText("Crie sua primeira cobrança para começar a gerar faturas.", in: app)
    XCTAssertTrue(app.buttons["Nova cobrança"].exists)

    app.tabBars.buttons["Organizações"].tap()
    assertText("Nenhuma organização ainda", in: app)
    assertText(
      "Organizações reúnem cobranças e membros sob papéis e permissões compartilhados. Crie uma para colaborar com sua equipe.",
      in: app
    )
    XCTAssertTrue(app.buttons["Criar organização"].exists)

    app.tabBars.buttons["Conta"].tap()
    accountRow(titled: "Chaves de integração", in: app).tap()
    assertText("Nenhuma chave de integração", in: app)
    assertText(
      "Crie uma chave para conectar outro serviço ao Rentivo e escolher o que ele pode acessar.",
      in: app
    )
    app.buttons["page.empty"].tap()
    XCTAssertTrue(app.staticTexts["Etapa 1 de 4"].waitForExistence(timeout: 2))
  }

  func testViewerTopLevelEmptyStatesOmitImpossibleActions() {
    let app = launchAuthenticated("--ui-testing-empty", "--ui-testing-viewer")

    app.tabBars.buttons["Cobranças"].tap()
    assertText("As cobranças que você pode consultar aparecerão aqui.", in: app)
    XCTAssertFalse(app.buttons["Nova cobrança"].exists)

    app.tabBars.buttons["Organizações"].tap()
    assertText("As organizações das quais você participa aparecerão aqui.", in: app)
    XCTAssertFalse(app.buttons["Criar organização"].exists)

    app.tabBars.buttons["Conta"].tap()
    accountRow(titled: "Chaves de integração", in: app).tap()
    assertText("Não há chaves de integração nesta conta.", in: app)
    XCTAssertFalse(app.buttons["Criar chave"].exists)
  }

  func testExpenseAndFileEmptyStatesShareInlineAndToolbarActions() {
    let app = launchAuthenticated()
    openCanonicalBilling(in: app)
    enableEmptyMode(in: app)

    app.tabBars.buttons["Cobranças"].tap()
    let expenses = app.buttons["Despesas"]
    scrollTo(expenses, in: app)
    expenses.tap()
    assertText("Nenhuma despesa registrada", in: app)
    assertText(
      "Registre a primeira despesa para acompanhar os custos desta cobrança.", in: app)
    XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "Adicionar despesa").count, 1)
    app.buttons["Adicionar despesa"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Etapa 1 de 3"].waitForExistence(timeout: 2))
    app.buttons["wizard.close"].tap()
    XCTAssertTrue(app.navigationBars["Despesas"].waitForExistence(timeout: 2))

    app.navigationBars["Despesas"].buttons.element(boundBy: 0).tap()
    let files = app.buttons["Arquivos"]
    scrollTo(files, in: app)
    files.tap()
    assertText("Nenhum arquivo adicionado", in: app)
    assertText(
      "Adicione documentos ou imagens para encontrá-los junto desta cobrança.", in: app)
    XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "Adicionar arquivo").count, 1)
  }

  func testViewerExpenseAndFileEmptiesHaveNoAddAction() {
    let app = launchAuthenticated()
    openCanonicalBilling(in: app)
    enableEmptyAndViewerModes(in: app)

    app.tabBars.buttons["Cobranças"].tap()
    let expenses = app.buttons["Despesas"]
    scrollTo(expenses, in: app)
    expenses.tap()
    assertText("Não há despesas registradas nesta cobrança.", in: app)
    XCTAssertFalse(app.buttons["Adicionar despesa"].exists)

    app.navigationBars["Despesas"].buttons.element(boundBy: 0).tap()
    let files = app.buttons["Arquivos"]
    scrollTo(files, in: app)
    files.tap()
    assertText("Não há arquivos nesta cobrança.", in: app)
    XCTAssertFalse(app.buttons["Adicionar arquivo"].exists)
  }

  func testBillEmptyStateUsesGenerateActionWhenPIXIsReady() {
    let app = launchAuthenticated()
    openCanonicalBilling(in: app)
    enableEmptyMode(in: app)

    app.tabBars.buttons["Cobranças"].tap()
    assertText("Nenhuma fatura gerada", in: app)
    assertText("Gere a primeira fatura desta cobrança.", in: app)
    app.buttons["Gerar fatura"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Etapa 1 de 5"].waitForExistence(timeout: 2))
  }

  private func launchAuthenticated(_ additionalArguments: String...) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing-authenticated"] + additionalArguments
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Início"].waitForExistence(timeout: 8))
    return app
  }

  private func openCanonicalBilling(in app: XCUIApplication) {
    app.tabBars.buttons["Cobranças"].tap()
    let billing = app.buttons["billing.card.00000000-0000-0000-0000-000000000101"]
    XCTAssertTrue(billing.waitForExistence(timeout: 3))
    billing.tap()
    XCTAssertTrue(app.navigationBars["Detalhes"].waitForExistence(timeout: 2))
  }

  private func enableEmptyMode(in app: XCUIApplication) {
    app.tabBars.buttons["Conta"].tap()
    let scenarios = app.buttons["account.demo"]
    scrollTo(scenarios, in: app)
    scenarios.tap()
    app.buttons["demo.empty-mode"].tap()
    XCTAssertEqual(app.buttons["demo.empty-mode"].value as? String, "Ativo")
  }

  private func enableEmptyAndViewerModes(in app: XCUIApplication) {
    app.tabBars.buttons["Conta"].tap()
    let scenarios = app.buttons["account.demo"]
    scrollTo(scenarios, in: app)
    scenarios.tap()
    app.buttons["demo.empty-mode"].tap()
    app.buttons["demo.viewer-mode"].tap()
    XCTAssertEqual(app.buttons["demo.viewer-mode"].value as? String, "Ativo")
  }

  private func accountRow(titled title: String, in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
  }

  private func assertText(_ text: String, in app: XCUIApplication) {
    XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 3), "Missing copy: \(text)")
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

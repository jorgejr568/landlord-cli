import XCTest

// These UI tests drive the app in `--ui-testing` (mock store) mode against
// `MockFixtures.canonical`. Two constraints shape what's testable here:
//
// - Mock sign-in cannot fail. The login screen's credential form goes through
//   `MockRentivoStore.mobileLogin`, which authenticates any e-mail/password pair
//   and never returns an MFA challenge, and the "Entrar pelo navegador" path
//   short-circuits to the unconditional `AppModel.signIn()` whenever
//   `dependencies.auth` isn't `APIRentivoStore` (always true in `--ui-testing`
//   mode, see `RentivoApp.swift`). There is no launch argument, demo setting, or
//   injectable seam that makes it fail, so a prior
//   `testAuthenticationValidationIsRecoverable` test (typing a wrong password to
//   trigger `login.error`) is not reproducible without adding a test-only failure
//   hook to `AppModel`/`MockRentivoStore`/`RentivoApp.swift`, which is out of
//   scope for a test-only fix. Dropped.
// - File downloads use deterministic local fixtures, allowing the mock journey
//   to exercise the same preview sheet as the live repository.
@MainActor
final class RentivoUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testPrimaryDemonstrationJourney() throws {
    let app = launchAndSignIn()

    XCTAssertTrue(app.tabBars.buttons["Início"].waitForExistence(timeout: 3))
    app.tabBars.buttons["Cobranças"].tap()
    XCTAssertTrue(app.navigationBars["Cobranças"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["billing.create"].exists)

    app.tabBars.buttons["Organizações"].tap()
    XCTAssertTrue(app.navigationBars["Organizações"].waitForExistence(timeout: 2))

    app.tabBars.buttons["Conta"].tap()
    XCTAssertTrue(app.navigationBars["Conta"].waitForExistence(timeout: 2))
  }

  func testUpcomingBillOnHomeOpensItsDetailAndSurvivesLeavingTheList() throws {
    let app = launchAndSignIn()

    // "Próximas faturas" only lists draft/published/sent bills; the canonical
    // draft is one of them.
    let upcoming = app.buttons["home.bill.card.00000000-0000-0000-0000-000000001001"]
    scrollTo(upcoming, in: app)
    upcoming.tap()
    XCTAssertTrue(app.navigationBars["Fatura"].waitForExistence(timeout: 3))

    // Walking the bill to "paid" drops it out of "Próximas faturas" when the
    // dashboard reloads behind this screen. The push is value-based precisely
    // so that does not yank the user back to Início mid-flow.
    transition("published", in: app)
    transition("sent", in: app)
    transition("paid", in: app)
    XCTAssertTrue(app.navigationBars["Fatura"].exists)

    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.navigationBars["Início"].waitForExistence(timeout: 3))
    XCTAssertFalse(upcoming.exists)
  }

  func testBillingCreationValidation() throws {
    let app = launchAndSignIn()
    app.tabBars.buttons["Cobranças"].tap()
    app.buttons["billing.create"].tap()

    XCTAssertTrue(app.navigationBars["Nova cobrança"].waitForExistence(timeout: 2))
    app.buttons["wizard.continue"].tap()
    XCTAssertTrue(
      app.staticTexts.matching(identifier: "billing.form.validation").firstMatch
        .waitForExistence(timeout: 2)
    )
  }

  func testBillingCreationToPaidAndThemeJourney() throws {
    let app = launchAndSignIn()
    app.tabBars.buttons["Cobranças"].tap()
    openCanonicalBilling(in: app)

    scrollTo(app.buttons["bill.create"], in: app)
    app.buttons["bill.create"].tap()
    XCTAssertTrue(app.navigationBars["Gerar fatura"].waitForExistence(timeout: 2))
    for _ in 0..<4 {
      app.buttons["wizard.continue"].tap()
    }
    app.buttons["wizard.commit"].tap()
    XCTAssertTrue(app.staticTexts["Fatura criada como rascunho."].waitForExistence(timeout: 3))

    let draft = app.buttons["bill.card.00000000-0000-0000-0000-000000001001"]
    scrollTo(draft, in: app)
    draft.tap()
    transition("published", in: app)
    transition("sent", in: app)
    transition("paid", in: app)

    // "Abrir recibo" only appears once the bill is paid. The mock store returns
    // a deterministic PDF so the customer-facing preview path remains covered.
    let openReceipt = app.buttons["Abrir recibo"]
    scrollTo(openReceipt, in: app)
    openReceipt.tap()
    XCTAssertTrue(app.navigationBars["Prévia"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Compartilhar ou salvar arquivo"].exists)
    app.buttons["Fechar"].tap()
    XCTAssertTrue(app.navigationBars["Fatura"].waitForExistence(timeout: 3))

    app.navigationBars.buttons.element(boundBy: 0).tap()
    let theme = app.buttons["billing.theme"]
    scrollTo(theme, in: app)
    theme.tap()
    let continueButton = app.buttons["wizard.continue"]
    XCTAssertTrue(continueButton.waitForExistence(timeout: 2))
    continueButton.tap()
    let primary = app.textFields["Primária"]
    XCTAssertTrue(primary.waitForExistence(timeout: 2))
    primary.tap()
    primary.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7))
    primary.typeText("#123456")
    XCTAssertTrue(waitForValue(of: primary, containing: "#123456"))
    for _ in 0..<3 {
      app.buttons["wizard.continue"].tap()
    }
    XCTAssertTrue(app.staticTexts["Etapa 5 de 5"].exists)
    app.buttons["wizard.commit"].tap()
    XCTAssertTrue(app.staticTexts["Tema atualizado."].waitForExistence(timeout: 3))
  }

  func testExpenseCreationJourney() throws {
    let app = launchAndSignIn()
    app.tabBars.buttons["Cobranças"].tap()
    openCanonicalBilling(in: app)

    let expenses = app.buttons["Despesas"]
    scrollTo(expenses, in: app)
    expenses.tap()
    XCTAssertTrue(app.navigationBars["Despesas"].waitForExistence(timeout: 2))
    app.buttons["Adicionar"].tap()
    app.textFields["Descrição"].tap()
    app.textFields["Descrição"].typeText("Reparo da fechadura")
    app.buttons["wizard.continue"].tap()
    app.textFields["Valor em centavos"].tap()
    app.textFields["Valor em centavos"].typeText("12500")
    app.buttons["wizard.continue"].tap()
    app.buttons["wizard.commit"].tap()
    XCTAssertTrue(app.staticTexts["Reparo da fechadura"].waitForExistence(timeout: 3))
  }

  func testInvitationAcceptanceJourney() throws {
    let app = launchAndSignIn()
    app.tabBars.buttons["Organizações"].tap()
    let invitations = app.buttons["organization.invitations.open"]
    XCTAssertTrue(invitations.waitForExistence(timeout: 3))
    invitations.tap()
    XCTAssertTrue(app.navigationBars["Convites"].waitForExistence(timeout: 2))
    app.buttons["Aceitar"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["page.empty"].waitForExistence(timeout: 3)
    )
  }

  func testViewerModeHidesMutationActions() throws {
    let app = launchAndSignIn()
    openDemoScenarios(in: app)
    app.buttons["demo.viewer-mode"].tap()
    XCTAssertTrue(waitForValue(of: app.buttons["demo.viewer-mode"], equalTo: "Ativo"))

    app.tabBars.buttons["Cobranças"].tap()
    XCTAssertFalse(app.buttons["billing.create"].exists)
    openCanonicalBilling(in: app)
    XCTAssertFalse(app.buttons["billing.edit"].exists)
    XCTAssertFalse(app.buttons["bill.create"].exists)

    let draft = app.buttons["bill.card.00000000-0000-0000-0000-000000001001"]
    scrollTo(draft, in: app)
    draft.tap()
    XCTAssertFalse(app.buttons["bill.transition.published"].exists)
    XCTAssertTrue(
      app.staticTexts["Ciclo disponível somente para quem pode gerenciar faturas."]
        .waitForExistence(timeout: 2)
    )
  }

  func testFailureRecoveryEmptyStateAndResetJourney() throws {
    let app = launchAndSignIn()
    openDemoScenarios(in: app)
    app.buttons["demo.fail-next"].tap()

    app.tabBars.buttons["Cobranças"].tap()
    XCTAssertTrue(app.staticTexts["Não foi possível carregar"].waitForExistence(timeout: 3))
    app.buttons["Tentar novamente"].tap()
    XCTAssertTrue(
      app.buttons["billing.card.00000000-0000-0000-0000-000000000101"]
        .waitForExistence(timeout: 3)
    )

    app.tabBars.buttons["Conta"].tap()
    app.buttons["demo.empty-mode"].tap()
    app.tabBars.buttons["Cobranças"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["page.empty"].waitForExistence(timeout: 3)
    )

    app.tabBars.buttons["Conta"].tap()
    app.buttons["demo.reset"].tap()
    app.buttons["Restaurar tema"].tap()
    app.tabBars.buttons["Cobranças"].tap()
    XCTAssertTrue(
      app.buttons["billing.card.00000000-0000-0000-0000-000000000101"]
        .waitForExistence(timeout: 3)
    )
  }

  // A `testAPIKeyRevocationRequiresConfirmation` test (tapping the "Chaves de integração" row's
  // small in-row "Editar"/"Revogar" buttons — see `APIKeyListView` in `APIKeyViews.swift`) was
  // attempted here to cover the API-key revoke confirmation dialog. It was dropped: on this
  // simulator, XCUITest's synthesized tap on either button in that row (not just the one opening
  // the confirmationDialog) reliably fails to invoke the button's action — confirmed by "Editar"
  // also never presenting its edit sheet, which rules out anything specific to confirmationDialog.
  // Reproducing or fixing that would mean changing `APIKeyViews.swift`, which is out of scope for
  // a test-only fix. The passkey-delete and expense/attachment/receipt-delete confirmation
  // dialogs use the same `.confirmationDialog(_:isPresented:presenting:actions:message:)` pattern
  // and may share this risk; a future change to those rows' layout should re-attempt UI coverage.

  private func launchAndSignIn() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()
    signIn(app)
    return app
  }

  /// The native credential form (see `AuthViews.swift`) submits through
  /// `AppModel.signIn(email:password:)`, which in `--ui-testing` mode reaches
  /// `MockRentivoStore.mobileLogin` — it accepts any credentials and never
  /// raises an MFA challenge, so any non-empty pair signs in. "Entrar" stays
  /// disabled until both fields are filled, hence the typing.
  private func signIn(_ app: XCUIApplication) {
    let email = app.textFields["login.email"]
    XCTAssertTrue(email.waitForExistence(timeout: 10))
    email.tap()
    email.typeText("ana@rentivo.com.br")
    let password = app.secureTextFields["login.password"]
    password.tap()
    password.typeText("segredo")
    app.buttons["login.submit"].tap()
    // Submitting a password field makes iOS offer to save it ("Salvar Senha?"), and that sheet
    // covers the whole app — including the tab bar — until it is answered. Decline it via its
    // first button ("Agora Não"), matched by position because the wording follows the
    // simulator's locale.
    let savePasswordSheet = app.sheets.firstMatch
    if savePasswordSheet.waitForExistence(timeout: 5) {
      savePasswordSheet.buttons.element(boundBy: 0).tap()
      XCTAssertTrue(savePasswordSheet.waitForNonExistence(timeout: 5))
    }
    XCTAssertTrue(app.tabBars.buttons["Início"].waitForExistence(timeout: 5))
  }

  private func openCanonicalBilling(in app: XCUIApplication) {
    let billing = app.buttons["billing.card.00000000-0000-0000-0000-000000000101"]
    XCTAssertTrue(billing.waitForExistence(timeout: 3))
    billing.tap()
    XCTAssertTrue(app.navigationBars["Detalhes"].waitForExistence(timeout: 2))
  }

  private func openDemoScenarios(in app: XCUIApplication) {
    app.tabBars.buttons["Conta"].tap()
    let scenarios = app.buttons["account.demo"]
    scrollTo(scenarios, in: app)
    scenarios.tap()
    XCTAssertTrue(app.navigationBars["Cenários"].waitForExistence(timeout: 2))
  }

  private func transition(_ status: String, in app: XCUIApplication) {
    let button = app.buttons["bill.transition.\(status)"]
    scrollTo(button, in: app)
    button.tap()

    // Consequential transitions add a confirmation action; ordinary transitions proceed
    // immediately. Querying the action itself avoids runtime differences in whether SwiftUI
    // exposes confirmationDialog as an alert, menu, or sheet.
    let confirmationActions = app.buttons.matching(
      identifier: "bill.transition.confirm.\(status)"
    )
    if confirmationActions.firstMatch.waitForExistence(timeout: 1) {
      confirmationActions.element(boundBy: 0).tap()
    }
    XCTAssertFalse(button.waitForExistence(timeout: 3))
  }

  private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
    var attempts = 0
    while !element.exists && attempts < 8 {
      app.swipeUp()
      attempts += 1
    }
    XCTAssertTrue(element.exists)
  }

  private func waitForValue(of element: XCUIElement, equalTo value: String) -> Bool {
    XCTWaiter.wait(
      for: [
        XCTNSPredicateExpectation(
          predicate: NSPredicate(format: "value == %@", value),
          object: element
        )
      ],
      timeout: 3
    ) == .completed
  }

  private func waitForValue(of element: XCUIElement, containing value: String) -> Bool {
    XCTWaiter.wait(
      for: [
        XCTNSPredicateExpectation(
          predicate: NSPredicate(format: "value CONTAINS %@", value),
          object: element
        )
      ],
      timeout: 3
    ) == .completed
  }
}

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
    XCTAssertTrue(app.buttons["profile.pix.key-type"].exists)
    let remove = app.buttons["profile.pix.remove"]
    XCTAssertTrue(remove.waitForExistence(timeout: 3))
    remove.tap()
    XCTAssertTrue(app.staticTexts["Remover chave PIX?"].waitForExistence(timeout: 2))
    dismissConfirmation(titled: "Remover chave PIX?", in: app)

    let continueButton = app.buttons["wizard.continue"]
    XCTAssertTrue(waitForEnabled(continueButton))
    continueButton.tap()
    XCTAssertTrue(app.staticTexts["Etapa 2 de 3"].waitForExistence(timeout: 2))
    continueButton.tap()
    XCTAssertTrue(app.staticTexts["Etapa 3 de 3"].waitForExistence(timeout: 2))
    XCTAssertFalse(app.staticTexts["Ambiente"].exists)

    let reveal = app.buttons["profile.pix.review.reveal"]
    XCTAssertEqual(reveal.label, "Mostrar chave")
    reveal.tap()
    XCTAssertEqual(reveal.label, "Ocultar chave")
    app.buttons["wizard.back"].tap()
    continueButton.tap()
    XCTAssertEqual(app.buttons["profile.pix.review.reveal"].label, "Mostrar chave")
  }

  func testChangePasswordShowsAllFieldsWithoutWizardChrome() throws {
    let app = launchAndSignIn()

    app.tabBars.buttons["Conta"].tap()
    accountRow(titled: "Segurança", in: app).tap()
    XCTAssertTrue(app.buttons["security.password.change"].waitForExistence(timeout: 3))
    app.buttons["security.password.change"].tap()

    XCTAssertFalse(app.staticTexts["Etapa 1 de 3"].exists)
    XCTAssertTrue(app.secureTextFields["password.form.current"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.secureTextFields["password.form.new"].exists)
    XCTAssertTrue(app.secureTextFields["password.form.confirmation"].exists)
    XCTAssertTrue(app.buttons["password.form.submit"].exists)

    app.buttons["password.form.submit"].tap()
    XCTAssertTrue(
      app.staticTexts["Inválido. Informe sua senha atual."].waitForExistence(timeout: 2)
    )

    let currentPassword = app.secureTextFields["password.form.current"]
    currentPassword.tap()
    XCTAssertTrue(waitForKeyboardFocus(on: currentPassword))
    currentPassword.typeText("segredo")
    app.secureTextFields["password.form.new"].tap()
    app.secureTextFields["password.form.new"].typeText("segredo-novo")
    app.secureTextFields["password.form.confirmation"].tap()
    app.secureTextFields["password.form.confirmation"].typeText("segredo-novo")

    for identifier in ["password.form.current", "password.form.new", "password.form.confirmation"] {
      let reveal = app.buttons["\(identifier).visibility"]
      reveal.tap()
      XCTAssertTrue(app.textFields[identifier].waitForExistence(timeout: 2))
      XCTAssertFalse((app.textFields[identifier].value as? String ?? "").isEmpty)
      reveal.tap()
      XCTAssertTrue(app.secureTextFields[identifier].waitForExistence(timeout: 2))
    }

    app.buttons["password.form.submit"].tap()
    assertSuccessNotice("Senha alterada com sucesso.", in: app)
  }

  func testAPIKeyWizardUsesFourStepsAndCombinesScopesWithExpiration() throws {
    let app = launchAndSignIn()

    app.tabBars.buttons["Conta"].tap()
    accountRow(titled: "Chaves de integração", in: app).tap()
    let create = app.buttons["api-key.create"]
    XCTAssertTrue(create.waitForExistence(timeout: 3))
    create.tap()

    XCTAssertTrue(app.staticTexts["Etapa 1 de 4"].waitForExistence(timeout: 2))
    app.buttons["wizard.continue"].tap()
    XCTAssertTrue(app.staticTexts["Escopos e validade"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.staticTexts["Validade da chave"].exists)
    XCTAssertTrue(app.datePickers["api-key.form.expiration"].exists)
    app.buttons["wizard.continue"].tap()
    XCTAssertTrue(app.staticTexts["Etapa 3 de 4"].waitForExistence(timeout: 2))
    app.buttons["wizard.continue"].tap()
    XCTAssertTrue(app.staticTexts["Etapa 4 de 4"].waitForExistence(timeout: 2))
  }

  func testRejectedOrganizationStepFocusesTheNameField() throws {
    let app = launchAndSignIn()

    app.tabBars.buttons["Organizações"].tap()
    let create = app.buttons["organization.create"]
    XCTAssertTrue(create.waitForExistence(timeout: 3))
    create.tap()
    app.buttons["wizard.continue"].tap()

    let name = app.textFields["organization.form.name"]
    XCTAssertTrue(
      app.staticTexts["Inválido. Informe o nome da organização."]
        .waitForExistence(timeout: 2)
    )
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

    XCTAssertFalse(app.descendants(matching: .any)["notice.toast"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.staticTexts["Restauração selecionada"].exists)
    app.buttons["wizard.continue"].tap()
    XCTAssertTrue(app.staticTexts["Restaurar herança"].exists)
    app.buttons["wizard.commit"].tap()
    assertSuccessNotice("A aparência padrão foi restaurada.", in: app)
  }

  func testThemeTypographyLabelsAndPrimaryColorSwatchReachReview() throws {
    let app = launchAndSignInAndOpenTheme()

    XCTAssertTrue(app.staticTexts["Fonte de títulos"].exists)
    XCTAssertTrue(app.staticTexts["Fonte de texto"].exists)
    XCTAssertTrue(app.buttons["theme.form.header-font"].exists)
    XCTAssertTrue(app.buttons["theme.form.text-font"].exists)

    for _ in 0..<4 { app.buttons["wizard.continue"].tap() }
    let color = app.descendants(matching: .any)["theme.review.primary-color"]
    XCTAssertTrue(color.waitForExistence(timeout: 2))
    XCTAssertTrue(color.label.hasPrefix("Cor primária: #"))
    XCTAssertTrue(app.staticTexts["Tema aplicado"].exists)
  }

  func testInviteExplainsRolesAndUsesAccessLevelInReview() throws {
    let app = launchAndSignIn()
    openCanonicalOrganization(in: app)
    app.buttons["Convidar membro"].tap()

    let email = app.textFields["invite.form.email"]
    XCTAssertTrue(email.waitForExistence(timeout: 2))
    email.tap()
    email.typeText("nova@example.com")
    app.buttons["wizard.continue"].tap()

    XCTAssertTrue(app.staticTexts["Nível de acesso"].waitForExistence(timeout: 2))
    let adminRole = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Administrador,")
    ).firstMatch
    let managerRole = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Gerente,")
    ).firstMatch
    let viewerRole = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Visualizador,")
    ).firstMatch
    XCTAssertTrue(adminRole.label.contains(
      "Gerencia a organização, os membros e a segurança. Também cria e administra cobranças."
    ))
    XCTAssertTrue(managerRole.label.contains(
      "Pode criar cobranças e gerenciar faturas, despesas, comprovantes e envios. Não gerencia membros nem configurações da organização."
    ))
    XCTAssertTrue(viewerRole.label.contains(
      "Pode consultar a organização e as cobranças, sem criar nem alterar dados."
    ))
    managerRole.tap()
    app.buttons["wizard.continue"].tap()
    XCTAssertTrue(app.staticTexts["Nível de acesso"].exists)
    XCTAssertTrue(app.staticTexts["Gerente"].exists)
  }

  func testMemberRoleMenuMarksCurrentRoleAndOwnerCrownIsNamed() throws {
    let app = launchAndSignIn()
    openCanonicalOrganization(in: app)

    XCTAssertTrue(
      app.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS %@", "Dono da organização")
      ).firstMatch.waitForExistence(timeout: 2)
    )
    let roleMenu = app.buttons["organization.member.11.role-menu"]
    scrollTo(roleMenu, in: app)
    roleMenu.tap()
    let currentRole = app.buttons["Administrador"]
    XCTAssertTrue(currentRole.waitForExistence(timeout: 2))
    XCTAssertFalse(currentRole.isEnabled)
    XCTAssertTrue(app.buttons["Gerente"].isEnabled)
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

  private func openCanonicalOrganization(in app: XCUIApplication) {
    app.tabBars.buttons["Organizações"].tap()
    let organization = app.staticTexts["Imobiliária Horizonte"]
    XCTAssertTrue(organization.waitForExistence(timeout: 3))
    organization.tap()
    XCTAssertTrue(app.navigationBars["Organização"].waitForExistence(timeout: 2))
  }

  private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
    var attempts = 0
    while !element.exists && attempts < 8 {
      app.swipeUp()
      attempts += 1
    }
    XCTAssertTrue(element.exists)
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

  private func accountRow(titled title: String, in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
  }

  private func dismissConfirmation(titled title: String, in app: XCUIApplication) {
    XCTAssertTrue(app.sheets[title].exists)
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
    XCTAssertTrue(app.staticTexts[title].waitForNonExistence(timeout: 2))
  }

  private func assertSuccessNotice(_ message: String, in app: XCUIApplication) {
    let toast = app.descendants(matching: .any)["notice.toast"]
    XCTAssertTrue(toast.waitForExistence(timeout: 7))
    XCTAssertTrue(toast.staticTexts["Sucesso: \(message)"].exists)
  }

  private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
    XCTWaiter.wait(
      for: [
        XCTNSPredicateExpectation(
          predicate: NSPredicate(format: "isEnabled == true"),
          object: element
        )
      ],
      timeout: timeout
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

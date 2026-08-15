import XCTest

@MainActor
final class BillingNavigationUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
    executionTimeAllowance = 45
  }

  func testWideBillingToBillNavigation() {
    assertBillingToBillNavigation(width: 1280)
  }

  func testNarrowBillingToBillNavigation() {
    assertBillingToBillNavigation(width: 760)
  }

  func testHomeToBillNavigation() {
    let app = launch(width: 1280)
    defer { app.terminate() }

    let bill = app.buttons["home.bill.card.00000000-0000-0000-0000-000000001001"]
    XCTAssertTrue(bill.waitForExistence(timeout: 10))
    scrollToHittable(bill, in: app.scrollViews["home.scroll"])
    bill.tap()

    XCTAssertTrue(app.descendants(matching: .any)["bill.detail"].waitForExistence(timeout: 5))
  }

  func testBillingToExpensesNavigation() {
    let app = launch(width: 1280)
    defer { app.terminate() }
    openCanonicalBilling(in: app)

    let expenses = app.buttons["billing.expenses"]
    XCTAssertTrue(expenses.waitForExistence(timeout: 5))
    scrollToHittable(expenses, in: app.scrollViews["billing.detail.scroll"])
    expenses.tap()

    XCTAssertTrue(app.descendants(matching: .any)["expense.list"].waitForExistence(timeout: 5))
  }

  func testOrganizationNavigation() {
    let app = launch(width: 1280)
    defer { app.terminate() }

    let organizationsSection = app.staticTexts["Organizações"].firstMatch
    XCTAssertTrue(organizationsSection.waitForExistence(timeout: 5))
    organizationsSection.tap()

    let organization =
      app.buttons["organization.card.00000000-0000-0000-0000-000000000010"]
    XCTAssertTrue(organization.waitForExistence(timeout: 10))
    organization.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["organization.detail"].waitForExistence(timeout: 5)
    )
  }

  private func assertBillingToBillNavigation(width: Int) {
    let app = launch(width: width)
    defer { app.terminate() }
    openCanonicalBilling(in: app)

    let bill = app.buttons["bill.card.00000000-0000-0000-0000-000000001001"]
    XCTAssertTrue(bill.waitForExistence(timeout: 5))
    scrollToHittable(bill, in: app.scrollViews["billing.detail.scroll"])
    bill.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["bill.detail"].waitForExistence(timeout: 5)
    )
  }

  private func launch(width: Int) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [
      "--screenshot-authenticated",
      "--ui-test-window-width=\(width)",
    ]
    app.launch()

    let window = app.windows.firstMatch
    XCTAssertTrue(window.waitForExistence(timeout: 10))
    XCTAssertEqual(window.frame.width, CGFloat(width), accuracy: 20)
    return app
  }

  private func openCanonicalBilling(in app: XCUIApplication) {
    let billingsSection = app.staticTexts["Cobranças"].firstMatch
    XCTAssertTrue(billingsSection.waitForExistence(timeout: 5))
    billingsSection.tap()

    let billing = app.buttons["billing.card.00000000-0000-0000-0000-000000000101"]
    XCTAssertTrue(billing.waitForExistence(timeout: 10))
    billing.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["billing.detail"].waitForExistence(timeout: 5)
    )
  }

  private func scrollToHittable(_ element: XCUIElement, in scrollView: XCUIElement) {
    XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
    for _ in 0..<20 where !element.isHittable {
      let deltaY: CGFloat = element.frame.midY < scrollView.frame.midY ? 50 : -50
      scrollView.scroll(byDeltaX: 0, deltaY: deltaY)
    }
    XCTAssertTrue(element.isHittable)
  }
}

import XCTest

final class BudgetDetailUITests: XCTestCase {
    @MainActor
    func testBudgetExpensesAndEmptyStateLight() throws {
        try verifyBudget(dark: false)
    }

    @MainActor
    func testBudgetExpensesAndEmptyStateDark() throws {
        try verifyBudget(dark: true)
    }

    @MainActor
    private func verifyBudget(dark: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_BUDGET_DETAIL", "-CloudSyncEnabled", "NO"]
        if dark { app.launchArguments.append("UITEST_VISUAL_DARK") }
        app.launch()
        let food = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'budget-card-' AND label CONTAINS 'Alimentari'")).firstMatch
        XCTAssertTrue(food.waitForExistence(timeout: 10))
        food.tap()
        XCTAssertTrue(app.staticTexts["Transazioni del budget"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["3 transazioni · 130,00 €"].exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["Entrata esclusa"].exists)
        XCTAssertFalse(app.staticTexts["Periodo precedente"].exists)
        let order = app.buttons["budget-expense-order"]
        XCTAssertTrue(order.exists, app.debugDescription)
        order.tap()
        XCTAssertTrue(app.buttons["Importi maggiori"].waitForExistence(timeout: 5))
        app.buttons["Importi maggiori"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'budget-expense-' AND identifier != 'budget-expense-order'"))
            .firstMatch.label.contains("Supermercato"))
        let supermarket = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'budget-expense-' AND label CONTAINS 'Supermercato'")).firstMatch
        XCTAssertTrue(supermarket.waitForExistence(timeout: 5))
        capture(app, name: dark ? "Budget dark" : "Budget light")
        supermarket.tap()
        XCTAssertTrue(app.navigationBars["Dettaglio"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Supermercato"].exists)
        app.navigationBars["Dettaglio"].buttons["BackButton"].tap()
        XCTAssertTrue(order.waitForExistence(timeout: 5))
        app.buttons["Fine"].tap()
        let travel = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'budget-card-' AND label CONTAINS 'Viaggi'")).firstMatch
        for _ in 0..<4 {
            if travel.exists && travel.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(travel.isHittable)
        travel.tap()
        XCTAssertTrue(app.staticTexts["Nessuna spesa registrata per queste categorie nel periodo del budget."].waitForExistence(timeout: 5))
        capture(app, name: dark ? "Budget empty dark" : "Budget empty light")
        app.buttons["Fine"].tap()
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

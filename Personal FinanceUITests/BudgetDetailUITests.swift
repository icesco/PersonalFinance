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
        XCTAssertTrue(food.label.contains("Periodo del budget:"))
        food.tap()
        XCTAssertTrue(app.staticTexts["budget-detail-period"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["budget-detail-period"].label.contains("Mensile"))
        XCTAssertTrue(app.staticTexts["Transazioni del budget"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["4 transazioni · 135,00 €"].exists, app.debugDescription)
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
    func testDedicatedBudgetListFiltersAndPreviewLimit() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_BUDGET_DETAIL", "-CloudSyncEnabled", "NO"]
        app.launch()
        let food = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'budget-card-' AND label CONTAINS 'Alimentari'")).firstMatch
        XCTAssertTrue(food.waitForExistence(timeout: 10))
        food.tap()
        let previewRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'budget-expense-' AND identifier != 'budget-expense-order'"))
        XCTAssertTrue(app.buttons["budget-open-transactions"].waitForExistence(timeout: 5))
        XCTAssertEqual(previewRows.count, 3)
        for _ in 0..<4 {
            if app.buttons["budget-open-transactions"].isHittable { break }
            app.swipeUp()
        }
        app.buttons["budget-open-transactions"].tap()
        let count = app.staticTexts["budget-list-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertEqual(count.label, "4 transazioni")
        XCTAssertTrue(app.staticTexts["budget-list-total"].label.contains("135"))
        XCTAssertTrue(app.staticTexts["budget-list-date-range"].exists)
        XCTAssertTrue(app.staticTexts["budget-list-period-context"].label.contains("periodo completo"))
        capture(app, name: "Lista budget")
        app.buttons["budget-list-previous"].tap()
        expectation(for: NSPredicate(format: "label == %@", "1 transazione"), evaluatedWith: count)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["budget-list-total"].label.contains("999"))
        app.buttons["budget-list-next"].tap()
        app.buttons["budget-list-filter"].tap()
        app.buttons["Viaggi"].tap()
        expectation(for: NSPredicate(format: "label == %@", "0 transazioni"), evaluatedWith: count)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["Nessuna transazione"].exists)
        app.buttons["budget-list-filter"].tap()
        app.buttons["Tutti i budget"].tap()
        expectation(for: NSPredicate(format: "label == %@", "4 transazioni"), evaluatedWith: count)
        waitForExpectations(timeout: 5)
        app.buttons["budget-list-cadence"].tap()
        app.buttons["Trimestrale"].tap()
        XCTAssertEqual(count.label, "4 transazioni")
        app.buttons["budget-list-timeframe"].tap()
        app.buttons["Settimana"].tap()
        XCTAssertTrue(count.exists)
        capture(app, name: "Lista budget settimana")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

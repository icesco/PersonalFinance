import XCTest

final class MonthlyForecastUITests: XCTestCase {
    @MainActor
    private func launch(dark: Bool = false, large: Bool = false, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_MONTHLY_FORECAST", "-CloudSyncEnabled", "NO",
                               "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launchArguments += extra
        if dark { app.launchArguments += ["UITEST_VISUAL_DARK", "UITEST_FORECAST_REDUCE_MOTION"] }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["monthly-forecast-account-Cointestato"].waitForExistence(timeout: 15))
        waitForSnapshot(in: app)
        return app
    }

    @MainActor
    private func waitForSnapshot(in app: XCUIApplication) {
        XCTAssertTrue(app.switches["monthly-forecast-include-variables"].waitForExistence(timeout: 15))
    }

    @MainActor
    private func enableVariables(in app: XCUIApplication) {
        let include = app.switches["monthly-forecast-include-variables"]
        for _ in 0..<6 where !include.isHittable { app.swipeUp() }
        if include.frame.maxY > app.frame.maxY - 120 { app.swipeUp() }
        include.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(include.value as? String, "1")
    }

    @MainActor
    private func row(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    @MainActor
    private func showDetails(in app: XCUIApplication) {
        let details = row("Dettagli del calcolo", in: app)
        for _ in 0..<8 where !details.isHittable { app.swipeUp() }
        XCTAssertTrue(details.isHittable)
        details.tap()
    }

    @MainActor
    func testAccountSelectionDetailsAndMonthRules() {
        continueAfterFailure = false
        let app = launch()
        let expectedMonth = Date().formatted(.dateTime.month(.wide).locale(Locale(identifier: "it_IT")))
        XCTAssertTrue(app.staticTexts["monthly-forecast-month"].label.localizedCaseInsensitiveContains(expectedMonth))
        for type in ["credit", "savings", "cash", "investment", "other"] {
            XCTAssertFalse(app.buttons["monthly-forecast-account-\(type)"].exists)
        }
        XCTAssertTrue(app.staticTexts["Il saldo basta"].exists)
        XCTAssertFalse(row("Ricorrenti ancora da registrare", in: app).exists)
        showDetails(in: app)
        let variables = row("Variabili residue", in: app)
        for _ in 0..<6 where !variables.isHittable { app.swipeUp() }
        XCTAssertTrue(variables.isHittable)
        variables.tap()
        XCTAssertTrue(app.navigationBars["Base della stima"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Alimentari"].exists)
        row("Movimenti della base storica", in: app).tap()
        XCTAssertTrue(app.staticTexts["Spesa storica"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        for _ in 0..<6 where !app.buttons["monthly-forecast-account-Crédit Agricole"].isHittable { app.swipeDown() }
        app.buttons["monthly-forecast-account-Crédit Agricole"].tap()
        waitForSnapshot(in: app)
        showDetails(in: app)
        let occasional = row("Occasionali programmate da pagare", in: app)
        for _ in 0..<6 where !occasional.isHittable { app.swipeUp() }
        row("Occasionali programmate da pagare", in: app).tap()
        XCTAssertTrue(app.staticTexts["Consulto programmato"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Acquisto programmato"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        for _ in 0..<6 where !app.buttons["monthly-forecast-previous"].isHittable { app.swipeDown() }
        let previous = app.buttons["monthly-forecast-previous"]
        let currentMonth = app.staticTexts["monthly-forecast-month"].label
        XCTAssertFalse(previous.isEnabled)
        app.buttons["monthly-forecast-next"].tap()
        XCTAssertTrue(previous.isEnabled)
        XCTAssertNotEqual(app.staticTexts["monthly-forecast-month"].label, currentMonth)
        previous.tap()
        XCTAssertEqual(app.staticTexts["monthly-forecast-month"].label, currentMonth)
        XCTAssertFalse(previous.isEnabled)
        app.buttons["monthly-forecast-next"].tap()
        XCTAssertTrue(row("Totale ancora necessario", in: app).waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Previsione mese futuro per conto"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testSafetyReservePercentageAndFixedAmount() {
        continueAfterFailure = false
        let app = launch()
        let input = app.textFields["monthly-safety-value"]
        for _ in 0..<6 where !input.isHittable { app.swipeUp() }
        XCTAssertTrue(input.isHittable)
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        input.typeText(XCUIKeyboardKey.delete.rawValue + "10")
        if app.buttons["Fine"].exists { app.buttons["Fine"].tap() }
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let reserve = row("Riserva per imprevisti", in: app)
        XCTAssertTrue(reserve.label.contains("7,50"))
        app.segmentedControls["monthly-safety-mode"].buttons["Importo fisso"].tap()
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        input.typeText(XCUIKeyboardKey.delete.rawValue + "100")
        if app.buttons["Fine"].exists { app.buttons["Fine"].tap() }
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertTrue(reserve.label.contains("100,00"))
        for _ in 0..<5 where !app.buttons["monthly-forecast-account-Cointestato"].isHittable { app.swipeDown() }
        XCTAssertTrue(row("Totale ancora necessario", in: app).label.contains("175,00"))
        app.buttons["monthly-forecast-account-Crédit Agricole"].tap()
        app.buttons["monthly-forecast-account-Cointestato"].tap()
        XCTAssertTrue(row("Totale ancora necessario", in: app).label.contains("175,00"))
    }

    @MainActor
    func testKnownCommitmentsAreDefaultAndEstimateIsAnExplicitChoice() {
        continueAfterFailure = false
        let app = launch()
        let total = row("Totale ancora necessario", in: app)
        XCTAssertTrue(total.label.contains("75,00"))
        let include = app.switches["monthly-forecast-include-variables"]
        enableVariables(in: app)
        for _ in 0..<6 where !total.isHittable { app.swipeDown() }
        XCTAssertTrue(total.label.contains("90,00"))
        for _ in 0..<6 where !include.isHittable { app.swipeUp() }
        if include.frame.maxY > app.frame.maxY - 120 { app.swipeUp() }
        include.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(include.value as? String, "0")
        for _ in 0..<6 where !total.isHittable { app.swipeDown() }
        XCTAssertTrue(total.label.contains("75,00"))
    }

    @MainActor
    func testContoBudgetReplacesHistoryWithoutCountingScheduledExpensesTwice() {
        continueAfterFailure = false
        let app = launch(extra: ["UITEST_FORECAST_BUDGET"])
        enableVariables(in: app)
        let total = row("Totale ancora necessario", in: app)
        for _ in 0..<6 where !total.isHittable { app.swipeDown() }
        XCTAssertTrue(total.label.contains("150,00"), total.label)
        let categories = app.buttons["monthly-forecast-categories"]
        for _ in 0..<6 where !categories.isHittable { app.swipeUp() }
        categories.tap()
        let budget = app.switches["monthly-forecast-category-Spesa di casa"]
        for _ in 0..<6 where !budget.isHittable { app.swipeUp() }
        XCTAssertTrue(budget.isHittable)
        XCTAssertFalse(app.switches["monthly-forecast-category-Alimentari"].exists)
        budget.tap()
        for _ in 0..<6 where !total.isHittable { app.swipeDown() }
        XCTAssertTrue(total.label.contains("75,00"))
    }

    @MainActor
    func testHabitualCategorySelectionChangesOnlyTheEstimate() {
        continueAfterFailure = false
        let app = launch()
        enableVariables(in: app)
        let categories = row("Categorie da includere", in: app)
        for _ in 0..<6 where !categories.isHittable { app.swipeUp() }
        categories.tap()
        let food = app.switches["monthly-forecast-category-Alimentari"]
        for _ in 0..<6 where !food.isHittable { app.swipeUp() }
        XCTAssertTrue(food.isHittable)
        XCTAssertTrue(row("Media mensile nello storico", in: app).label.contains("60,00"))
        food.tap()
        let total = row("Totale ancora necessario", in: app)
        for _ in 0..<6 where !total.isHittable { app.swipeDown() }
        XCTAssertTrue(total.label.contains("75,00"))
        for _ in 0..<6 where !food.isHittable { app.swipeUp() }
        food.tap()
        for _ in 0..<6 where !total.isHittable { app.swipeDown() }
        XCTAssertTrue(total.label.contains("90,00"))
    }

    @MainActor
    func testFundingSplitSharesUpdateWithReserveAndStayWithTheAccount() {
        continueAfterFailure = false
        let app = launch(extra: ["UITEST_FORECAST_SPLIT"])
        let first = app.descendants(matching: .any).matching(identifier: "monthly-funding-first").firstMatch
        let second = app.descendants(matching: .any).matching(identifier: "monthly-funding-second").firstMatch
        for _ in 0..<8 where !first.isHittable { app.swipeUp() }
        XCTAssertTrue(first.label.contains("Anna"))
        XCTAssertTrue(first.label.contains("37,50"))
        XCTAssertTrue(second.label.contains("37,50"))
        app.segmentedControls["monthly-funding-split-mode"].buttons["Quote diverse"].tap()
        let percentage = app.textFields["monthly-funding-split-percentage"]
        percentage.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).doubleTap()
        percentage.typeText("60")
        if app.buttons["Fine"].exists { app.buttons["Fine"].tap() }
        XCTAssertTrue(first.label.contains("45,00"))
        XCTAssertTrue(second.label.contains("30,00"))
        let fixed = app.segmentedControls["monthly-safety-mode"].buttons["Importo fisso"]
        for _ in 0..<8 where !fixed.isHittable { app.swipeUp() }
        fixed.tap()
        let reserve = app.textFields["monthly-safety-value"]
        reserve.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        reserve.typeText(XCUIKeyboardKey.delete.rawValue + "100")
        if app.buttons["Fine"].exists { app.buttons["Fine"].tap() }
        XCTAssertTrue(first.label.contains("105,00"))
        XCTAssertTrue(second.label.contains("70,00"))
        for _ in 0..<10 where !app.buttons["monthly-forecast-account-Crédit Agricole"].isHittable { app.swipeDown() }
        app.buttons["monthly-forecast-account-Crédit Agricole"].tap()
        XCTAssertFalse(first.exists)
        app.buttons["monthly-forecast-account-Cointestato"].tap()
        XCTAssertTrue(first.label.contains("105,00"))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Ripartizione dei versamenti con quote personalizzate"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testDarkLargeTextKeepsSummaryAndDetailsReachable() {
        continueAfterFailure = false
        let app = launch(dark: true, large: true)
        let total = row("Totale ancora necessario", in: app)
        for _ in 0..<5 where !total.isHittable { app.swipeUp() }
        XCTAssertTrue(total.isHittable)
        total.tap()
        XCTAssertTrue(app.navigationBars["Totale ancora necessario"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Previsione dark con testo accessibilità e animazioni disattivate"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

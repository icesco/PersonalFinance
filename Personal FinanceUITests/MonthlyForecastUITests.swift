import XCTest

final class MonthlyForecastUITests: XCTestCase {
    @MainActor
    private func launch(dark: Bool = false, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_MONTHLY_FORECAST", "-CloudSyncEnabled", "NO",
                               "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        if dark { app.launchArguments += ["UITEST_VISUAL_DARK", "UITEST_FORECAST_REDUCE_MOTION"] }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["monthly-forecast-account-Cointestato"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    private func row(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    @MainActor
    func testAccountSelectionDetailsAndMonthRules() {
        continueAfterFailure = false
        let app = launch()
        let expectedMonth = Date().formatted(.dateTime.month(.wide).locale(Locale(identifier: "it_IT")))
        XCTAssertTrue(app.staticTexts["monthly-forecast-month"].label.localizedCaseInsensitiveContains(expectedMonth))
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
        let occasional = row("Occasionali programmate da pagare", in: app)
        for _ in 0..<6 where !occasional.isHittable { app.swipeUp() }
        row("Occasionali programmate da pagare", in: app).tap()
        XCTAssertTrue(app.staticTexts["Consulto programmato"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Acquisto programmato"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        for _ in 0..<6 where !app.buttons["monthly-forecast-previous"].isHittable { app.swipeDown() }
        app.buttons["monthly-forecast-previous"].tap()
        XCTAssertTrue(app.staticTexts["Consuntivo del mese"].exists)
        XCTAssertFalse(row("Totale ancora necessario", in: app).exists)
        app.buttons["monthly-forecast-next"].tap()
        app.buttons["monthly-forecast-next"].tap()
        XCTAssertTrue(row("Totale ancora necessario", in: app).exists)
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
        app.buttons["Fine"].tap()
        let reserve = row("Riserva per imprevisti", in: app)
        XCTAssertTrue(reserve.label.contains("9,00"))
        app.segmentedControls["monthly-safety-mode"].buttons["Importo fisso"].tap()
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        input.typeText(XCUIKeyboardKey.delete.rawValue + "100")
        app.buttons["Fine"].tap()
        XCTAssertTrue(reserve.label.contains("100,00"))
        for _ in 0..<5 where !app.buttons["monthly-forecast-account-Cointestato"].isHittable { app.swipeDown() }
        XCTAssertTrue(row("Totale ancora necessario", in: app).label.contains("190,00"))
        app.buttons["monthly-forecast-account-Crédit Agricole"].tap()
        app.buttons["monthly-forecast-account-Cointestato"].tap()
        XCTAssertTrue(row("Totale ancora necessario", in: app).label.contains("190,00"))
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

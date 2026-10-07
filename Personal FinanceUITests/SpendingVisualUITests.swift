import XCTest

final class SpendingVisualUITests: XCTestCase {
    @MainActor
    func testTimelineDayHeaderStaysPinned() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FINANCE_CALENDAR", "UITEST_TIMELINE_PINNING", "-CloudSyncEnabled", "NO", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        let timeline = app.segmentedControls["finance-calendar-mode"].buttons["Timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 10))
        timeline.tap()
        scrollTo(app.staticTexts["Movimento illustrativo 6"], in: app)
        let header = app.descendants(matching: .any).matching(identifier: "finance-timeline-pinned-header-3").firstMatch
        XCTAssertTrue(header.exists)
        let firstY = header.frame.minY
        XCTAssertLessThanOrEqual(firstY, app.navigationBars.firstMatch.frame.maxY + 25)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.70))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.62))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertEqual(header.frame.minY, firstY, accuracy: 3)
        capture(app, "formi-timeline-pinned-day")
    }

    @MainActor
    func testSavingsGaugeSignedValues() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_SAVINGS_GAUGE", "-CloudSyncEnabled", "NO", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        XCTAssertTrue(app.buttons["Deficit"].waitForExistence(timeout: 10))
        capture(app, "formi-savings-gauge")
        app.buttons["Deficit"].tap()
        XCTAssertTrue(app.staticTexts["Spese oltre le entrate"].waitForExistence(timeout: 5))
        capture(app, "formi-savings-gauge-deficit")
        app.buttons["Correzione"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "125")).firstMatch.waitForExistence(timeout: 5))
        capture(app, "formi-savings-gauge-correction")
    }

    @MainActor
    func testAnalysisChartsAndExplanation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-CloudSyncEnabled", "NO", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        if app.buttons["Esplora con dati demo"].waitForExistence(timeout: 4) {
            app.buttons["Esplora con dati demo"].tap()
        }
        XCTAssertTrue(app.tabBars.buttons["Analisi"].waitForExistence(timeout: 15))
        capture(app, "formi-brim-home")
        app.tabBars.buttons["Analisi"].tap()
        let trendPreview = app.buttons["analysis-trend-preview"]
        let savingsPreview = app.buttons["analysis-savings-preview"]
        let balancePreview = app.buttons["analysis-balance-preview"]
        XCTAssertTrue(trendPreview.waitForExistence(timeout: 10))
        XCTAssertTrue(savingsPreview.exists)
        XCTAssertTrue(balancePreview.exists)
        XCTAssertFalse(app.buttons["Come leggere il grafico"].exists)
        capture(app, "formi-analysis-previews")
        trendPreview.tap()
        XCTAssertTrue(app.navigationBars["Andamento delle spese"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ottobre 2026"].exists)
        capture(app, "formi-analysis-trend-detail")
        let explanation = app.buttons["Come leggere il grafico"]
        scrollTo(explanation, in: app)
        explanation.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Le linee sommano")).firstMatch.exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(savingsPreview.waitForExistence(timeout: 5))
        savingsPreview.tap()
        XCTAssertTrue(app.navigationBars["Tasso di risparmio"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Non calcolabile"].exists)
        let savingsGuide = app.buttons["analysis-savings-explanation"]
        scrollTo(savingsGuide, in: app)
        savingsGuide.tap()
        XCTAssertTrue(app.staticTexts["Quanto resta delle tue entrate"].waitForExistence(timeout: 5))
        app.buttons["Fine"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Periodo precedente"].tap()
        savingsPreview.tap()
        XCTAssertTrue(app.staticTexts["settembre 2026"].waitForExistence(timeout: 5))
        capture(app, "formi-analysis-savings-detail")
        app.navigationBars.buttons.firstMatch.tap()
        scrollTo(balancePreview, in: app)
        balancePreview.tap()
        XCTAssertTrue(app.navigationBars["Saldo per conto"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["analysis-balance-history"].exists)
        capture(app, "formi-analysis-balance-detail")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(trendPreview.waitForExistence(timeout: 5))
    }

    @MainActor
    func testMarginWithIsolatedIllustrativeData() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_MARGIN_VISUAL", "-CloudSyncEnabled", "NO", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        let preview = app.buttons["today-margin-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        capture(app, "formi-home-margin-preview")
        preview.tap()
        XCTAssertTrue(app.staticTexts["Margine stimato"].waitForExistence(timeout: 10))
        capture(app, "formi-brim-margin-example")
        app.buttons["Come è calcolato quanto puoi ancora spendere"].tap()
        XCTAssertTrue(app.staticTexts["Un margine, non una promessa"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCalendarSelectionTimelineAndMonthNavigation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FINANCE_CALENDAR", "-CloudSyncEnabled", "NO", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        XCTAssertTrue(app.buttons["finance-calendar-day-3"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Ottobre 2026"].exists)
        capture(app, "formi-calendar-month")
        app.buttons["finance-calendar-day-3"].firstMatch.tap()
        let expense = app.staticTexts["Spesa illustrativa"]
        scrollTo(expense, in: app)
        capture(app, "formi-calendar-selected-day")
        app.scrollViews.firstMatch.swipeDown()
        app.scrollViews.firstMatch.swipeDown()
        app.segmentedControls["finance-calendar-mode"].buttons["Timeline"].tap()
        let future = app.staticTexts["Scadenza illustrativa"]
        scrollTo(future, in: app)
        capture(app, "formi-calendar-timeline")
        app.scrollViews.firstMatch.swipeDown()
        app.scrollViews.firstMatch.swipeDown()
        app.buttons["Mese successivo"].tap()
        XCTAssertTrue(app.buttons["finance-calendar-today"].exists)
        app.buttons["finance-calendar-today"].tap()
        app.segmentedControls["finance-calendar-mode"].buttons["Calendario"].tap()
        XCTAssertTrue(app.buttons["finance-calendar-day-3"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<14 {
            if element.exists && element.isHittable { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.78))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.55))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        capture(app, "formi-brim-scroll-diagnostic")
        XCTAssertTrue(element.exists && element.isHittable)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/private/tmp/\(name).png"))
    }
}

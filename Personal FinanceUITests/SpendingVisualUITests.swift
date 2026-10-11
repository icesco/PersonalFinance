import XCTest

final class SpendingVisualUITests: XCTestCase {
    @MainActor
    func testMoneyFlowRibbonDrillDown() throws {
        try verifyMoneyFlowDrillDown(dark: false)
    }

    @MainActor
    func testMoneyFlowRibbonDrillDownDark() throws {
        try verifyMoneyFlowDrillDown(dark: true)
    }

    @MainActor
    func testMoneyFlowReducedMotion() throws {
        try verifyMoneyFlowDrillDown(dark: false, reduceMotion: true)
    }

    @MainActor
    func testMoneyFlowCategoryIsolationFromList() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_MONEY_FLOW", "-CloudSyncEnabled", "NO",
                               "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        let homeRow = app.buttons["money-flow-category-Casa"]
        XCTAssertTrue(homeRow.waitForExistence(timeout: 10))
        scrollTo(homeRow, in: app)
        homeRow.tap()
        let title = app.staticTexts["money-flow-focus-name"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Casa")
        XCTAssertFalse(app.buttons["money-flow-node-Cibo"].exists)
        XCTAssertFalse(app.buttons["money-flow-node-Da classificare"].exists)
        XCTAssertTrue(app.buttons["money-flow-node-Affitto"].exists)
        XCTAssertTrue(app.buttons["money-flow-node-Utenze"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.8))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.4)))
        XCTAssertTrue(app.buttons["money-flow-back"].isHittable)
        XCTAssertTrue(app.buttons["Panoramica"].isHittable)
        app.buttons["Panoramica"].tap()
        XCTAssertFalse(title.exists)
        XCTAssertTrue(app.buttons["money-flow-node-Casa"].exists)
        XCTAssertTrue(app.buttons["money-flow-node-Cibo"].exists)
        XCTAssertTrue(app.buttons["money-flow-node-Da classificare"].exists)
    }

    @MainActor
    private func verifyMoneyFlowDrillDown(dark: Bool, reduceMotion: Bool = false) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_MONEY_FLOW", "-CloudSyncEnabled", "NO",
                               "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        if dark { app.launchArguments.append("UITEST_VISUAL_DARK") }
        if reduceMotion { app.launchArguments.append("UITEST_MONEY_FLOW_REDUCE_MOTION") }
        app.launch()
        let home = app.buttons["money-flow-node-Casa"]
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        scrollTo(home, in: app)
        capture(app, "formi-money-flow-overview-\(dark ? "dark" : "light")")
        // Tap the actual ribbon just before its destination, outside the label.
        home.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: -42, dy: 0)).tap()
        capture(app, "formi-money-flow-after-ribbon-tap-\(dark ? "dark" : "light")")
        let title = app.staticTexts["money-flow-focus-name"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Casa")
        XCTAssertTrue(title.isHittable)
        XCTAssertFalse(app.buttons["Aumenta zoom"].exists)
        XCTAssertTrue(app.buttons["money-flow-node-Affitto"].exists)
        capture(app, "formi-money-flow-casa-\(dark ? "dark" : "light")")
        XCTAssertGreaterThanOrEqual(title.frame.minY, app.buttons["money-flow-back"].frame.maxY)
        let rent = app.buttons["money-flow-node-Affitto"]
        scrollTo(rent, in: app)
        rent.tap()
        XCTAssertEqual(title.label, "Affitto")
        XCTAssertEqual(app.buttons["money-flow-back"].label, "Torna a Casa")
        XCTAssertTrue(app.buttons["Vedi movimenti"].exists)
        app.buttons["Vedi movimenti"].tap()
        XCTAssertTrue(app.navigationBars["Affitto"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertEqual(title.label, "Affitto")
        app.buttons["money-flow-back"].tap()
        XCTAssertEqual(title.label, "Casa")
        app.buttons["Panoramica"].tap()
        XCTAssertFalse(title.exists)
        scrollTo(home, in: app)
        home.tap()
        let direct = app.buttons["money-flow-node-Direttamente nella categoria"]
        scrollTo(direct, in: app)
        direct.tap()
        XCTAssertEqual(title.label, "Direttamente nella categoria")
        XCTAssertFalse(app.buttons["Vedi movimenti"].exists)
        app.buttons["Panoramica"].tap()
        let uncategorized = app.buttons["money-flow-node-Da classificare"]
        scrollTo(uncategorized, in: app)
        uncategorized.tap()
        XCTAssertEqual(title.label, "Da classificare")
        XCTAssertFalse(app.buttons["Vedi movimenti"].exists)
        app.buttons["Panoramica"].tap()
        let food = app.buttons["money-flow-node-Cibo"]
        scrollTo(food, in: app)
        food.tap()
        XCTAssertEqual(title.label, "Cibo")
        let coffee = app.buttons["money-flow-node-Bar e caffè"]
        scrollTo(coffee, in: app)
        coffee.tap()
        XCTAssertEqual(title.label, "Bar e caffè")
        XCTAssertTrue(app.buttons["money-flow-back"].isHittable)
        XCTAssertTrue(app.buttons["Panoramica"].isHittable)
        capture(app, "formi-money-flow-leaf-\(dark ? "dark" : "light")")
        app.buttons["money-flow-back"].tap()
        XCTAssertEqual(title.label, "Cibo")
        app.buttons["Panoramica"].tap()
        XCTAssertFalse(title.exists)
    }

    @MainActor
    func testTimelineDayHeaderStaysPinned() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FINANCE_CALENDAR", "UITEST_TIMELINE_PINNING", "-CloudSyncEnabled", "NO", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        let timeline = app.segmentedControls["finance-calendar-mode"].buttons["Timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 10))
        timeline.tap()
        app.buttons["Mese successivo"].tap()
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
        let dayDetail = app.descendants(matching: .any)["spending-trend-day-detail"]
        scrollTo(dayDetail, in: app)
        let day = Calendar.current.component(.day, from: Date())
        let selectedDay = app.buttons["spending-trend-day-\(day)"]
        XCTAssertTrue(selectedDay.exists)
        selectedDay.tap()
        XCTAssertTrue(dayDetail.label.contains("Giorno \(day)"))
        let previousDay = app.buttons["spending-trend-day-\(max(1, day - 1))"]
        previousDay.tap()
        XCTAssertTrue(dayDetail.label.contains("Giorno \(max(1, day - 1))"))
        capture(app, "formi-analysis-selected-day")
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
        XCTAssertTrue(app.staticTexts["Dai un significato ai numeri"].waitForExistence(timeout: 5))
        app.buttons["Chiudi"].tap()
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
    func testMarginDarkWithLargeText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_MARGIN_VISUAL", "UITEST_VISUAL_DARK", "UITEST_VISUAL_LARGE_TEXT",
                               "-CloudSyncEnabled", "NO", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        let preview = app.buttons["today-margin-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(preview.frame.maxX, app.frame.maxX)
        capture(app, "formi-home-margin-dark-large-text")
        preview.tap()
        XCTAssertTrue(app.staticTexts["Margine stimato"].waitForExistence(timeout: 10))
        capture(app, "formi-margin-dark-large-text")
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
        XCTAssertFalse(expense.exists)
        XCTAssertFalse(app.staticTexts["Registrate"].exists)
        capture(app, "formi-calendar-timeline")
        app.scrollViews.firstMatch.swipeDown()
        app.scrollViews.firstMatch.swipeDown()
        app.buttons["Mese precedente"].tap()
        XCTAssertTrue(app.staticTexts["Nessuna spesa futura nel mese"].waitForExistence(timeout: 5))
        app.buttons["finance-calendar-today"].tap()
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

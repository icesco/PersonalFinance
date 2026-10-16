import XCTest

final class MovementHeatmapUITests: XCTestCase {
    @MainActor
    func testPreviewAccountScopeDaysAndTransactionNavigation() throws {
        try verify(dark: false)
    }

    @MainActor
    func testHeatmapDarkAppearance() throws {
        try verify(dark: true)
    }

    @MainActor
    private func verify(dark: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FINANCE_CALENDAR", "UITEST_MOVEMENT_HEATMAP", "-CloudSyncEnabled", "NO",
                               "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        if dark { app.launchArguments += ["UITEST_VISUAL_DARK"] }
        app.launch()
        let preview = app.buttons["analysis-heatmap-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Anteprima del calendario"), evaluatedWith: preview)
        waitForExpectations(timeout: 10)
        let previewImage = XCTAttachment(screenshot: app.screenshot())
        previewImage.name = dark ? "Heatmap preview dark" : "Heatmap preview light"
        previewImage.lifetime = .keepAlways; add(previewImage)
        preview.tap()
        let total = app.staticTexts["heatmap-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        XCTAssertTrue(total.label.contains("836,50"), total.label)
        let mode = app.segmentedControls["heatmap-mode"]
        mode.buttons["Entrate"].tap()
        XCTAssertTrue(total.label.replacingOccurrences(of: ".", with: "").contains("2525,00"), total.label)
        mode.buttons["Netto"].tap()
        XCTAssertTrue(total.label.replacingOccurrences(of: ".", with: "").contains("1688,50"), total.label)
        let balanced = app.buttons["heatmap-day-8"]
        balanced.tap()
        for _ in 0..<3 {
            if app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'heatmap-entry-' AND label CONTAINS 'Acquisto illustrativo'")).firstMatch.isHittable { break }
            app.swipeUp()
        }
        let movement = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'heatmap-entry-' AND label CONTAINS 'Acquisto illustrativo'")).firstMatch
        XCTAssertTrue(movement.waitForExistence(timeout: 5), app.debugDescription)
        movement.tap()
        XCTAssertTrue(app.navigationBars["Dettaglio"].waitForExistence(timeout: 5))
        app.navigationBars["Dettaglio"].buttons["BackButton"].tap()
        for _ in 0..<4 {
            if app.buttons["heatmap-account-picker"].isHittable { break }
            app.swipeDown()
        }
        app.buttons["heatmap-account-picker"].tap()
        app.buttons["Riserva"].tap()
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        XCTAssertTrue(total.label.contains("0,00"), total.label)
        app.buttons["heatmap-day-12"].tap()
        for _ in 0..<3 {
            if app.staticTexts["Trasferimento escluso dai totali"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["Trasferimento escluso dai totali"].exists, app.debugDescription)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = dark ? "Heatmap detail dark" : "Heatmap detail light"
        attachment.lifetime = .keepAlways; add(attachment)
        for _ in 0..<4 {
            if app.buttons["heatmap-account-picker"].isHittable { break }
            app.swipeDown()
        }
        app.buttons["heatmap-account-picker"].tap()
        app.buttons["Cointestato"].tap()
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        XCTAssertTrue(total.label.contains("107,00"), total.label)
        app.buttons["heatmap-account-picker"].tap()
        app.buttons["Tutti i conti inclusi"].tap()
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        XCTAssertTrue(total.label.replacingOccurrences(of: ".", with: "").contains("1688,50"), total.label)
        app.buttons["heatmap-previous-month"].tap()
        XCTAssertTrue(app.staticTexts["heatmap-empty-month"].waitForExistence(timeout: 10))
        app.buttons["heatmap-next-month"].tap()
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        app.buttons["heatmap-day-10"].tap()
        for _ in 0..<3 {
            if app.staticTexts["Nessun movimento registrato in questo giorno per i conti selezionati."].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["Nessun movimento registrato in questo giorno per i conti selezionati."].exists)
    }
}

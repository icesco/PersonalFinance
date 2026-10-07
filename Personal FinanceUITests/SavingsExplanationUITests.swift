import XCTest

final class SavingsExplanationUITests: XCTestCase {
    @MainActor
    func testSavingsExplanationAndManualPlanning() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-CloudSyncEnabled", "NO", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        let demo = app.buttons["Esplora con dati demo"]
        if demo.waitForExistence(timeout: 5) { demo.tap() }
        let planning = app.tabBars.buttons["Pianifica"]
        XCTAssertTrue(planning.waitForExistence(timeout: 20))
        planning.tap()
        if app.buttons["Tutti i libri"].exists {
            app.buttons["Tutti i libri"].tap()
            XCTAssertTrue(app.buttons["Demo"].waitForExistence(timeout: 5))
            app.buttons["Demo"].tap()
        }
        let explanation = app.buttons["planning-savings-guides"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 10))
        explanation.tap()
        XCTAssertTrue(app.staticTexts["Dai un significato ai numeri"].waitForExistence(timeout: 5))
        capture(app, "formi-charts-explanation-top")
        scrollUntilHittable(app.staticTexts["Un esempio con il 50/30/20"], in: app)
        capture(app, "formi-charts-distribution")
        scrollUntilHittable(app.staticTexts["Un esempio di movimenti registrati"], in: app)
        capture(app, "formi-charts-transfer-example")
        scrollUntilHittable(app.buttons["Guide e approfondimenti"], in: app)
        app.buttons["Guide e approfondimenti"].tap()
        XCTAssertTrue(app.staticTexts["Budget e risparmio"].waitForExistence(timeout: 5))
        capture(app, "formi-charts-guides")
        app.buttons["Chiudi"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Come funziona il risparmio"].waitForExistence(timeout: 5))
        app.buttons["Chiudi"].tap()
        app.buttons["planning-discover-methods"].tap()
        XCTAssertTrue(app.staticTexts["Come vuoi organizzarti?"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Dai un significato ai numeri"].exists)
        capture(app, "formi-charts-method-step")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Gestione manuale")).firstMatch.tap()
        app.buttons["budgeting-continue"].tap()
        XCTAssertTrue(app.staticTexts["Come misuriamo gli accantonamenti?"].waitForExistence(timeout: 5))
        app.buttons["budgeting-continue"].tap()
        XCTAssertTrue(app.staticTexts["Il tuo piano, prima di applicarlo"].waitForExistence(timeout: 5))
        app.buttons["budgeting-continue"].tap()
        XCTAssertTrue(app.buttons["planning-edit-method"].waitForExistence(timeout: 5))
        capture(app, "formi-charts-manual-result")
        app.tabBars.buttons["Analisi"].tap()
        scrollUntilHittable(app.buttons["analysis-savings-preview"], in: app)
        app.buttons["analysis-savings-preview"].tap()
        scrollUntilHittable(app.buttons["analysis-savings-explanation"], in: app)
        XCTAssertTrue(app.staticTexts["Tasso di risparmio"].exists)
        capture(app, "formi-charts-analysis")
        app.buttons["analysis-savings-explanation"].tap()
        XCTAssertTrue(app.staticTexts["Dai un significato ai numeri"].waitForExistence(timeout: 5))
        app.buttons["Chiudi"].tap()
    }

    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
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

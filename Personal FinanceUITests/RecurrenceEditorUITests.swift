import XCTest

final class RecurrenceEditorUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testQuickEntrySavesFrequencyAndInclusiveEndDate() {
        verifyQuickEntry(hasEndDate: true)
    }

    @MainActor
    func testQuickEntryCanReturnToNeverEnding() {
        verifyQuickEntry(hasEndDate: false)
    }

    @MainActor
    private func verifyQuickEntry(hasEndDate: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_QUICK_TRANSFER", "-CloudSyncEnabled", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["quick-type-transfer"].waitForExistence(timeout: 15))
        app.buttons["quick-type-transfer"].tap()
        app.buttons["Dal conto"].tap()
        app.buttons["Corrente"].tap()
        app.buttons["Al conto"].tap()
        app.buttons["Risparmio"].tap()
        let amount = app.textFields["Importo"]
        amount.tap()
        amount.typeText("10")
        app.buttons["quick-type-transfer"].tap()

        let save = app.buttons["Salva trasferimento"]
        let recurring = app.switches["Transazione ricorrente"]
        reveal(recurring, above: save, in: app)
        recurring.tap()
        let cadence = app.buttons["recurrence-frequency"]
        reveal(cadence, above: save, in: app)
        cadence.tap()
        let frequency = app.buttons["recurrence-frequency-quarterly"]
        if !frequency.isHittable { app.swipeUp() }
        XCTAssertTrue(frequency.waitForExistence(timeout: 5))
        frequency.tap()
        XCTAssertTrue(cadence.waitForExistence(timeout: 5))
        XCTAssertTrue(cadence.label.contains("Trimestrale"))

        let endMode = app.segmentedControls["recurrence-end-mode"]
        reveal(endMode, above: save, in: app)
        endMode.buttons["In una data"].tap()
        XCTAssertTrue(app.datePickers["recurrence-end-date"].exists)
        if !hasEndDate { endMode.buttons["Mai"].tap() }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = hasEndDate ? "Ricorrenza con fine" : "Ricorrenza senza fine"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(save.isEnabled)
        save.tap()
        let savedFrequency = app.staticTexts["recurrence-saved-frequency"]
        XCTAssertTrue(savedFrequency.waitForExistence(timeout: 10))
        XCTAssertEqual(savedFrequency.label, "quarterly")
        XCTAssertEqual(app.staticTexts["recurrence-saved-end"].label, hasEndDate ? "Con data" : "Mai")
        if hasEndDate {
            XCTAssertEqual(app.staticTexts["recurrence-saved-inclusive-end"].label, "Giorno incluso")
        }
    }

    @MainActor
    private func reveal(_ element: XCUIElement, above save: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable && element.frame.maxY < save.frame.minY { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}

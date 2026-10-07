import XCTest

final class QuickTransferUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testTransferAlongsideExpenseAndIncomeSavesBothAccounts() {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_QUICK_TRANSFER", "-CloudSyncEnabled", "NO"]
        app.launch()
        let transfer = app.buttons["quick-type-transfer"]
        XCTAssertTrue(transfer.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["quick-type-expense"].exists)
        XCTAssertTrue(app.buttons["quick-type-income"].exists)
        transfer.tap()
        XCTAssertTrue(app.buttons["Dal conto"].exists)
        XCTAssertTrue(app.buttons["Al conto"].exists)
        XCTAssertFalse(app.buttons["Categoria"].exists)

        app.buttons["Dal conto"].tap()
        app.buttons["Corrente"].tap()
        app.buttons["Al conto"].tap()
        XCTAssertFalse(app.buttons["Corrente"].exists)
        app.buttons["Risparmio"].tap()
        let amount = app.textFields["Importo"]
        amount.tap()
        amount.typeText("75")
        let save = app.buttons["Salva trasferimento"]
        XCTAssertTrue(save.isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Spesa Entrata Trasferimento"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        save.tap()
        XCTAssertTrue(app.staticTexts["transfer-saved-route"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["transfer-saved-route"].label, "transfer: Corrente → Risparmio")
        XCTAssertEqual(app.staticTexts["transfer-saved-amount"].label, "75")
        XCTAssertTrue(app.staticTexts["Senza categoria"].exists)
        XCTAssertTrue(app.staticTexts["Corrente: 425"].exists)
        XCTAssertTrue(app.staticTexts["Risparmio: 175"].exists)
    }

    @MainActor
    func testTransferStaysVisibleWithOnlyOneAccountAndCanSwitchBack() {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_QUICK_EXPENSE_BUDGET", "-CloudSyncEnabled", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["quick-type-transfer"].waitForExistence(timeout: 15))
        app.buttons["quick-type-transfer"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Per un trasferimento servono almeno due conti")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Salva trasferimento"].isEnabled)
        app.buttons["quick-type-income"].tap()
        XCTAssertTrue(app.buttons["Categoria"].exists)
        XCTAssertFalse(app.buttons["Al conto"].exists)
        XCTAssertTrue(app.buttons["Salva entrata"].exists)
        app.buttons["quick-type-expense"].tap()
        XCTAssertTrue(app.buttons["Salva spesa"].exists)
    }
}

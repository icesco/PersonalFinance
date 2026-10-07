import XCTest

final class BookSelectionUITests: XCTestCase {
    @MainActor
    func testSelectingSingleBookAndAllBooksDismissesPicker() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_CURRENCY_SELECTION", "-CloudSyncEnabled", "NO", "-AppLockEnabled", "NO"]
        app.launch()

        func book(_ name: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
        }

        XCTAssertTrue(book("Personale").waitForExistence(timeout: 15))
        XCTAssertTrue(book("Personale").isSelected)
        XCTAssertTrue(book("Viaggi").isHittable)
        book("Famiglia").tap()
        XCTAssertTrue(app.staticTexts["Famiglia"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["I tuoi libri"].exists)

        app.buttons["Cambia libro"].tap()
        XCTAssertTrue(book("Famiglia").waitForExistence(timeout: 5))
        XCTAssertTrue(book("Famiglia").isSelected)
        book("Tutti i libri").tap()
        XCTAssertTrue(app.staticTexts["Tutti i libri"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["I tuoi libri"].exists)

        app.buttons["Cambia libro"].tap()
        XCTAssertTrue(book("Tutti i libri").waitForExistence(timeout: 5))
        XCTAssertTrue(book("Tutti i libri").isSelected)
        XCTAssertFalse(book("Famiglia").isSelected)
        app.buttons["Chiudi"].tap()
        XCTAssertFalse(app.staticTexts["I tuoi libri"].exists)
    }

    @MainActor
    func testHomeBookSourceRemainsUsableAfterZoomDismissal() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_CURRENCY_SELECTION", "UITEST_BOOK_ZOOM", "-CloudSyncEnabled", "NO", "-AppLockEnabled", "NO"]
        app.launch()
        for name in ["Famiglia", "Personale", "Viaggi"] {
            let source = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Scegli libro:")).firstMatch
            XCTAssertTrue(source.waitForExistence(timeout: 15))
            XCTAssertTrue(source.isHittable)
            source.tap()
            let book = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
            XCTAssertTrue(book.waitForExistence(timeout: 5))
            book.tap()
            let updatedSource = app.buttons["Scegli libro: \(name)"]
            XCTAssertTrue(updatedSource.waitForExistence(timeout: 5))
            XCTAssertTrue(updatedSource.isHittable)
            XCTAssertFalse(app.staticTexts["I tuoi libri"].exists)
        }
        app.buttons["Scegli libro: Viaggi"].tap()
        XCTAssertTrue(app.buttons["Chiudi"].waitForExistence(timeout: 5))
        app.buttons["Chiudi"].tap()
        XCTAssertTrue(app.buttons["Scegli libro: Viaggi"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Scegli libro: Viaggi"].isHittable)
    }

}

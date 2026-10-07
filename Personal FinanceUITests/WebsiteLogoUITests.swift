import XCTest

final class WebsiteLogoUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testFreeLogoSearchBackgroundSaveAndCancel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_MAC_LOCAL", "-CloudSyncEnabled", "NO", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        if app.buttons["Esplora con dati demo"].waitForExistence(timeout: 3) {
            app.buttons["Esplora con dati demo"].tap()
        }
        let planning = app.tabBars.buttons["Pianifica"]
        XCTAssertTrue(planning.waitForExistence(timeout: 20))
        planning.tap()
        let chooseBook = app.buttons["Scegli un libro per gestire i budget"]
        if chooseBook.exists {
            chooseBook.tap()
            let book = app.buttons.containing(.staticText, identifier: "Demo").firstMatch
            XCTAssertTrue(book.waitForExistence(timeout: 5))
            book.tap()
        }
        let create = app.buttons["Nuovo conto"].firstMatch
        reveal(create, in: app)
        create.tap()
        let name = app.textFields["conto-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Revolut")
        let balance = app.textFields["conto-initial-balance"]
        balance.tap(); balance.typeText("0")
        let search = app.buttons["conto-logo-search"]
        reveal(search, in: app)
        search.tap()
        let brand = app.buttons["conto-logo-brand-www.revolut.com"]
        XCTAssertTrue(brand.waitForExistence(timeout: 5))
        brand.tap()
        let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Logo da ")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 35), "The official site should return a usable logo")
        result.tap()
        let background = app.switches["conto-logo-remove-background"]
        reveal(background, in: app, direction: .down)
        XCTAssertTrue(background.waitForExistence(timeout: 5))
        capture(app, name: "00 Anteprima prima della rimozione dello sfondo")
        // SwiftUI exposes the whole form row as a Switch. Tap the actual thumb at its trailing edge.
        background.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: background)
        waitForExpectations(timeout: 5)
        capture(app, name: "01 Logo Revolut con anteprima e sfondo rimosso")
        let apply = app.buttons["conto-logo-apply"]
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: apply)
        waitForExpectations(timeout: 5)
        apply.tap()
        XCTAssertTrue(app.buttons["conto-logo-remove"].waitForExistence(timeout: 5))
        capture(app, name: "02 Logo nel conto in creazione")
        app.buttons["conto-save"].tap()
        let row = app.buttons.containing(.staticText, identifier: "Revolut").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        reveal(row, in: app)
        capture(app, name: "03 Conto salvato con logo")
        row.press(forDuration: 1.2)
        let edit = app.buttons["Modifica conto"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let remove = app.buttons["conto-logo-remove"]
        reveal(remove, in: app)
        XCTAssertTrue(remove.exists, "Saved logo should be loaded into the edit form")
        remove.tap()
        XCTAssertFalse(app.buttons["conto-logo-remove"].exists)
        app.buttons["Annulla"].tap()
        reveal(row, in: app)
        row.press(forDuration: 1.2)
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        reveal(remove, in: app)
        XCTAssertTrue(remove.exists, "Cancel must retain the saved logo")
        capture(app, name: "04 Logo conservato dopo Annulla")
        app.buttons["Annulla"].tap()
    }

    private enum Direction { case up, down }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, direction: Direction = .up) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            if direction == .up { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Control must be reachable: \(element)")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

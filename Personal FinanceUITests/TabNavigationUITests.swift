import XCTest

final class TabNavigationUITests: XCTestCase {
    @MainActor func testCustomizationLight() { verifyCustomization(dark: false) }
    @MainActor func testCustomizationDark() { verifyCustomization(dark: true) }

    @MainActor func testBookSelectionLivesInSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_NAVIGATION", "-CloudSyncEnabled", "NO", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        XCTAssertTrue(app.buttons["navigation-settings"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Scegli libro:")).count, 0)
        capture(app, "book-readonly-home")
        app.tabBars.buttons["Pianifica"].tap()
        XCTAssertFalse(app.buttons["Demo"].exists)
        app.buttons["navigation-settings"].tap()
        let chooseBook = app.buttons["settings-book-selection"]
        XCTAssertTrue(chooseBook.waitForExistence(timeout: 5))
        capture(app, "book-selection-settings")
        chooseBook.tap()
        XCTAssertTrue(app.staticTexts["I tuoi libri"].waitForExistence(timeout: 5))
        let book = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Demo")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 5))
        book.tap()
        XCTAssertTrue(app.navigationBars["Impostazioni"].waitForExistence(timeout: 5))
        app.buttons["Chiudi"].tap()
        XCTAssertTrue(app.tabBars.buttons["Pianifica"].isSelected)
    }

    @MainActor func testSettingsAccessibleFromEveryTab() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_NAVIGATION", "-CloudSyncEnabled", "NO", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        XCTAssertTrue(app.buttons["navigation-settings"].waitForExistence(timeout: 20))
        for title in ["Oggi", "Movimenti", "Pianifica"] {
            app.tabBars.buttons[title].tap()
            verifySettingsReturn(to: title, app: app)
        }
        app.tabBars.buttons["Oggi"].tap()
        app.buttons["navigation-settings"].tap()
        tap("Personalizza tab", app: app)
        tap("Rimuovi Pianifica dalla barra", app: app)
        for title in ["Calendario", "Budget", "Conti"] { tap("Aggiungi \(title) alla barra", app: app) }
        app.buttons["Fine"].tap()
        app.buttons["Chiudi"].tap()
        for title in ["Calendario", "Budget", "Conti"] {
            app.tabBars.buttons[title].tap()
            verifySettingsReturn(to: title, app: app)
        }
        app.tabBars.buttons["Oggi"].tap()
        app.buttons["navigation-settings"].tap()
        tap("Personalizza tab", app: app)
        tap("Rimuovi Calendario dalla barra", app: app)
        tap("Aggiungi Analisi alla barra", app: app)
        app.buttons["Fine"].tap()
        app.buttons["Chiudi"].tap()
        app.tabBars.buttons["Analisi"].tap()
        verifySettingsReturn(to: "Analisi", app: app)
        capture(app, "settings-access-analysis")
    }

    @MainActor private func verifySettingsReturn(to title: String, app: XCUIApplication) {
        let settings = app.buttons["navigation-settings"]
        XCTAssertTrue(settings.isHittable)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Impostazioni"].waitForExistence(timeout: 5))
        app.buttons["Chiudi"].tap()
        XCTAssertTrue(app.tabBars.buttons[title].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons[title].isSelected)
    }

    @MainActor func testOptionalSectionsOpenAsIndependentTabs() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_NAVIGATION", "-CloudSyncEnabled", "NO", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        XCTAssertTrue(app.buttons["today-sections"].waitForExistence(timeout: 20))
        app.buttons["today-sections"].tap()
        app.buttons["Personalizza tab"].tap()
        tap("Rimuovi Pianifica dalla barra", app: app)
        for title in ["Calendario", "Budget", "Conti"] { tap("Aggiungi \(title) alla barra", app: app) }
        app.buttons["Fine"].tap()
        app.tabBars.buttons["Calendario"].tap()
        XCTAssertTrue(app.navigationBars["Calendario e timeline"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Budget"].tap()
        XCTAssertTrue(app.navigationBars["Budget"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Fine"].exists)
        app.tabBars.buttons["Conti"].tap()
        XCTAssertTrue(app.navigationBars["Conti"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Movimenti"].tap()
        XCTAssertTrue(app.tabBars.buttons["Movimenti"].isSelected)
        app.tabBars.buttons["Oggi"].tap()
        XCTAssertTrue(app.buttons["today-sections"].exists)
    }

    @MainActor private func verifyCustomization(dark: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_NAVIGATION", "-CloudSyncEnabled", "NO", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        if dark { app.launchArguments.append("UITEST_VISUAL_DARK") }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Pianifica"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.tabBars.buttons.count, 3)
        app.buttons["today-sections"].tap()
        app.buttons["Personalizza tab"].tap()
        XCTAssertTrue(app.navigationBars["Personalizza tab"].waitForExistence(timeout: 5))
        capture(app, "customization-\(dark ? "dark" : "light")")
        tap("Aggiungi Analisi alla barra", app: app)
        tap("Aggiungi Calendario alla barra", app: app)
        XCTAssertFalse(app.buttons["Aggiungi Budget alla barra"].isEnabled)
        tap("Sposta Calendario prima", app: app)
        tap("Rimuovi Pianifica dalla barra", app: app)
        app.buttons["Fine"].tap()
        XCTAssertTrue(app.tabBars.buttons["Analisi"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["Pianifica"].exists)
        XCTAssertEqual(app.tabBars.buttons.count, 4)
        app.buttons["today-sections"].tap()
        app.buttons["Pianifica"].tap()
        XCTAssertTrue(app.buttons["Chiudi"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Dai spazio ai tuoi progetti"].exists)
        app.buttons["Chiudi"].tap()
        app.buttons["today-sections"].tap()
        app.buttons["Impostazioni"].tap()
        XCTAssertTrue(app.navigationBars["Impostazioni"].waitForExistence(timeout: 5))
        tap("Personalizza tab", app: app)
        XCTAssertTrue(app.navigationBars["Personalizza tab"].waitForExistence(timeout: 5))
        tap("Ripristina Oggi, Movimenti e Pianifica", app: app)
        app.buttons["Fine"].tap()
        app.buttons["Chiudi"].tap()
        XCTAssertTrue(app.tabBars.buttons["Pianifica"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.buttons.count, 3)
        capture(app, "navigation-\(dark ? "dark" : "light")")
    }

    @MainActor private func tap(_ label: String, app: XCUIApplication) {
        let button = app.buttons[label]
        for _ in 0..<6 {
            if button.exists && button.isHittable { break }
            app.swipeUp()
        }
        for _ in 0..<6 {
            if button.exists && button.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(button.exists)
        button.tap()
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

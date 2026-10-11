import XCTest

final class MarginScenarioUITests: XCTestCase {
    @MainActor
    func testCompactMarginAndScenarioInputs() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_MARGIN_VISUAL", "-CloudSyncEnabled", "NO",
                               "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        let preview = app.buttons["today-margin-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertLessThan(preview.frame.height, 300)
        preview.tap()
        let field = app.textFields["margin-scenario-expense"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let result = app.staticTexts["margin-scenario-result"]
        XCTAssertTrue(result.label.contains("1.885,23"))

        replace(field, with: "3000")
        XCTAssertTrue(result.label.contains("Mancherebbero"))
        XCTAssertTrue(result.label.contains("814,77"))
        replace(field, with: "2185,23")
        XCTAssertTrue(result.label.contains("Resterebbero 0,00"))
        replace(field, with: "0")
        XCTAssertTrue(result.label.contains("2.185,23"))
        replace(field, with: "")
        XCTAssertTrue(app.staticTexts["margin-scenario-invalid"].exists)
        XCTAssertFalse(result.exists)
    }

    @MainActor
    private func replace(_ field: XCUIElement, with text: String) {
        let count = (field.value as? String)?.count ?? 0
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + text)
    }
}

import XCTest

final class CaptureUITests: XCTestCase {
    @MainActor func testBankDefaultSavedInSettingsPrefillsNotificationAndExplainsRouting() {
        let app = app(extraArguments: ["UITEST_CAPTURE_ROUTING"])
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Da approvare")).firstMatch.tap()
        app.buttons["Configura notifiche e condivisione"].tap()
        app.buttons["Conti predefiniti per banca"].tap()
        let previous = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Instradamento QA")).firstMatch
        if previous.exists { previous.swipeLeft(); app.buttons["Rimuovi"].tap() }
        app.buttons["capture-bank-default-add"].tap()
        let bank = app.textFields["capture-default-bank"]
        XCTAssertTrue(bank.waitForExistence(timeout: 5))
        bank.tap(); bank.typeText("Instradamento QA")
        XCTAssertTrue(app.buttons["capture-default-book"].label.contains("Prova acquisizione"))
        XCTAssertTrue(app.buttons["capture-default-account"].label.contains("Banca QA"))
        XCTAssertTrue(app.buttons["capture-default-save"].isEnabled)
        app.buttons["capture-default-save"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Instradamento QA")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        for _ in 0..<3 { app.navigationBars.buttons.firstMatch.tap() }
        XCTAssertTrue(app.buttons["capture-test-notification"].waitForExistence(timeout: 5))
        app.buttons["capture-test-notification"].tap()
        XCTAssertTrue(app.staticTexts["capture-test-acquired"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Da approvare")).firstMatch.tap()
        let proposal = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Conto predefinito per Instradamento QA")).firstMatch
        XCTAssertTrue(proposal.waitForExistence(timeout: 5))
        XCTAssertTrue(proposal.label.contains("Libro: Prova acquisizione"))
        XCTAssertTrue(proposal.label.contains("Conto: Banca QA"))
        proposal.tap()
        XCTAssertTrue(app.buttons["capture-book"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["capture-account"].label.contains("Banca QA"))
        XCTAssertTrue(app.staticTexts["Conto predefinito per Instradamento QA"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Configura notifiche e condivisione"].tap()
        app.buttons["Conti predefiniti per banca"].tap()
        saved.swipeLeft(); app.buttons["Rimuovi"].tap()
        XCTAssertFalse(saved.exists)
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func app(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_CAPTURE", "-CloudSyncEnabled", "NO", "-forgia.deviceAuthentication.enabled", "NO"] + extraArguments
        app.launch()
        XCTAssertTrue(app.buttons["capture-test-notification"].waitForExistence(timeout: 20))
        return app
    }
    @MainActor func testNotificationNeedsApprovalBeforeChangingBalance() {
        let app = app()
        app.buttons["capture-test-notification"].tap()
        XCTAssertTrue(app.staticTexts["capture-test-acquired"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["capture-test-balance"].label, "Saldo: 500")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Da approvare")).firstMatch.tap()
        let proposal = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Esselunga QA")).firstMatch
        XCTAssertTrue(proposal.waitForExistence(timeout: 10))
        proposal.tap()
        let amount = app.textFields["capture-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        XCTAssertEqual(amount.value as? String, "24.9")
        let confirmation = app.switches["Confermo che il pagamento o l’accredito è già avvenuto"]
        for _ in 0..<3 where !confirmation.isHittable { app.swipeUp() }
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["capture-approve"].isEnabled)
        let nativeSwitch = confirmation.switches.firstMatch
        if nativeSwitch.exists { nativeSwitch.tap() }
        else { confirmation.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: app.buttons["capture-approve"])
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        app.buttons["capture-approve"].tap()
        XCTAssertTrue(app.navigationBars["Da approvare"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertEqual(app.staticTexts["capture-test-recorded"].label, "Registrato: 24.9")
        XCTAssertEqual(app.staticTexts["capture-test-balance"].label, "Saldo: 475.1")
    }
    @MainActor func testInboxShowsSuggestedBookAccountAndCategoryFromHistory() {
        let app = app(extraArguments: ["UITEST_CAPTURE_CLASSIFICATION"])
        app.buttons["capture-test-notification"].tap()
        XCTAssertTrue(app.staticTexts["capture-test-acquired"].waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Da approvare")).firstMatch.tap()
        let proposal = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Esselunga QA")).firstMatch
        XCTAssertTrue(proposal.waitForExistence(timeout: 10))
        XCTAssertTrue(proposal.label.contains("Libro: Prova acquisizione"), proposal.label)
        XCTAssertTrue(proposal.label.contains("Conto: Banca QA"), proposal.label)
        XCTAssertTrue(proposal.label.contains("Categoria: Alimentari"), proposal.label)
        proposal.tap()
        XCTAssertTrue(app.buttons["capture-book"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["capture-book"].label.contains("Prova acquisizione"))
        XCTAssertTrue(app.buttons["capture-account"].label.contains("Banca QA"))
        XCTAssertTrue(app.buttons["capture-category"].label.contains("Alimentari"))
    }
    @MainActor func testSystemShareExtensionQueuesTextWithoutChangingBalance() {
        shareAndVerify(identifier: "capture-test-share", proposalLabel: "Testo condiviso")
    }
    @MainActor func testInboxLoadsFurtherPagesAndRemovesDiscardedProposal() {
        let app = app(extraArguments: ["UITEST_CAPTURE_PAGINATION"])
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Da approvare")).firstMatch.tap()
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Pagina QA 001")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let last = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Pagina QA 072")).firstMatch
        XCTAssertFalse(last.exists)
        for _ in 0..<30 where !last.isHittable { app.swipeUp() }
        XCTAssertTrue(last.isHittable, app.debugDescription)
        last.tap()
        let discard = app.buttons["Scarta proposta"]
        for _ in 0..<5 where !discard.isHittable { app.swipeUp() }
        XCTAssertTrue(discard.isHittable)
        discard.tap()
        app.buttons["Scarta"].tap()
        XCTAssertTrue(app.navigationBars["Da approvare"].waitForExistence(timeout: 10))
        XCTAssertFalse(last.exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertEqual(app.staticTexts["capture-test-balance"].label, "Saldo: 500")
        app.buttons["capture-test-clear-pagination"].tap()
    }
    @MainActor func testSystemShareExtensionReadsPDFWithoutChangingBalance() {
        shareAndVerify(identifier: "capture-test-share-pdf", proposalLabel: "Documento condiviso")
    }
    @MainActor func testSharedImageWithoutTextKeepsOriginalAndExplainsEmptyOCR() {
        shareAndVerify(identifier: "capture-test-share-blank-image", proposalLabel: "Documento condiviso", emptyOCR: true)
    }
    @MainActor private func shareAndVerify(identifier: String, proposalLabel: String, emptyOCR: Bool = false) {
        let app = app()
        app.buttons[identifier].tap()
        let formi = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Formi")).firstMatch
        if !formi.waitForExistence(timeout: 5) {
            let more = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Altro", "More"])).firstMatch
            XCTAssertTrue(more.waitForExistence(timeout: 5))
            more.tap()
        }
        XCTAssertTrue(formi.waitForExistence(timeout: 5), app.debugDescription)
        formi.tap()
        let saveToFormi = app.buttons["Aggiungi a Formi"]
        XCTAssertTrue(saveToFormi.waitForExistence(timeout: 10))
        let shareScreenshot = app.screenshot()
        let previewURL = FileManager.default.temporaryDirectory.appendingPathComponent("Formi-Share-Preview.png")
        try? shareScreenshot.pngRepresentation.write(to: previewURL)
        print("FORMI_SHARE_PREVIEW_FILE: \(previewURL.path)")
        let sharePreview = XCTAttachment(screenshot: shareScreenshot)
        sharePreview.name = "Estensione Formi - condivisione"; sharePreview.lifetime = .keepAlways
        add(sharePreview)
        saveToFormi.tap()
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: saveToFormi)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 15), .completed, app.debugDescription)
        if app.buttons["Chiudi"].exists { app.buttons["Chiudi"].tap() }
        XCTAssertTrue(app.buttons["capture-test-share"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["capture-test-balance"].label, "Saldo: 500")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Da approvare")).firstMatch.tap()
        let proposal = identifier != "capture-test-share"
            ? app.buttons["capture-proposal-document"].firstMatch
            : app.buttons.matching(NSPredicate(format: "label CONTAINS %@", proposalLabel)).firstMatch
        XCTAssertTrue(proposal.waitForExistence(timeout: 10), app.debugDescription)
        proposal.tap()
        XCTAssertTrue(app.textFields["capture-amount"].waitForExistence(timeout: 10))
        if emptyOCR {
            let status = app.staticTexts["capture-ocr-status"]
            XCTAssertTrue(status.waitForExistence(timeout: 15))
            XCTAssertTrue(status.label.contains("Non abbiamo trovato testo leggibile"), status.label)
            XCTAssertTrue(status.label.contains("originale è conservato"), status.label)
            XCTAssertFalse(app.buttons["capture-approve"].isEnabled)
            return
        }
        let recognized = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "18.5"), object: app.textFields["capture-amount"])
        XCTAssertEqual(XCTWaiter.wait(for: [recognized], timeout: 15), .completed)
        XCTAssertFalse(app.buttons["capture-approve"].isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Documento condiviso da approvare"; screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

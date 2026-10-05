//
//  Personal_FinanceUITests.swift
//  Personal FinanceUITests
//
//  Created by Francesco Bianco on 24/08/25.
//

import XCTest

final class Personal_FinanceUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testPrimaryDesignJourney() throws {
        let app = XCUIApplication()
        app.launch()

        let demoButton = app.buttons["Esplora con dati demo"]
        if demoButton.waitForExistence(timeout: 5) {
            capture(app, name: "01 Onboarding")
            demoButton.tap()
        }

        let analysisTab = app.buttons["Analisi"]
        XCTAssertTrue(analysisTab.waitForExistence(timeout: 20))
        capture(app, name: "02 Oggi")

        let plannedIncome = app.buttons["Registra la prossima entrata"]
        if plannedIncome.exists {
            plannedIncome.tap()
            XCTAssertTrue(app.staticTexts["Nuova entrata"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.switches["Transazione ricorrente"].value as? String, "1")
            capture(app, name: "03 Nuova entrata pianificata")
            app.buttons["Annulla"].tap()
        }

        app.buttons["Spesa"].tap()
        XCTAssertTrue(app.staticTexts["Nuova spesa"].waitForExistence(timeout: 10))
        capture(app, name: "04 Nuova spesa vuota")
        let amount = app.textFields["Importo"]
        XCTAssertTrue(amount.exists)
        amount.tap()
        amount.typeText("42,50")
        app.buttons["Categoria"].tap()
        app.buttons["Alimentari"].tap()
        let saveReady = NSPredicate(format: "isEnabled == true")
        expectation(for: saveReady, evaluatedWith: app.buttons["Salva spesa"])
        waitForExpectations(timeout: 5)
        capture(app, name: "05 Nuova spesa compilata")
        app.buttons["Annulla"].tap()

        analysisTab.tap()
        XCTAssertTrue(app.staticTexts["Dove spendi"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Ricorrenti e variabili"].exists)
        capture(app, name: "06 Analisi")

        let transactionsTab = app.buttons["Movimenti"]
        XCTAssertTrue(transactionsTab.waitForExistence(timeout: 10))
        transactionsTab.tap()
        XCTAssertTrue(app.staticTexts["Movimenti"].waitForExistence(timeout: 10))
        capture(app, name: "07 Movimenti")

        let moreTab = app.tabBars.buttons["Altro"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 10))
        moreTab.tap()
        XCTAssertTrue(app.staticTexts["Impostazioni"].waitForExistence(timeout: 10))
        capture(app, name: "08 Altro")
    }

    @MainActor
    func testWidgetLinksOpenPlanningAndExpense() throws {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Esplora con dati demo"].waitForExistence(timeout: 3) {
            app.buttons["Esplora con dati demo"].tap()
        }
        XCTAssertTrue(app.tabBars.buttons["Pianifica"].waitForExistence(timeout: 15))
        app.open(URL(string: "forgia://widget/planning")!)
        XCTAssertTrue(app.navigationBars["Pianifica"].waitForExistence(timeout: 10))
        app.open(URL(string: "forgia://widget/expense")!)
        XCTAssertTrue(app.navigationBars["Nuova spesa"].waitForExistence(timeout: 10))
        app.navigationBars["Nuova spesa"].buttons["Annulla"].tap()
    }

    @MainActor
    func testExpenseShortcutOpensReviewWithoutSaving() throws {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Esplora con dati demo"].waitForExistence(timeout: 3) {
            app.buttons["Esplora con dati demo"].tap()
        }
        let more = app.tabBars.buttons["Altro"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        more.tap()
        let link = app.buttons["Comandi Rapidi e Siri"]
        for _ in 0..<8 {
            if link.exists && link.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        let action = app.buttons["try-expense-shortcut"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.tap()
        XCTAssertTrue(app.navigationBars["Nuova spesa"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["Importo"].exists)
        capture(app, name: "Spesa aperta da App Intent")
        app.navigationBars["Nuova spesa"].buttons["Annulla"].tap()
        XCTAssertTrue(action.waitForExistence(timeout: 5))
    }

    @MainActor
    func testForeignAmountIsConvertedBeforeSaving() throws {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Esplora con dati demo"].waitForExistence(timeout: 3) {
            app.buttons["Esplora con dati demo"].tap()
        }
        XCTAssertTrue(app.buttons["Spesa"].waitForExistence(timeout: 15))
        app.buttons["Spesa"].tap()
        app.buttons["Importo in valuta estera"].tap()
        let original = app.textFields["Importo in valuta estera"]
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        original.tap()
        original.typeText("100")
        let rate = app.textFields["Tasso di cambio"]
        rate.tap()
        rate.typeText("0,9")
        app.navigationBars["Valuta estera"].buttons["Usa importo"].tap()
        let amount = app.textFields["Importo"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertEqual(amount.value as? String, "90")
        capture(app, name: "Importo estero convertito")
        app.navigationBars["Nuova spesa"].buttons["Annulla"].tap()
    }

    @MainActor
    func testManualPlaceDraftCanBeCancelled() throws {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Esplora con dati demo"].waitForExistence(timeout: 3) {
            app.buttons["Esplora con dati demo"].tap()
        }
        XCTAssertTrue(app.buttons["Spesa"].waitForExistence(timeout: 15))
        app.buttons["Spesa"].tap()
        let place = app.textFields["Nome del luogo (opzionale)"]
        for _ in 0..<6 {
            if place.isHittable && place.frame.midY < app.frame.height * 0.65 { break }
            app.swipeUp()
        }
        XCTAssertTrue(place.isHittable)
        place.tap()
        place.typeText("Luogo di prova")
        app.navigationBars["Nuova spesa"].buttons["Annulla"].tap()
        app.buttons["Spesa"].tap()
        for _ in 0..<6 {
            if place.isHittable && place.frame.midY < app.frame.height * 0.65 { break }
            app.swipeUp()
        }
        XCTAssertEqual(place.value as? String, "Nome del luogo (opzionale)")
        capture(app, name: "Luogo facoltativo")
        app.navigationBars["Nuova spesa"].buttons["Annulla"].tap()
    }

    @MainActor
    func testRecurringSeriesCanBeEndedWithoutDeletingHistory() throws {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Esplora con dati demo"].waitForExistence(timeout: 3) {
            app.buttons["Esplora con dati demo"].tap()
        }
        let title = "Ricorrenza test " + UUID().uuidString.prefix(6)
        XCTAssertTrue(app.buttons["Spesa"].waitForExistence(timeout: 15))
        app.buttons["Spesa"].tap()
        app.buttons["Categoria"].tap()
        app.buttons["Alimentari"].tap()
        let recurring = app.switches["Transazione ricorrente"]
        for _ in 0..<4 {
            if recurring.isHittable { break }
            app.swipeUp()
        }
        recurring.tap()
        let note = app.textFields["Aggiungi una nota (opzionale)"]
        note.tap()
        note.typeText(title)
        app.swipeDown()
        let amount = app.textFields["Importo"]
        for _ in 0..<4 {
            if amount.isHittable { break }
            app.swipeDown()
        }
        amount.tap()
        amount.typeText("1,23")
        app.buttons["Salva spesa"].tap()
        let planning = app.tabBars.buttons["Pianifica"]
        XCTAssertTrue(planning.waitForExistence(timeout: 5))
        planning.tap()
        let manage = app.buttons["Gestisci ricorrenze"]
        for _ in 0..<5 {
            if manage.isHittable { break }
            app.swipeUp()
        }
        manage.tap()
        let row = app.descendants(matching: .any)["recurring-series-" + title].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.buttons["Termina"].tap()
        app.buttons["Termina ricorrenza"].tap()
        app.segmentedControls.buttons["Terminate"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(row.buttons["Termina"].exists)
        capture(app, name: "Ricorrenza terminata e conservata")
    }

    @MainActor
    func testLockedLaunchDoesNotExposeFinancialNavigation() throws {
        let app = XCUIApplication()
        // Standard UserDefaults argument domain: this does not persist the setting.
        app.launchArguments = ["-forgia.deviceAuthentication.enabled", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Sblocca"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.buttons["Movimenti"].exists)
        XCTAssertFalse(app.buttons["Spesa"].exists)
        app.open(URL(string: "forgia://widget/expense")!)
        XCTAssertTrue(app.buttons["Sblocca"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Nuova spesa"].exists)
        capture(app, name: "Forgia bloccata")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["Sblocca"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.buttons["Movimenti"].exists)
    }

    @MainActor
    func testCalculatorAppliesAmountWithoutSaving() throws {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Esplora con dati demo"].waitForExistence(timeout: 3) {
            app.buttons["Esplora con dati demo"].tap()
        }
        let expense = app.buttons["Spesa"]
        XCTAssertTrue(expense.waitForExistence(timeout: 15))
        expense.tap()
        app.buttons["Calcolatrice"].tap()
        XCTAssertTrue(app.buttons["Usa importo"].waitForExistence(timeout: 5))
        for key in ["1", "2", ",", "5", "+", "8"] { app.buttons[key].tap() }
        capture(app, name: "Calcolatrice somma")
        app.buttons["Usa importo"].tap()
        let amount = app.textFields["Importo"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertEqual(amount.value as? String, "20,5")
        app.buttons["Calcolatrice"].tap()
        app.buttons["Azzera calcolo"].tap()
        for key in ["1", "÷", "0"] { app.buttons[key].tap() }
        XCTAssertFalse(app.buttons["Usa importo"].isEnabled)
        app.navigationBars["Calcolatrice"].buttons["Annulla"].tap()
        XCTAssertEqual(amount.value as? String, "20,5")
        app.buttons["Annulla"].tap()
    }

    @MainActor
    func testAnalysisPeriods() throws {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Esplora con dati demo"].waitForExistence(timeout: 3) {
            app.buttons["Esplora con dati demo"].tap()
        }
        let analysis = app.tabBars.buttons["Analisi"]
        XCTAssertTrue(analysis.waitForExistence(timeout: 15))
        analysis.tap()
        XCTAssertTrue(app.staticTexts["Dove spendi"].waitForExistence(timeout: 5))
        app.buttons["Periodo precedente"].tap()
        app.segmentedControls.buttons["Anno"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Anno"].isSelected)
        capture(app, name: "Analisi annuale")
        app.segmentedControls.buttons["Mese"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Mese"].isSelected)
    }

    @MainActor
    func testPlanningNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Esplora con dati demo"].waitForExistence(timeout: 3) {
            app.buttons["Esplora con dati demo"].tap()
        }
        let planning = app.tabBars.buttons["Pianifica"]
        XCTAssertTrue(planning.waitForExistence(timeout: 15))
        planning.tap()
        let budgets = app.buttons["planning-budgets"]
        XCTAssertTrue(budgets.waitForExistence(timeout: 5))
        capture(app, name: "Pianifica conti e scadenze")
        budgets.tap()
        XCTAssertTrue(app.buttons["Nuovo budget"].waitForExistence(timeout: 5))
        app.buttons["Fine"].tap()
        XCTAssertTrue(budgets.waitForExistence(timeout: 5))
        app.buttons["Nuovo conto"].tap()
        XCTAssertTrue(app.textFields["Nome Conto"].waitForExistence(timeout: 5))
        app.buttons["Annulla"].tap()
        XCTAssertTrue(budgets.waitForExistence(timeout: 5))
    }

    @MainActor
    func testExpenseBudgetPreviewUpdatesBeforeSaving() throws {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Esplora con dati demo"].waitForExistence(timeout: 3) {
            app.buttons["Esplora con dati demo"].tap()
        }
        let budgetLink = app.buttons["today-budgets"]
        for _ in 0..<8 {
            if budgetLink.exists && budgetLink.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(budgetLink.isHittable)
        budgetLink.tap()
        app.buttons["Nuovo budget"].tap()
        let name = app.textFields["Nome Budget"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let category = app.buttons["budget-category-Alimentari"]
        for _ in 0..<4 {
            if category.exists && category.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(category.isHittable, app.debugDescription)
        category.tap()
        expectation(for: NSPredicate(format: "value == %@", "Selezionata"), evaluatedWith: category)
        waitForExpectations(timeout: 5)
        for _ in 0..<4 {
            if name.isHittable { break }
            app.swipeDown()
        }
        name.tap()
        name.typeText("Verifica spesa " + UUID().uuidString.prefix(6))
        let limit = app.textFields["0,00"]
        limit.tap()
        limit.typeText("1000000")
        app.buttons["Salva"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: name)
        waitForExpectations(timeout: 5)
        app.terminate()
        app.launch()
        app.buttons["Spesa"].tap()
        let amount = app.textFields["Importo"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        app.buttons["Categoria"].tap()
        let expenseCategory = app.buttons["Alimentari"]
        XCTAssertTrue(expenseCategory.waitForExistence(timeout: 5))
        expenseCategory.tap()
        amount.tap()
        amount.typeText("42,50")
        let within = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Rientra nel budget")).firstMatch
        XCTAssertTrue(within.waitForExistence(timeout: 5))
        capture(app, name: "Budget entro il limite")
        amount.tap()
        // Clear through the field's existing clear action, avoiding clipboard state.
        app.buttons["Cancella importo"].tap()
        amount.tap()
        amount.typeText("1000001")
        let over = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Sforeresti di")).firstMatch
        XCTAssertTrue(over.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Salva spesa"].isEnabled)
        capture(app, name: "Budget sforamento prima del salvataggio")
        app.buttons["Annulla"].tap()
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

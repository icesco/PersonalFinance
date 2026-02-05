//
//  DemoDataService.swift
//  Personal Finance
//
//  Service to generate realistic demo data for the app
//

import Foundation
import SwiftData
import FinanceCore

/// Service to populate the app with realistic demo data
@MainActor
final class DemoDataService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Generate all demo data
    func generateDemoData() async throws {
        // Create accounts
        let personalAccount = createPersonalAccount()
        let familyAccount = createFamilyAccount()

        modelContext.insert(personalAccount)
        modelContext.insert(familyAccount)

        // Create categories for each account
        let personalCategories = createCategories(for: personalAccount)
        let familyCategories = createCategories(for: familyAccount)

        // Create conti for each account
        let personalConti = createConti(for: personalAccount)
        let familyConti = createConti(for: familyAccount)

        // Generate transactions for the last 6 months
        generateTransactions(
            for: personalAccount,
            conti: personalConti,
            categories: personalCategories,
            monthlyIncome: 2800,
            profile: .single
        )

        generateTransactions(
            for: familyAccount,
            conti: familyConti,
            categories: familyCategories,
            monthlyIncome: 4500,
            profile: .family
        )

        try modelContext.save()
    }

    // MARK: - Account Creation

    private func createPersonalAccount() -> Account {
        let account = Account(name: "Personale", currency: "EUR")
        return account
    }

    private func createFamilyAccount() -> Account {
        let account = Account(name: "Famiglia", currency: "EUR")
        return account
    }

    // MARK: - Categories Creation

    private func createCategories(for account: Account) -> [String: FinanceCategory] {
        var categoryMap: [String: FinanceCategory] = [:]

        let categoryData: [(name: String, color: String, icon: String)] = [
            // Income
            ("Stipendio", "#4CAF50", "dollarsign.circle"),
            ("Freelance", "#8BC34A", "briefcase"),
            ("Bonus", "#2E7D32", "gift.circle"),
            ("Rimborsi", "#388E3C", "arrow.counterclockwise.circle"),

            // Expenses
            ("Alimentari", "#F44336", "cart"),
            ("Trasporti", "#2196F3", "car"),
            ("Casa", "#9C27B0", "house"),
            ("Utenze", "#673AB7", "bolt"),
            ("Salute", "#E91E63", "cross.case"),
            ("Intrattenimento", "#FF5722", "gamecontroller"),
            ("Abbigliamento", "#795548", "tshirt"),
            ("Ristoranti", "#FF6F00", "fork.knife"),
            ("Viaggi", "#1976D2", "airplane"),
            ("Sport", "#FF9800", "figure.run"),
            ("Tecnologia", "#455A64", "iphone"),
            ("Abbonamenti", "#00BCD4", "tv"),
            ("Educazione", "#607D8B", "book"),
            ("Regali", "#FF4081", "gift"),
            ("Altro", "#9E9E9E", "questionmark.circle")
        ]

        for (name, color, icon) in categoryData {
            let category = FinanceCategory(name: name, color: color, icon: icon)
            category.account = account
            modelContext.insert(category)
            categoryMap[name] = category
        }

        return categoryMap
    }

    // MARK: - Conti Creation

    private func createConti(for account: Account) -> [ContoType: Conto] {
        var contiMap: [ContoType: Conto] = [:]

        let contiData: [(name: String, type: ContoType, initialBalance: Decimal)] = [
            ("Conto Principale", .checking, 1500),
            ("Carta di Credito", .credit, 0),
            ("Contanti", .cash, 150),
            ("Risparmi", .savings, 5000)
        ]

        for (name, type, initialBalance) in contiData {
            let conto = Conto(name: name, type: type, initialBalance: initialBalance)
            conto.account = account
            modelContext.insert(conto)
            contiMap[type] = conto
        }

        return contiMap
    }

    // MARK: - Transaction Generation

    private enum SpendingProfile {
        case single
        case family
    }

    private func generateTransactions(
        for account: Account,
        conti: [ContoType: Conto],
        categories: [String: FinanceCategory],
        monthlyIncome: Decimal,
        profile: SpendingProfile
    ) {
        let calendar = Calendar.current
        let now = Date()

        // Generate for the last 6 months
        for monthOffset in (0..<6).reversed() {
            guard let monthStart = calendar.date(byAdding: .month, value: -monthOffset, to: now),
                  let monthDate = calendar.date(from: calendar.dateComponents([.year, .month], from: monthStart))
            else { continue }

            // Monthly income (salary on the 27th)
            if let salaryDate = calendar.date(bySetting: .day, value: 27, of: monthDate),
               let checkingConto = conti[.checking],
               let salaryCategory = categories["Stipendio"] {
                createTransaction(
                    amount: monthlyIncome,
                    type: .income,
                    date: salaryDate,
                    description: "Stipendio",
                    toConto: checkingConto,
                    category: salaryCategory
                )
            }

            // Occasional bonus (every 3 months)
            if monthOffset % 3 == 0,
               let bonusDate = calendar.date(bySetting: .day, value: 28, of: monthDate),
               let checkingConto = conti[.checking],
               let bonusCategory = categories["Bonus"] {
                createTransaction(
                    amount: Decimal(Int.random(in: 200...500)),
                    type: .income,
                    date: bonusDate,
                    description: "Bonus trimestrale",
                    toConto: checkingConto,
                    category: bonusCategory
                )
            }

            // Fixed monthly expenses
            generateFixedExpenses(
                monthDate: monthDate,
                conti: conti,
                categories: categories,
                profile: profile,
                calendar: calendar
            )

            // Variable expenses throughout the month
            generateVariableExpenses(
                monthDate: monthDate,
                conti: conti,
                categories: categories,
                profile: profile,
                calendar: calendar
            )

            // Transfer to savings (10th of the month)
            if let transferDate = calendar.date(bySetting: .day, value: 10, of: monthDate),
               let checkingConto = conti[.checking],
               let savingsConto = conti[.savings] {
                let savingsAmount: Decimal = profile == .family ? 400 : 250
                createTransfer(
                    amount: savingsAmount,
                    date: transferDate,
                    description: "Risparmio mensile",
                    fromConto: checkingConto,
                    toConto: savingsConto
                )
            }
        }
    }

    private func generateFixedExpenses(
        monthDate: Date,
        conti: [ContoType: Conto],
        categories: [String: FinanceCategory],
        profile: SpendingProfile,
        calendar: Calendar
    ) {
        guard let checkingConto = conti[.checking] else { return }

        // Rent/Mortgage (1st of the month)
        if let rentDate = calendar.date(bySetting: .day, value: 1, of: monthDate),
           let casaCategory = categories["Casa"] {
            let rentAmount: Decimal = profile == .family ? 950 : 650
            createTransaction(
                amount: rentAmount,
                type: .expense,
                date: rentDate,
                description: "Affitto",
                fromConto: checkingConto,
                category: casaCategory
            )
        }

        // Utilities (5th of the month)
        if let utilitiesDate = calendar.date(bySetting: .day, value: 5, of: monthDate),
           let utilitiesCategory = categories["Utenze"] {
            let utilities: [(String, Decimal)] = profile == .family
                ? [("Luce", 85), ("Gas", 65), ("Acqua", 35), ("Internet", 35)]
                : [("Luce", 45), ("Gas", 35), ("Internet", 30)]

            for (utility, amount) in utilities {
                createTransaction(
                    amount: amount,
                    type: .expense,
                    date: utilitiesDate,
                    description: utility,
                    fromConto: checkingConto,
                    category: utilitiesCategory
                )
            }
        }

        // Subscriptions (various dates)
        if let subscriptionsCategory = categories["Abbonamenti"] {
            let subscriptions: [(String, Decimal, Int)] = [
                ("Netflix", 15.99, 8),
                ("Spotify", 10.99, 12),
                ("Palestra", profile == .family ? 79 : 39, 1),
                ("Amazon Prime", 4.99, 15)
            ]

            for (name, amount, day) in subscriptions {
                if let subDate = calendar.date(bySetting: .day, value: day, of: monthDate) {
                    createTransaction(
                        amount: amount,
                        type: .expense,
                        date: subDate,
                        description: name,
                        fromConto: checkingConto,
                        category: subscriptionsCategory
                    )
                }
            }
        }

        // Transport (monthly pass on 1st)
        if let transportDate = calendar.date(bySetting: .day, value: 1, of: monthDate),
           let transportCategory = categories["Trasporti"] {
            let transportAmount: Decimal = profile == .family ? 70 : 39
            createTransaction(
                amount: transportAmount,
                type: .expense,
                date: transportDate,
                description: "Abbonamento trasporti",
                fromConto: checkingConto,
                category: transportCategory
            )
        }
    }

    private func generateVariableExpenses(
        monthDate: Date,
        conti: [ContoType: Conto],
        categories: [String: FinanceCategory],
        profile: SpendingProfile,
        calendar: Calendar
    ) {
        guard let checkingConto = conti[.checking],
              let creditConto = conti[.credit],
              let cashConto = conti[.cash]
        else { return }

        let daysInMonth = calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 30

        // Groceries (2-3 times per week)
        if let alimentariCategory = categories["Alimentari"] {
            let groceryDays = profile == .family ? [3, 7, 10, 14, 17, 21, 24, 28] : [4, 11, 18, 25]
            for day in groceryDays {
                if day <= daysInMonth,
                   let groceryDate = calendar.date(bySetting: .day, value: day, of: monthDate) {
                    let amount = profile == .family
                        ? Decimal(Int.random(in: 80...150))
                        : Decimal(Int.random(in: 40...80))
                    createTransaction(
                        amount: amount,
                        type: .expense,
                        date: groceryDate,
                        description: ["Supermercato", "Spesa settimanale", "Esselunga", "Conad"].randomElement()!,
                        fromConto: Bool.random() ? checkingConto : creditConto,
                        category: alimentariCategory
                    )
                }
            }
        }

        // Restaurants (2-4 times per month)
        if let ristorantiCategory = categories["Ristoranti"] {
            let restaurantCount = profile == .family ? Int.random(in: 2...4) : Int.random(in: 3...6)
            for _ in 0..<restaurantCount {
                let day = Int.random(in: 1...min(28, daysInMonth))
                if let restaurantDate = calendar.date(bySetting: .day, value: day, of: monthDate) {
                    let amount = profile == .family
                        ? Decimal(Int.random(in: 50...120))
                        : Decimal(Int.random(in: 20...60))
                    createTransaction(
                        amount: amount,
                        type: .expense,
                        date: restaurantDate,
                        description: ["Cena fuori", "Pranzo", "Pizza", "Sushi", "Aperitivo"].randomElement()!,
                        fromConto: creditConto,
                        category: ristorantiCategory
                    )
                }
            }
        }

        // Entertainment (1-3 times per month)
        if let entertainmentCategory = categories["Intrattenimento"] {
            let entertainmentCount = Int.random(in: 1...3)
            for _ in 0..<entertainmentCount {
                let day = Int.random(in: 1...min(28, daysInMonth))
                if let entertainmentDate = calendar.date(bySetting: .day, value: day, of: monthDate) {
                    let descriptions = profile == .family
                        ? ["Cinema famiglia", "Parco divertimenti", "Bowling", "Escape room"]
                        : ["Cinema", "Concerto", "Teatro", "Mostra"]
                    let amount = profile == .family
                        ? Decimal(Int.random(in: 30...80))
                        : Decimal(Int.random(in: 15...50))
                    createTransaction(
                        amount: amount,
                        type: .expense,
                        date: entertainmentDate,
                        description: descriptions.randomElement()!,
                        fromConto: Bool.random() ? creditConto : cashConto,
                        category: entertainmentCategory
                    )
                }
            }
        }

        // Small cash expenses (coffee, snacks)
        if let altroCategory = categories["Altro"] {
            let smallExpenseCount = Int.random(in: 5...12)
            for _ in 0..<smallExpenseCount {
                let day = Int.random(in: 1...min(28, daysInMonth))
                if let expenseDate = calendar.date(bySetting: .day, value: day, of: monthDate) {
                    createTransaction(
                        amount: Decimal(Double.random(in: 2...15).rounded(toPlaces: 2)),
                        type: .expense,
                        date: expenseDate,
                        description: ["Caffè", "Snack", "Giornale", "Parcheggio", "Mancia"].randomElement()!,
                        fromConto: cashConto,
                        category: altroCategory
                    )
                }
            }
        }

        // Occasional shopping
        if Bool.random() {
            if let abbigliamentoCategory = categories["Abbigliamento"] {
                let day = Int.random(in: 10...25)
                if let shoppingDate = calendar.date(bySetting: .day, value: day, of: monthDate) {
                    createTransaction(
                        amount: Decimal(Int.random(in: 30...150)),
                        type: .expense,
                        date: shoppingDate,
                        description: ["Vestiti", "Scarpe", "Accessori"].randomElement()!,
                        fromConto: creditConto,
                        category: abbigliamentoCategory
                    )
                }
            }
        }

        // Occasional tech purchase (every 2-3 months)
        if Int.random(in: 0...2) == 0 {
            if let techCategory = categories["Tecnologia"] {
                let day = Int.random(in: 5...20)
                if let techDate = calendar.date(bySetting: .day, value: day, of: monthDate) {
                    createTransaction(
                        amount: Decimal(Int.random(in: 20...200)),
                        type: .expense,
                        date: techDate,
                        description: ["Accessorio tech", "App", "Cavi", "Gadget"].randomElement()!,
                        fromConto: creditConto,
                        category: techCategory
                    )
                }
            }
        }

        // Health expense (occasional)
        if Int.random(in: 0...3) == 0 {
            if let healthCategory = categories["Salute"] {
                let day = Int.random(in: 1...28)
                if let healthDate = calendar.date(bySetting: .day, value: day, of: monthDate) {
                    createTransaction(
                        amount: Decimal(Int.random(in: 15...100)),
                        type: .expense,
                        date: healthDate,
                        description: ["Farmacia", "Visita medica", "Dentista"].randomElement()!,
                        fromConto: checkingConto,
                        category: healthCategory
                    )
                }
            }
        }
    }

    // MARK: - Transaction Helpers

    private func createTransaction(
        amount: Decimal,
        type: TransactionType,
        date: Date,
        description: String,
        fromConto: Conto? = nil,
        toConto: Conto? = nil,
        category: FinanceCategory
    ) {
        let transaction = FinanceTransaction(
            amount: amount,
            type: type,
            date: date,
            transactionDescription: description
        )

        if let fromConto = fromConto {
            transaction.setFromConto(fromConto)
        }
        if let toConto = toConto {
            transaction.setToConto(toConto)
        }
        transaction.setCategory(category)

        modelContext.insert(transaction)
    }

    private func createTransfer(
        amount: Decimal,
        date: Date,
        description: String,
        fromConto: Conto,
        toConto: Conto
    ) {
        let transaction = FinanceTransaction(
            amount: amount,
            type: .transfer,
            date: date,
            transactionDescription: description
        )

        transaction.setFromConto(fromConto)
        transaction.setToConto(toConto)

        modelContext.insert(transaction)
    }
}

// MARK: - Helper Extensions

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

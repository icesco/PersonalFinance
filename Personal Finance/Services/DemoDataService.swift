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

    /// Generate demo data: a "Demo" libro with one conto corrente and 2 months of transactions
    func generateDemoData() async throws {
        let account = Account(name: "Demo", currency: "EUR")
        modelContext.insert(account)

        let categories = createCategories(for: account)

        let conto = Conto(name: "Conto Corrente", type: .checking, initialBalance: 2500)
        conto.account = account
        modelContext.insert(conto)

        let calendar = Calendar.current
        let now = Date()

        // Previous month
        if let prevMonth = calendar.date(byAdding: .month, value: -1, to: now) {
            let monthDate = calendar.date(from: calendar.dateComponents([.year, .month], from: prevMonth))!
            generateMonth(monthDate: monthDate, conto: conto, categories: categories, calendar: calendar)
        }

        // Current month
        let currentMonthDate = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        generateMonth(monthDate: currentMonthDate, conto: conto, categories: categories, calendar: calendar)

        try modelContext.save()
    }

    // MARK: - Categories

    private func createCategories(for account: Account) -> [String: FinanceCategory] {
        var map: [String: FinanceCategory] = [:]

        let data: [(String, String, String)] = [
            ("Stipendio", "#4CAF50", "dollarsign.circle"),
            ("Bonus", "#2E7D32", "gift.circle"),
            ("Alimentari", "#F44336", "cart"),
            ("Trasporti", "#2196F3", "car"),
            ("Casa", "#9C27B0", "house"),
            ("Utenze", "#673AB7", "bolt"),
            ("Salute", "#E91E63", "cross.case"),
            ("Intrattenimento", "#FF5722", "gamecontroller"),
            ("Abbigliamento", "#795548", "tshirt"),
            ("Ristoranti", "#FF6F00", "fork.knife"),
            ("Abbonamenti", "#00BCD4", "tv"),
            ("Sport", "#FF9800", "figure.run"),
            ("Altro", "#9E9E9E", "questionmark.circle"),
        ]

        for (name, color, icon) in data {
            let cat = FinanceCategory(name: name, color: color, icon: icon)
            cat.account = account
            modelContext.insert(cat)
            map[name] = cat
        }

        return map
    }

    // MARK: - Month Generation

    private func generateMonth(
        monthDate: Date,
        conto: Conto,
        categories: [String: FinanceCategory],
        calendar: Calendar
    ) {
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 30
        // Limit to today if current month
        let today = Date()
        let isCurrentMonth = calendar.isDate(monthDate, equalTo: today, toGranularity: .month)
        let maxDay = isCurrentMonth ? calendar.component(.day, from: today) : daysInMonth

        // — Stipendio (27th)
        if maxDay >= 27, let cat = categories["Stipendio"] {
            addTx(amount: 2400, type: .income, day: 27, month: monthDate,
                   desc: "Stipendio", toConto: conto, category: cat, calendar: calendar)
        }

        // — Affitto (1st)
        if let cat = categories["Casa"] {
            addTx(amount: 650, type: .expense, day: 1, month: monthDate,
                   desc: "Affitto", fromConto: conto, category: cat, calendar: calendar)
        }

        // — Utenze (5th)
        if maxDay >= 5, let cat = categories["Utenze"] {
            addTx(amount: 48, type: .expense, day: 5, month: monthDate,
                   desc: "Luce", fromConto: conto, category: cat, calendar: calendar)
            addTx(amount: 38, type: .expense, day: 5, month: monthDate,
                   desc: "Gas", fromConto: conto, category: cat, calendar: calendar)
            addTx(amount: 30, type: .expense, day: 5, month: monthDate,
                   desc: "Internet", fromConto: conto, category: cat, calendar: calendar)
        }

        // — Abbonamenti
        if let cat = categories["Abbonamenti"] {
            if maxDay >= 8 {
                addTx(amount: 15.99, type: .expense, day: 8, month: monthDate,
                       desc: "Netflix", fromConto: conto, category: cat, calendar: calendar)
            }
            if maxDay >= 12 {
                addTx(amount: 10.99, type: .expense, day: 12, month: monthDate,
                       desc: "Spotify", fromConto: conto, category: cat, calendar: calendar)
            }
        }

        // — Trasporti (1st)
        if let cat = categories["Trasporti"] {
            addTx(amount: 39, type: .expense, day: 1, month: monthDate,
                   desc: "Abbonamento metro", fromConto: conto, category: cat, calendar: calendar)
        }

        // — Sport (1st)
        if let cat = categories["Sport"] {
            addTx(amount: 45, type: .expense, day: 1, month: monthDate,
                   desc: "Palestra", fromConto: conto, category: cat, calendar: calendar)
        }

        // — Alimentari (weekly)
        if let cat = categories["Alimentari"] {
            let groceryDays = [4, 11, 18, 25].filter { $0 <= maxDay }
            let descriptions = ["Supermercato", "Spesa settimanale", "Esselunga", "Conad"]
            for (i, day) in groceryDays.enumerated() {
                let amount = Decimal(Int.random(in: 45...85))
                addTx(amount: amount, type: .expense, day: day, month: monthDate,
                       desc: descriptions[i % descriptions.count], fromConto: conto, category: cat, calendar: calendar)
            }
        }

        // — Ristoranti (3-4 times)
        if let cat = categories["Ristoranti"] {
            let descriptions = ["Cena fuori", "Pranzo", "Pizza", "Aperitivo", "Sushi"]
            let count = Int.random(in: 3...4)
            for i in 0..<count {
                let day = randomDay(in: 1...min(28, maxDay))
                let amount = Decimal(Int.random(in: 18...55))
                addTx(amount: amount, type: .expense, day: day, month: monthDate,
                       desc: descriptions[i % descriptions.count], fromConto: conto, category: cat, calendar: calendar)
            }
        }

        // — Intrattenimento (1-2 times)
        if let cat = categories["Intrattenimento"] {
            let descriptions = ["Cinema", "Concerto", "Mostra", "Teatro"]
            let count = Int.random(in: 1...2)
            for i in 0..<count {
                let day = randomDay(in: 1...min(28, maxDay))
                let amount = Decimal(Int.random(in: 12...40))
                addTx(amount: amount, type: .expense, day: day, month: monthDate,
                       desc: descriptions[i % descriptions.count], fromConto: conto, category: cat, calendar: calendar)
            }
        }

        // — Small cash (coffee, etc.)
        if let cat = categories["Altro"] {
            let descriptions = ["Caffe'", "Snack", "Giornale", "Parcheggio"]
            let count = Int.random(in: 5...8)
            for i in 0..<count {
                let day = randomDay(in: 1...min(28, maxDay))
                let amount = Decimal(Double.random(in: 1.5...8.0).rounded(toPlaces: 2))
                addTx(amount: amount, type: .expense, day: day, month: monthDate,
                       desc: descriptions[i % descriptions.count], fromConto: conto, category: cat, calendar: calendar)
            }
        }

        // — Occasional: abbigliamento
        if Bool.random(), maxDay >= 10, let cat = categories["Abbigliamento"] {
            let day = randomDay(in: 10...min(25, maxDay))
            addTx(amount: Decimal(Int.random(in: 35...120)), type: .expense, day: day, month: monthDate,
                   desc: ["Vestiti", "Scarpe"].randomElement()!, fromConto: conto, category: cat, calendar: calendar)
        }

        // — Occasional: salute
        if Bool.random(), let cat = categories["Salute"] {
            let day = randomDay(in: 1...min(28, maxDay))
            addTx(amount: Decimal(Int.random(in: 15...80)), type: .expense, day: day, month: monthDate,
                   desc: "Farmacia", fromConto: conto, category: cat, calendar: calendar)
        }
    }

    // MARK: - Helpers

    private func addTx(
        amount: Decimal,
        type: TransactionType,
        day: Int,
        month: Date,
        desc: String,
        fromConto: Conto? = nil,
        toConto: Conto? = nil,
        category: FinanceCategory,
        calendar: Calendar
    ) {
        guard let date = calendar.date(bySetting: .day, value: day, of: month) else { return }
        let tx = FinanceTransaction(amount: amount, type: type, date: date, transactionDescription: desc)
        if let from = fromConto { tx.setFromConto(from) }
        if let to = toConto { tx.setToConto(to) }
        tx.setCategory(category)
        modelContext.insert(tx)
    }

    private func randomDay(in range: ClosedRange<Int>) -> Int {
        Int.random(in: range)
    }
}

// MARK: - Helper Extensions

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

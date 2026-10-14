#if DEBUG
import SwiftUI
import SwiftData
import FinanceCore

/// In-memory ledger for forecast interaction checks.
struct MonthlyForecastFixture: View {
    @MainActor private static let data: (ModelContainer, [Conto]) = {
        let container = try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Previsione illustrativa", currency: "EUR")
        let joint = Conto(name: "Cointestato", type: .checking, initialBalance: 500)
        let bank = Conto(name: "Crédit Agricole", type: .checking, initialBalance: 100)
        joint.account = book; bank.account = book; book.conti = [joint, bank]
        container.mainContext.insert(book)
        let food = FinanceCore.Category(name: "Alimentari", icon: "basket")
        let bills = FinanceCore.Category(name: "Bollette", icon: "bolt")
        food.account = book; bills.account = book
        container.mainContext.insert(food); container.mainContext.insert(bills)
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.dateInterval(of: .month, for: now)!.start
        @MainActor func add(_ conto: Conto, _ date: Date, _ amount: Decimal, _ title: String,
                            category: FinanceCore.Category, recurring: Bool = false) {
            let row = FinanceCore.Transaction(amount: amount, type: .expense, date: date,
                transactionDescription: title, isRecurring: recurring, recurrenceFrequency: recurring ? .monthly : nil)
            row.setFromConto(conto); row.setCategory(category)
            if date < now { row.createdAt = date; row.scheduledOriginDate = nil }
            container.mainContext.insert(row)
        }
        add(joint, calendar.date(byAdding: .month, value: -4, to: start)!, 1, "Inizio storico", category: food)
        for offset in 1...3 {
            let prior = calendar.date(byAdding: .month, value: -offset, to: start)!
            add(joint, calendar.date(byAdding: .day, value: 4, to: prior)!, 30, "Spesa storica", category: food)
            add(joint, calendar.date(byAdding: .day, value: 19, to: prior)!, 30, "Spesa storica", category: food)
        }
        add(joint, now.addingTimeInterval(-86400), 20, "Alimentari registrati", category: food)
        let due = calendar.date(byAdding: .day, value: -2, to: calendar.date(byAdding: .month, value: 1, to: start)!)!
        add(joint, due, 25, "Acquisto programmato", category: food)
        add(joint, calendar.date(byAdding: .month, value: -1, to: due)!, 50, "Utenza ricorrente", category: bills, recurring: true)
        add(bank, due, 300, "Consulto programmato", category: bills)
        try! container.mainContext.save()
        return (container, [joint, bank])
    }()
    var body: some View {
        NavigationStack {
            MonthlyForecastView(conti: Self.data.1, currency: "EUR")
        }.modelContainer(Self.data.0)
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("UITEST_VISUAL_DARK") ? .dark : .light)
            .transaction { transaction in
                if ProcessInfo.processInfo.arguments.contains("UITEST_FORECAST_REDUCE_MOTION") { transaction.disablesAnimations = true }
            }
    }
}
#endif

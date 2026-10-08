#if DEBUG
import SwiftUI
import SwiftData
import FinanceCore

/// Isolated calendar data for interaction checks; never touches the real ledger.
struct FinanceCalendarFixture: View {
    private static let data: (ModelContainer, UUID) = {
        let container = try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Calendario illustrativo", currency: "EUR")
        let conto = Conto(name: "Corrente", type: .checking, initialBalance: 2000)
        conto.account = book
        book.conti = [conto]
        container.mainContext.insert(book)
        let groceries = FinanceCore.Category(name: "Alimentari", icon: "basket")
        let bills = FinanceCore.Category(name: "Bollette", icon: "bolt")
        let subscriptions = FinanceCore.Category(name: "Abbonamenti", icon: "play.rectangle")
        for category in [groceries, bills, subscriptions] {
            category.account = book
            container.mainContext.insert(category)
        }
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .month, for: Date())!.start
        @MainActor func add(_ date: Date, _ title: String, _ amount: Decimal, category: FinanceCore.Category, recurring: Bool = false) {
            let row = FinanceCore.Transaction(amount: amount, type: .expense, date: date,
                transactionDescription: title, isRecurring: recurring, recurrenceFrequency: recurring ? .monthly : nil)
            row.setFromConto(conto)
            row.category = category
            row.categoryId = category.id
            container.mainContext.insert(row)
        }
        add(calendar.date(byAdding: .day, value: 2, to: start)!, "Spesa illustrativa", 45, category: groceries)
        if ProcessInfo.processInfo.arguments.contains("UITEST_TIMELINE_PINNING") {
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: start)!
            let day = calendar.date(byAdding: .day, value: 2, to: nextMonth)!
            for index in 1...6 {
                add(calendar.date(byAdding: .hour, value: index, to: day)!,
                    "Movimento illustrativo \(index)", Decimal(index * 10), category: groceries)
            }
        }
        add(calendar.date(byAdding: .day, value: 19, to: start)!, "Scadenza illustrativa", 120, category: bills)
        let prior = calendar.date(byAdding: .month, value: -1, to: start)!
        add(calendar.date(byAdding: .day, value: 14, to: prior)!, "Ricorrenza illustrativa", 60, category: subscriptions, recurring: true)
        try! container.mainContext.save()
        return (container, conto.id)
    }()
    var body: some View {
        NavigationStack {
            FinanceCalendarView(contoIDs: [Self.data.1], currency: "EUR")
        }.modelContainer(Self.data.0)
    }
}
#endif

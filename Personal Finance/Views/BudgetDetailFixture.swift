#if DEBUG
import SwiftUI
import SwiftData
import FinanceCore

struct BudgetDetailFixture: View {
    @State private var state = AppStateManager(persistsSelection: false)
    private let container: ModelContainer
    private let book: Account

    init() {
        container = try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        book = Account(name: "Libro budget", currency: "EUR")
        context.insert(book)
        let conto = Conto(name: "Conto demo", type: .checking)
        conto.account = book; context.insert(conto)
        let category = FinanceCategory(name: "Alimentari", icon: "cart")
        category.account = book; context.insert(category)
        let unused = FinanceCategory(name: "Viaggi", icon: "airplane")
        unused.account = book; context.insert(unused)
        let budget = FinanceBudget(name: "Alimentari", amount: 100, period: .monthly)
        budget.account = book; budget.categories = [category]; context.insert(budget)
        let overlapping = FinanceBudget(name: "Generale", amount: 300, period: .quarterly)
        overlapping.account = book; overlapping.categories = [category]; context.insert(overlapping)
        let empty = FinanceBudget(name: "Viaggi", amount: 200, period: .monthly)
        empty.account = book; empty.categories = [unused]; context.insert(empty)
        let range = budget.currentPeriodRange
        func add(_ amount: Decimal, _ description: String, _ date: Date, type: TransactionType = .expense) {
            let transaction = FinanceTransaction(amount: amount, type: type, date: date)
            transaction.transactionDescription = description
            transaction.setCategory(category); transaction.setFromConto(conto)
            context.insert(transaction)
        }
        add(70, "Supermercato", range.start)
        add(50, "Cena", range.start.addingTimeInterval(3600))
        add(5, "Caffè", range.start.addingTimeInterval(7200))
        add(10, "Spesa futura", range.end.addingTimeInterval(-1))
        add(999, "Entrata esclusa", range.start, type: .income)
        add(999, "Periodo precedente", range.start.addingTimeInterval(-1))
        try! context.save()
    }

    var body: some View {
        BudgetView(showsCloseButton: false)
            .environment(state)
            .modelContainer(container)
            .environment(\.locale, Locale(identifier: "it_IT"))
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("UITEST_VISUAL_DARK") ? .dark : .light)
            .onAppear { state.selectAccount(book) }
    }
}
#endif

import FinanceCore
import Foundation

/// Synthetic data only: the widget gallery must never show the user's finances,
/// and a "Dati nascosti" preview tells nothing about what the widget does.
enum FinanceWidgetSample {
    static let snapshot: FinanceWidgetSnapshot = {
        let now = Date()
        let calendar = Calendar.current
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: now)! }

        let book = Account(name: "Personale", currency: "EUR")
        let checking = Conto(name: "Conto corrente", type: .checking, initialBalance: 2_400)
        let savings = Conto(name: "Risparmi", type: .savings, initialBalance: 5_200)
        for conto in [checking, savings] { conto.account = book }
        book.conti = [checking, savings]

        let groceries = Category(name: "Spesa", color: CategoryPalette.terracotta, icon: "cart")
        let budget = Budget(name: "Spesa e casa", amount: 400, period: .monthly)
        budget.account = book
        budget.categories = [groceries]

        // Past expenses drive the month total, the budget and the balance curve.
        let past: [(String, Decimal, Int, FinanceCore.Category?)] = [
            ("Supermercato", 86.40, -2, groceries), ("Mercato", 32.10, -5, groceries),
            ("Supermercato", 74.25, -9, groceries), ("Ristorante", 48, -4, nil), ("Carburante", 60, -7, nil)
        ]
        var transactions = past.map { title, amount, offset, category in
            let row = Transaction(amount: amount, type: .expense, date: day(offset), transactionDescription: title)
            if let category { row.setCategory(category) }
            row.setFromConto(checking)
            return row
        }

        // Scheduled movements feed the upcoming widget and the projected balance.
        let upcoming: [(String, Decimal, TransactionType, Int, String, String)] = [
            ("Abbonamento musica", 10.99, .expense, 1, CategoryPalette.albicocca, "play.tv"),
            ("Spesa settimanale", 65, .expense, 1, CategoryPalette.terracotta, "cart"),
            ("Bolletta luce", 48.50, .expense, 1, CategoryPalette.prugna, "bolt"),
            ("Stipendio", 1_800, .income, 3, CategoryPalette.ottanio, "dollarsign.circle"),
            ("Affitto", 650, .expense, 12, CategoryPalette.prugna, "key"),
            ("Palestra", 35, .expense, 16, CategoryPalette.albicocca, "figure.run")
        ]
        transactions += upcoming.map { title, amount, type, offset, color, icon in
            let row = Transaction(amount: amount, type: type, date: day(offset), transactionDescription: title,
                                  isRecurring: true, recurrenceFrequency: .monthly)
            row.setCategory(Category(name: title, color: color, icon: icon))
            if type == .income { row.setToConto(checking) } else { row.setFromConto(checking) }
            return row
        }

        return FinanceWidgetBuilder.build(accounts: [book], budgets: [budget], transactions: transactions,
                                          resolutions: [], now: now)
    }()

    static var bookID: UUID? { snapshot.books.first?.id }
}

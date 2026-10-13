#if DEBUG
import SwiftUI
import SwiftData
import FinanceCore

struct NavigationVisualFixture: View {
    @State private var state = AppStateManager(persistsSelection: false)
    @State private var ready = false
    private static let container = try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)

    var body: some View {
        Group {
            if ready { MainTabView() } else { ProgressView() }
        }
        .environment(state)
        .modelContainer(Self.container)
        .environment(\.locale, Locale(identifier: "it_IT"))
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("UITEST_VISUAL_DARK") ? .dark : .light)
        .task {
            guard !ready else { return }
            do {
                let planningReview = ProcessInfo.processInfo.arguments.contains("UITEST_PLANNING_REVIEW")
                state.setOptionalTabs(planningReview ? [.planning, .accounts, .search] : [.planning])
                let id = try await DemoDataService(modelContext: Self.container.mainContext).generateDemoData()
                let books = try Self.container.mainContext.fetch(FetchDescriptor<Account>())
                if let book = books.first(where: { $0.id == id }) {
                    state.selectAccount(book)
                    if planningReview, let conto = book.activeConti.first {
                        let calendar = Calendar.current
                        let today = calendar.startOfDay(for: Date())
                        for (name, amount, day) in [("Internet casa", Decimal(string: "49.90")!, -3), ("Affitto", Decimal(680), 4)] {
                            let due = calendar.date(byAdding: .day, value: day, to: today)!
                            let seed = calendar.date(byAdding: .month, value: -1, to: due)!
                            let transaction = FinanceTransaction(amount: amount, type: .expense, date: seed,
                                transactionDescription: name, isRecurring: true, recurrenceFrequency: .monthly)
                            transaction.setFromConto(conto)
                            transaction.setCategory(book.categories?.first { $0.fits(.expense) })
                            Self.container.mainContext.insert(transaction)
                        }
                        for (name, type, balance) in [("Contanti", ContoType.cash, Decimal(85)), ("Risparmio", .savings, Decimal(3200)), ("Carta di credito", .credit, Decimal(-240))] {
                            let extra = Conto(name: name, type: type, initialBalance: balance)
                            extra.account = book
                            if type == .credit { extra.creditLimit = 1500 }
                            Self.container.mainContext.insert(extra)
                        }
                        if ProcessInfo.processInfo.arguments.contains("UITEST_BALANCES_VERIFIED") {
                            for candidate in book.activeConti {
                                let now = Date()
                                candidate.balanceVerifiedAt = now
                                candidate.balanceVerificationFingerprint = BalanceReconciliation.verificationFingerprint(for: candidate, through: now)
                            }
                        }
                        try Self.container.mainContext.save()
                        state.selectTab(ProcessInfo.processInfo.arguments.contains("UITEST_PLANNING_ACCOUNTS") ? .accounts :
                            ProcessInfo.processInfo.arguments.contains("UITEST_PLANNING_SEARCH") ? .search : .planning)
                    }
                }
                ready = true
            } catch { assertionFailure(error.localizedDescription) }
        }
    }
}
#endif

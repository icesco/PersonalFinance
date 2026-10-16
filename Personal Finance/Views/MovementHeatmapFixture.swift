#if DEBUG
import SwiftUI
import SwiftData
import FinanceCore

struct MovementHeatmapFixture: View {
    @State private var state = AppStateManager(persistsSelection: false)
    private static let data: (ModelContainer, Set<UUID>, Date) = {
        let container = try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let book = Account(name: "Heatmap illustrativa", currency: "EUR")
        let bank = Conto(name: "Corrente", type: .checking, initialBalance: 2000)
        let joint = Conto(name: "Cointestato", type: .checking, initialBalance: 1000)
        let reserve = Conto(name: "Riserva", type: .savings, initialBalance: 500)
        context.insert(book)
        for conto in [bank, joint, reserve] { conto.account = book; context.insert(conto) }
        let category = FinanceCore.Category(name: "Spese illustrative", icon: "basket")
        category.account = book; context.insert(category)
        let calendar = Calendar.current
        let month = calendar.date(byAdding: .month, value: -1, to: calendar.dateInterval(of: .month, for: Date())!.start)!
        func add(_ day: Int, _ amount: Decimal, _ type: TransactionType, _ title: String, from: Conto? = nil, to: Conto? = nil) {
            let date = calendar.date(byAdding: .day, value: day - 1, to: month)!
            let row = FinanceCore.Transaction(amount: amount, type: type, date: date, transactionDescription: title)
            row.setFromConto(from); row.setToConto(to); row.setCategory(category); context.insert(row)
        }
        add(1, 2450, .income, "Entrata illustrativa", to: bank)
        add(1, 650, .expense, "Affitto illustrativo", from: bank)
        add(3, 65, .expense, "Spesa illustrativa", from: joint)
        add(5, 4.5, .expense, "Bar illustrativo", from: bank)
        add(8, 75, .income, "Rimborso illustrativo", to: bank)
        add(8, 75, .expense, "Acquisto illustrativo", from: bank)
        add(12, 300, .transfer, "Accantonamento illustrativo", from: bank, to: reserve)
        add(14, 42, .expense, "Cena illustrativa", from: joint)
        try! context.save()
        return (container, Set([bank.id, joint.id, reserve.id]), month)
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Analisi · dati illustrativi").font(.subheadline).foregroundStyle(.secondary)
                    MovementHeatmapPreview(contoIDs: Self.data.1, currency: "EUR", initialDate: Self.data.2)
                }.frame(maxWidth: 760).frame(maxWidth: .infinity).padding(20)
            }.themedBackground(tint: .clear).navigationTitle("Analisi")
                .environment(\.financeCardSurfaceStyle, .themed)
        }.modelContainer(Self.data.0)
            .environment(state)
            .environment(\.locale, Locale(identifier: "it_IT"))
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("UITEST_VISUAL_DARK") ? .dark : .light)
    }
}
#endif

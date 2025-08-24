import SwiftUI
import SwiftData
import FinanceCore

struct ContoDetailView: View {
    let conto: Conto
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var navigationRouter
    
    var body: some View {
        List {
            Section {
                ContoSummaryCard(conto: conto)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            
            Section {
                Button("Nuova Transazione") {
                    navigationRouter.presentTransactionCreation(for: conto, type: .expense)
                }
                .foregroundStyle(.blue)
                
                Button("Nuova Entrata") {
                    navigationRouter.presentTransactionCreation(for: conto, type: .income)
                }
                .foregroundStyle(.green)
                
                Button("Trasferimento") {
                    navigationRouter.presentTransfer(from: conto)
                }
                .foregroundStyle(.orange)
            }
            
            if !conto.allTransactions.isEmpty {
                Section("Transazioni Recenti") {
                    ForEach(conto.allTransactions.prefix(20), id: \.id) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                }
            }
        }
        .navigationTitle(conto.name ?? "Conto")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct ContoSummaryCard: View {
    let conto: Conto
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: conto.type?.icon ?? "questionmark.circle")
                    .font(.title2)
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(conto.name ?? "Unknown Conto")
                        .font(.headline)
                    Text(conto.type?.displayName ?? "Unknown Type")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Saldo Attuale")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(conto.balance.currencyFormatted)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(conto.balance >= 0 ? .primary : Color.red)
                }
            }
            
            if (conto.initialBalance ?? 0) != 0 || !conto.allTransactions.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Saldo Iniziale")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text((conto.initialBalance ?? 0).currencyFormatted)
                            .font(.subheadline.weight(.medium))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Transazioni")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(conto.allTransactions.count)")
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct TransactionRow: View {
    let transaction: FinanceTransaction
    
    var body: some View {
        HStack {
            Image(systemName: transaction.type?.icon ?? "questionmark.circle")
                .foregroundStyle(colorForTransactionType(transaction.type))
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                if let transactionDescription = transaction.transactionDescription, !transactionDescription.isEmpty {
                    Text(transactionDescription)
                        .font(.headline)
                } else {
                    Text(transaction.type?.displayName ?? "Transaction")
                        .font(.headline)
                }
                
                HStack {
                    if let category = transaction.category {
                        Text(category.name ?? "No Category")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(transaction.date ?? Date(), style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Text(formatAmount(transaction))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(colorForAmount(transaction))
        }
    }
    
    private func colorForTransactionType(_ type: TransactionType?) -> Color {
        switch type {
        case .income: return .green
        case .expense: return Color.red
        case .transfer: return .orange
        case .none: return .gray
        }
    }
    
    private func formatAmount(_ transaction: FinanceTransaction) -> String {
        let amount = transaction.amount ?? 0
        switch transaction.type {
        case .income:
            return "+\(amount.currencyFormatted)"
        case .expense:
            return "-\(amount.currencyFormatted)"
        case .transfer:
            // Check if this is incoming or outgoing transfer
            if transaction.toConto != nil {
                return "+\(amount.currencyFormatted)"
            } else {
                return "-\(amount.currencyFormatted)"
            }
        case .none:
            return "\(amount.currencyFormatted)"
        }
    }
    
    private func colorForAmount(_ transaction: FinanceTransaction) -> Color {
        switch transaction.type {
        case .income: return .green
        case .expense: return Color.red
        case .transfer:
            if transaction.toConto != nil {
                return .green
            } else {
                return Color.red
            }
        case .none: return .primary
        }
    }
}

struct ContoDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let container = try! FinanceCoreModule.createModelContainer(inMemory: true)
        let account = Account(name: "Test Account")
        container.mainContext.insert(account)
        
        let conto = Conto(name: "Test Conto", type: .checking, initialBalance: 1000)
        conto.account = account
        container.mainContext.insert(conto)
        
        let category = FinanceCategory(name: "Food")
        category.account = account
        container.mainContext.insert(category)
        
        let transaction = FinanceTransaction(amount: 50, type: .expense, transactionDescription: "Grocery shopping")
        transaction.fromConto = conto
        transaction.category = category
        container.mainContext.insert(transaction)
        
        return NavigationStack {
            ContoDetailView(conto: conto)
        }
        .modelContainer(container)
    }
}

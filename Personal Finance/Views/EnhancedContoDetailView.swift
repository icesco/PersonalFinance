import SwiftUI
import SwiftData
import FinanceCore

struct EnhancedContoDetailView: View {
    let conto: Conto
    
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    
    @State private var selectedPeriod: AnalysisPeriod = .month
    @State private var showingTransactionFilter = false
    @State private var selectedTransactionType: TransactionType? = nil
    
    // Computed properties for analysis
    private var transactions: [FinanceTransaction] {
        conto.allTransactions.filter { transaction in
            guard let date = transaction.date else { return false }
            let range = selectedPeriod.dateRange
            return date >= range.start && date < range.end
        }
    }
    
    private var filteredTransactions: [FinanceTransaction] {
        if let type = selectedTransactionType {
            return transactions.filter { $0.type == type }
        }
        return transactions
    }
    
    private var totalIncome: Decimal {
        transactions
            .filter { $0.type == .income }
            .reduce(0) { $0 + ($1.amount ?? 0) }
    }
    
    private var totalExpenses: Decimal {
        transactions
            .filter { $0.type == .expense }
            .reduce(0) { $0 + ($1.amount ?? 0) }
    }
    
    private var netFlow: Decimal {
        totalIncome - totalExpenses
    }
    
    private var categoryBreakdown: [CategorySpending] {
        let grouped = Dictionary(grouping: transactions.filter { $0.type == .expense }) { $0.category }
        
        return grouped.compactMap { (category, transactions) -> CategorySpending? in
            guard let cat = category else { return nil }
            let amount = transactions.reduce(0) { $0 + ($1.amount ?? 0) }
            let percentage = totalExpenses > 0 ? Double(truncating: amount as NSDecimalNumber) / Double(truncating: totalExpenses as NSDecimalNumber) * 100 : 0
            
            return CategorySpending(
                category: cat,
                amount: amount,
                percentage: percentage,
                transactionCount: transactions.count
            )
        }
        .sorted { $0.amount > $1.amount }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Header with balance and basic info
                headerSection
                
                // Period selector
                periodSelector
                
                // Financial overview cards
                overviewCards
                
                // Category breakdown
                if !categoryBreakdown.isEmpty {
                    categoryBreakdownSection
                }
                
                // Transaction list
                transactionListSection
            }
            .padding()
        }
        .navigationTitle(conto.name ?? "Conto")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Nuova Transazione") {
                        // Add transaction action
                    }
                    
                    Button("Modifica Conto") {
                        // Edit account action
                    }
                    
                    Button("Esporta Dati") {
                        // Export data action
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Account icon and name
            HStack {
                Image(systemName: conto.type?.icon ?? "questionmark.circle")
                    .font(.title)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading) {
                    Text(conto.name ?? "Conto Sconosciuto")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(conto.type?.displayName ?? "Tipo sconosciuto")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Current balance
            VStack(alignment: .leading, spacing: 8) {
                Text("Saldo Attuale")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(conto.balance.currencyFormatted)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(conto.balance >= 0 ? .primary : .red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2)
    }
    
    // MARK: - Period Selector
    
    private var periodSelector: some View {
        Picker("Periodo", selection: $selectedPeriod) {
            ForEach(AnalysisPeriod.allCases, id: \.self) { period in
                Text(period.displayName).tag(period)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
    }
    
    // MARK: - Overview Cards
    
    private var overviewCards: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            // Income card
            EnhancedOverviewCard(
                title: "Entrate",
                amount: totalIncome,
                icon: "arrow.down.circle.fill",
                color: .green
            )
            
            // Expenses card
            EnhancedOverviewCard(
                title: "Spese",
                amount: totalExpenses,
                icon: "arrow.up.circle.fill",
                color: .red
            )
            
            // Net flow card
            EnhancedOverviewCard(
                title: "Flusso Netto",
                amount: netFlow,
                icon: netFlow >= 0 ? "plus.circle.fill" : "minus.circle.fill",
                color: netFlow >= 0 ? .green : .red
            )
            
            // Transaction count card
            EnhancedOverviewCard(
                title: "Transazioni",
                value: "\(filteredTransactions.count)",
                icon: "list.bullet",
                color: .blue
            )
        }
    }
    
    // MARK: - Category Breakdown Section
    
    private var categoryBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spese per Categoria")
                .font(.headline)
            
            LazyVStack(spacing: 8) {
                ForEach(categoryBreakdown.prefix(5), id: \.category.id) { item in
                    CategoryBreakdownRow(
                        category: item.category,
                        amount: item.amount,
                        percentage: item.percentage,
                        transactionCount: item.transactionCount
                    )
                }
                
                if categoryBreakdown.count > 5 {
                    Button("Vedi Tutte le Categorie") {
                        // Show all categories
                    }
                    .foregroundColor(.accentColor)
                    .padding(.top, 8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2)
    }
    
    // MARK: - Transaction List Section
    
    private var transactionListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transazioni")
                    .font(.headline)
                
                Spacer()
                
                Menu {
                    Button("Tutte") {
                        selectedTransactionType = nil
                    }
                    
                    Button("Entrate") {
                        selectedTransactionType = .income
                    }
                    
                    Button("Spese") {
                        selectedTransactionType = .expense
                    }
                    
                    Button("Trasferimenti") {
                        selectedTransactionType = .transfer
                    }
                } label: {
                    HStack {
                        Text(selectedTransactionType?.displayName ?? "Tutte")
                        Image(systemName: "chevron.down")
                    }
                    .foregroundColor(.accentColor)
                }
            }
            
            if filteredTransactions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "list.bullet")
                        .font(.title)
                        .foregroundColor(.secondary)
                    
                    Text("Nessuna Transazione")
                        .font(.headline)
                    
                    Text("Non ci sono transazioni per il periodo selezionato")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 32)
            } else {
                LazyVStack(spacing: 1) {
                    ForEach(filteredTransactions, id: \.id) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2)
    }
}

// MARK: - Supporting Views

struct EnhancedOverviewCard: View {
    let title: String
    let amount: Decimal?
    let value: String?
    let icon: String
    let color: Color
    
    init(title: String, amount: Decimal, icon: String, color: Color) {
        self.title = title
        self.amount = amount
        self.value = nil
        self.icon = icon
        self.color = color
    }
    
    init(title: String, value: String, icon: String, color: Color) {
        self.title = title
        self.amount = nil
        self.value = value
        self.icon = icon
        self.color = color
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let amount = amount {
                Text(amount.currencyFormatted)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else if let value = value {
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

struct CategoryBreakdownRow: View {
    let category: FinanceCategory
    let amount: Decimal
    let percentage: Double
    let transactionCount: Int
    
    var body: some View {
        HStack {
            // Category icon
            Image(systemName: category.icon ?? "tag")
                .foregroundColor(Color(hex: category.color ?? "#007AFF"))
                .frame(width: 24)
            
            // Category info
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name ?? "Categoria Sconosciuta")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(transactionCount) transazioni")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Amount and percentage
            VStack(alignment: .trailing, spacing: 2) {
                Text(amount.currencyFormatted)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(percentage, specifier: "%.1f")%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct CategorySpending {
    let category: FinanceCategory
    let amount: Decimal
    let percentage: Double
    let transactionCount: Int
}

// MARK: - Color Extension (if not already available)

// Color hex extension removed - already defined in CreateContoView
/*extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}*/

#Preview {
    NavigationView {
        // Preview implementation would need mock data
        Text("Conto Detail Preview")
    }
}
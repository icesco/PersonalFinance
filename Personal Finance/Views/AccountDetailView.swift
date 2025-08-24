import SwiftUI
import SwiftData
import FinanceCore

struct AccountDetailView: View {
    let account: Account
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var navigationRouter
    
    var body: some View {
        contiList
            .navigationTitle(account.name ?? "Account")
            .navigationBarTitleDisplayMode(.large)
    }
    
    private var contiList: some View {
        List {
            Section {
                OverviewCard(account: account)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            
            Section("I Tuoi Conti") {
                ForEach(account.activeConti ?? []) { conto in
                    Button {
                        navigationRouter.navigateToContoDetail(conto)
                    } label: {
                        ContoRow(conto: conto)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Nuovo Conto", systemImage: "plus") {
                    navigationRouter.presentContoCreation(for: account)
                }
            }
        }
    }
}

struct OverviewCard: View {
    let account: Account
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Patrimonio Totale")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(account.totalBalance.currencyFormatted)
                        .font(.title.weight(.semibold))
                        .foregroundStyle(account.totalBalance >= 0 ? Color(.label) : Color.red)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(account.conti?.count ?? 0)")
                        .font(.title2.weight(.semibold))
                    Text("Conti")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if !(account.conti?.isEmpty ?? true) {
                HStack(spacing: 12) {
                    ForEach(ContoType.allCases.prefix(4), id: \.self) { type in
                        let conti = account.conti?.filter { $0.type == type } ?? []
                        if !conti.isEmpty {
                            VStack(spacing: 4) {
                                Image(systemName: type.icon)
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                                
                                Text("\(conti.count)")
                                    .font(.caption.weight(.medium))
                                
                                Text(type.displayName.prefix(5))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ContoRow: View {
    let conto: Conto
    
    var body: some View {
        HStack {
            Image(systemName: conto.type?.icon ?? "questionmark.circle")
                .foregroundStyle(.blue)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(conto.name ?? "Unknown Conto")
                    .font(.headline)
                Text(conto.type?.displayName ?? "Unknown Type")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(conto.balance.currencyFormatted)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(conto.balance >= 0 ? Color(.label) : Color.red)
                
                if !conto.allTransactions.isEmpty {
                    Text("\(conto.allTransactions.count) transazioni")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct AccountDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let container = try! FinanceCoreModule.createModelContainer(inMemory: true)
        let account = Account(name: "Test Account")
        container.mainContext.insert(account)
        
        let conto = Conto(name: "Test Conto", type: .checking, initialBalance: 1000)
        conto.account = account
        container.mainContext.insert(conto)
        
        return AccountDetailView(account: account)
            .modelContainer(container)
    }
}

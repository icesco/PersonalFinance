import SwiftUI
import FinanceCore

struct FinanceContoDetailsView: View {
    let conto: Conto
    @State private var editing = false
    private var currency: String { conto.account?.currency ?? "EUR" }
    private var recentTransactions: [FinanceTransaction] {
        var seen = Set<UUID>()
        return Array(conto.allTransactions.filter { $0.date <= Date() && seen.insert($0.id).inserted }.prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                balanceHeader
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ForgiaPalette.sageSurface)

                VStack(alignment: .leading, spacing: 24) {
                    if let interval = Calendar.current.dateInterval(of: .month, for: Date()) {
                        InlineBalanceHistoryCard(scopeContoIDs: [conto.id], interval: interval,
                            currency: currency, periodTitle: Date().formatted(.dateTime.month(.wide).year()),
                            historyBookID: conto.account?.id, historyContoID: conto.id)
                    }
                    recentMovements
                    if conto.type == .savings {
                        SavingsAccountSummary(conto: conto)
                    }
                    accountInformation
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .themedBackground()
        .navigationTitle(conto.name ?? "Conto")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Modifica", systemImage: "pencil") { editing = true }
            }
        }
        .financePresentation(isPresented: $editing, title: "Modifica conto") { EditContoView(conto: conto) }
    }

    private var balanceHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            if conto.type == .credit {
                CreditAccountCard(conto: conto)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 12) {
                    ContoLogo(conto: conto, size: 40)
                    Text(conto.type?.displayName ?? "Conto")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ContoBalanceView(conto: conto)
            }
            HStack {
                Text(conto.account?.name ?? "Libro")
                if conto.isActive != true { Text("Archiviato") }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var recentMovements: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ultimi movimenti").font(.title3.weight(.semibold))
                Spacer()
                NavigationLink {
                    TransactionListView(initialConto: conto, isPushed: true)
                } label: {
                    Text("Vedi tutti").font(.subheadline).frame(minHeight: 44)
                }
            }
            VStack(spacing: 0) {
                let transactions = recentTransactions
                if transactions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nessun movimento registrato").font(.subheadline.weight(.medium))
                        Text("I movimenti di questo conto compariranno qui.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                } else {
                    ForEach(transactions) { transaction in
                        NavigationLink { TransactionDetailView(transaction: transaction) } label: {
                            CompactTransactionRow(transaction: transaction, currency: currency,
                                showConto: false, showsDisclosure: true)
                        }.buttonStyle(.plain)
                        if transaction.id != transactions.last?.id {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
            }.unifiedCard()
        }
    }

    private var accountInformation: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let description = conto.contoDescription, !description.isEmpty {
                Text(description).font(.subheadline).foregroundStyle(.secondary)
            }
            if conto.type == .credit, conto.statementClosingDay != nil || conto.paymentDueDay != nil {
                VStack(spacing: 12) {
                    if let day = conto.statementClosingDay {
                        LabeledContent("Chiusura estratto conto", value: "Giorno \(day)")
                    }
                    if let day = conto.paymentDueDay {
                        LabeledContent("Addebito", value: "Giorno \(day)")
                    }
                }.font(.subheadline).unifiedCard()
            }

        }
    }
}

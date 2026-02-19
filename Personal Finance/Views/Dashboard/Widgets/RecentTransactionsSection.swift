//
//  RecentTransactionsSection.swift
//  Personal Finance
//

import SwiftUI
import FinanceCore

struct RecentTransactionsSection: View {
    let transactions: [FinanceTransaction]
    var onViewAll: (() -> Void)?
    var onTapTransaction: ((FinanceTransaction) -> Void)?
    var onEditTransaction: ((FinanceTransaction) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ultime transazioni")
                    .font(.headline)
                Spacer()
                Button("Vedi tutte") { onViewAll?() }
                    .font(.subheadline)
            }

            if transactions.isEmpty {
                ContentUnavailableView {
                    Label("Nessuna transazione", systemImage: "list.bullet")
                } description: {
                    Text("Le tue transazioni appariranno qui")
                }
            } else {
                ForEach(transactions, id: \.id) { transaction in
                    TransactionRowView(transaction: transaction)
                        .contentShape(Rectangle())
                        .onTapGesture { onTapTransaction?(transaction) }
                        .contextMenu {
                            Button {
                                onTapTransaction?(transaction)
                            } label: {
                                Label("Dettagli", systemImage: "info.circle")
                            }
                            Button {
                                onEditTransaction?(transaction)
                            } label: {
                                Label("Modifica", systemImage: "pencil")
                            }
                        }

                    if transaction.id != transactions.last?.id {
                        Divider()
                    }
                }
            }
        }
        .unifiedCard()
    }
}

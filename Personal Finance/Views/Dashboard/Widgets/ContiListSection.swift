//
//  ContiListSection.swift
//  Personal Finance
//

import SwiftUI
import FinanceCore

struct ContiListSection: View {
    let conti: [Conto]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("I tuoi conti").font(.headline)

            if conti.isEmpty {
                ContentUnavailableView {
                    Label("Nessun conto", systemImage: "creditcard")
                } description: {
                    Text("Aggiungi il tuo primo conto")
                }
            } else {
                ForEach(conti, id: \.id) { conto in
                    NavigationLink {
                        TransactionListView(initialConto: conto)
                    } label: {
                        ContoRowView(conto: conto)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .offset(y: 8)))
                }
            }
        }
        .unifiedCard()
    }
}

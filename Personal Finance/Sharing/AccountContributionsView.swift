import SwiftUI
import SwiftData
import FinanceCore

struct AccountContributionsView: View {
    let conto: Conto
    @Query private var memberships: [SharedBookMembership]
    @State private var month = Date()
    private var isShared: Bool { memberships.contains { $0.localContoID == conto.id } }

    var body: some View {
        if isShared, let interval = Calendar.current.dateInterval(of: .month, for: month) {
            let rows = AccountContributions.summarize(conto: conto, interval: interval)
            VStack(alignment: .leading, spacing: 12) {
                Text("Versamenti di ciascuno").font(.title3.weight(.semibold))
                HStack {
                    Button("Mese precedente", systemImage: "chevron.left") { shiftMonth(-1) }
                        .labelStyle(.iconOnly).frame(width: 44, height: 44)
                    Spacer()
                    Text(month, format: .dateTime.month(.wide).year()).font(.subheadline)
                    Spacer()
                    Button("Mese successivo", systemImage: "chevron.right") { shiftMonth(1) }
                        .labelStyle(.iconOnly).frame(width: 44, height: 44)
                }
                VStack(alignment: .leading, spacing: 14) {
                    if rows.isEmpty {
                        Text("Nessun versamento registrato in questo mese.").foregroundStyle(.secondary)
                    }
                    ForEach(rows) { row in
                        HStack(alignment: .firstTextBaseline) {
                            Text(name(row.person))
                            Spacer(minLength: 16)
                            Text(row.amount, format: .currency(code: conto.account?.currency ?? "EUR"))
                                .monospacedDigit().fontWeight(.semibold)
                        }
                    }
                    Text("Sono trasferimenti, quindi non aumentano il reddito e non sono spese di casa. I versamenti senza una persona indicata restano separati.")
                        .font(.caption).foregroundStyle(.secondary)
                }.unifiedCard()
            }
            .accessibilityIdentifier("account-contributions")
        }
    }
    private func shiftMonth(_ value: Int) {
        if let date = Calendar.current.date(byAdding: .month, value: value, to: month) { month = date }
    }
    private func name(_ person: TransactionPerson?) -> String {
        guard let person else { return String(localized: "Non attribuiti") }
        if person.id == TransactionPeople.current?.id { return String(localized: "Tu") }
        return person.name.isEmpty ? String(localized: "Partecipante") : person.name
    }
}

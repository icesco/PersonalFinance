import SwiftUI
import SwiftData
import FinanceCore

struct TransactionPeopleEditor: View {
    let contoIDs: [UUID]
    let isTransfer: Bool
    @Binding var assignedTo: TransactionPerson?
    @Binding var contributor: TransactionPerson?
    @Query private var memberships: [SharedBookMembership]
    @Query private var conti: [Conto]
    @Query private var transactions: [FinanceTransaction]

    init(contoIDs: [UUID], isTransfer: Bool, assignedTo: Binding<TransactionPerson?>, contributor: Binding<TransactionPerson?>) {
        self.contoIDs = contoIDs; self.isTransfer = isTransfer
        _assignedTo = assignedTo; _contributor = contributor
        _conti = Query(filter: #Predicate<Conto> { contoIDs.contains($0.id) })
        _transactions = Query(filter: #Predicate<FinanceTransaction> { transaction in
            (transaction.fromContoId != nil && contoIDs.contains(transaction.fromContoId!)) ||
            (transaction.toContoId != nil && contoIDs.contains(transaction.toContoId!))
        })
    }

    private var people: [TransactionPerson] {
        var values: [String: TransactionPerson] = [:]
        let bookIDs = Set(conti.compactMap { $0.account?.id })
        for membership in memberships where membership.localContoID.map(contoIDs.contains) == true || (membership.localContoID == nil && bookIDs.contains(membership.localBookID)) {
            if let data = membership.peopleJSON?.data(using: .utf8),
               let members = try? JSONDecoder().decode([TransactionPerson].self, from: data) {
                for person in members { values[person.id] = person }
            }
        }
        for transaction in transactions {
            for person in [transaction.createdBy, transaction.lastEditedBy, transaction.assignedTo, transaction.contributor].compactMap({ $0 }) {
                if values[person.id]?.name.isEmpty != false { values[person.id] = person }
            }
        }
        for person in [assignedTo, contributor, TransactionPeople.current].compactMap({ $0 }) { values[person.id] = person }
        return values.values.sorted { $0.id < $1.id }
    }

    var body: some View {
        let available = people
        HStack {
            Text("Assegnato a")
            Spacer(minLength: 12)
            Picker("Assegnato a", selection: $assignedTo) {
                Text("Nessuno").tag(nil as TransactionPerson?)
                ForEach(available) { person in Text(label(person)).tag(Optional(person)) }
            }.labelsHidden()
        }
        .frame(minHeight: 44)
        if isTransfer {
            HStack {
                Text("Versamento di")
                Spacer(minLength: 12)
                Picker("Versamento di", selection: $contributor) {
                    Text("Non indicato").tag(nil as TransactionPerson?)
                    ForEach(available) { person in Text(label(person)).tag(Optional(person)) }
                }.labelsHidden()
            }
            .frame(minHeight: 44)
            Text("Indica chi versa il denaro, anche quando registri il movimento per un’altra persona.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Text("Chi registra il movimento viene indicato automaticamente quando l’identità iCloud è disponibile.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private func label(_ person: TransactionPerson) -> String {
        if person.id == TransactionPeople.current?.id { return String(localized: "Tu") }
        return person.name.isEmpty ? String(localized: "Partecipante") : person.name
    }
}

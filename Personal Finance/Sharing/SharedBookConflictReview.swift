import SwiftUI
import FinanceCore

struct SharedBookConflictReview: View {
    let conflicts: [SharedBookConflict]
    let referenceCount: Int
    let currency: String
    let enabled: Bool
    let busy: Bool
    @Binding var choices: [SharedRecordID: SharedBookMerge.Side]
    let onApply: () -> Void

    var body: some View {
        if !conflicts.isEmpty || referenceCount > 0 {
            Section("Modifiche da confrontare") {
                Text("Il libro non è stato aggiornato: alcune modifiche richiedono una scelta.")
                ForEach(conflicts, id: \.local.id) { conflict in
                    SharedBookConflictCard(conflict: conflict, currency: currency, choice: Binding(
                        get: { choices[conflict.local.id] }, set: { choices[conflict.local.id] = $0 }
                    )).disabled(busy || !enabled)
                }
                if !conflicts.isEmpty {
                    Button("Applica le scelte", action: onApply)
                        .disabled(!enabled || busy || referenceCount > 0 || conflicts.contains { choices[$0.local.id] == nil })
                        .accessibilityIdentifier("shared-book-apply-choices")
                    Text("Le modifiche compatibili vengono conservate. Se una versione cambia prima della conferma, Formi ti chiederà di confrontarla di nuovo.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if referenceCount > 0 {
                    Text("Ci sono \(referenceCount) collegamenti coinvolti da una cancellazione. Le modifiche restano conservate per il confronto.")
                }
            }
        }
    }
}

#if DEBUG
/// Local UI fixture. It never instantiates the cloud coordinator or transport.
struct SharedBookConflictFixture: View {
    @State private var choices: [SharedRecordID: SharedBookMerge.Side] = [:]
    @State private var confirmed = false
    private static let conflict: SharedBookConflict? = {
        let bookID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let id = SharedRecordID(bookID: bookID, kind: .transaction, entityID: "00000000-0000-0000-0000-000000000011")
        let base = SharedBookRecord(id: id, fields: ["amount": .decimal(20), "description": .text("Spesa demo")])
        var local = base, remote = base
        local.fields["amount"] = .decimal(30); remote.fields["amount"] = .decimal(40)
        if case let .conflict(conflict) = try? SharedBookMerge.merge(base: base, local: local, remote: remote) { return conflict }
        return nil
    }()
    var body: some View {
        NavigationStack {
            List {
                if let conflict = Self.conflict {
                    SharedBookConflictReview(conflicts: [conflict], referenceCount: 0, currency: "EUR", enabled: true, busy: false, choices: $choices) {
                        confirmed = choices[conflict.local.id] != nil
                    }
                }
                if confirmed { Text("Scelta confermata nel test locale").accessibilityIdentifier("shared-conflict-fixture-confirmed") }
            }.navigationTitle("Conflitto demo")
        }
    }
}
#endif

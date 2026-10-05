import SwiftUI
import FinanceCore

struct SharedBookConflictCard: View {
    let conflict: SharedBookConflict
    let currency: String
    @Binding var choice: SharedBookMerge.Side?

    private var keys: [String] {
        if case let .fields(keys) = conflict.reason { return keys }
        return Set(conflict.local.fields.keys).union(conflict.remote.fields.keys)
            .filter { !["externalID", "createdAt", "updatedAt", "book"].contains($0) }.sorted()
    }
    private var name: String {
        for key in ["name", "description", "filename"] {
            if case let .text(name)? = conflict.local.fields[key], !name.isEmpty { return name }
            if case let .text(name)? = conflict.remote.fields[key], !name.isEmpty { return name }
        }
        return "Dato modificato"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(name).font(.headline)
            if conflict.local.deleted || conflict.remote.deleted {
                Label(conflict.local.deleted ? "Eliminato sul dispositivo" : "Eliminato nella versione condivisa", systemImage: "trash")
                    .foregroundStyle(.red)
            }
            ForEach(keys, id: \.self) { key in
                VStack(alignment: .leading, spacing: 4) {
                    Text(label(key)).font(.subheadline.bold())
                    Text("Dispositivo: \(value(conflict.local.fields[key], key: key, deleted: conflict.local.deleted, names: conflict.localReferenceNames))")
                    Text("Condiviso: \(value(conflict.remote.fields[key], key: key, deleted: conflict.remote.deleted, names: conflict.remoteReferenceNames))")
                }.font(.callout).textSelection(.enabled)
            }
            Picker("Versione da conservare", selection: $choice) {
                Text("Scegli una versione").tag(nil as SharedBookMerge.Side?)
                Text(conflict.local.deleted ? "Conferma eliminazione locale" : "Usa versione sul dispositivo").tag(Optional(SharedBookMerge.Side.local))
                Text(conflict.remote.deleted ? "Conferma eliminazione condivisa" : "Usa versione condivisa").tag(Optional(SharedBookMerge.Side.remote))
            }
            .accessibilityIdentifier("shared-conflict-choice-\(conflict.local.id.recordName)")
        }.padding(.vertical, 6)
    }
    private func label(_ key: String) -> String {
        switch key {
        case "amount": "Importo"
        case "destinationAmount": "Importo ricevuto"
        case "initialBalance": "Saldo iniziale"
        case "date", "scheduledDate": "Data"
        case "name": "Nome"
        case "description": "Descrizione"
        case "notes": "Note"
        case "currency", "originalCurrency": "Valuta"
        case "originalAmount": "Importo originale"
        case "exchangeRate": "Cambio"
        case "type": "Tipo"
        case "fromConto": "Conto di origine"
        case "toConto": "Conto di destinazione"
        case "category", "categories", "parent": "Categoria"
        case "isActive": "Attivo"
        case "isRecurring": "Ricorrente"
        case "recurrenceFrequency": "Frequenza"
        case "recurrenceEndDate": "Fine ricorrenza"
        case "filename": "Nome allegato"
        case "contentDigest", "contentType": "Contenuto allegato"
        case "placeName": "Luogo"
        case "latitude", "longitude", "locationAccuracy": "Posizione"
        case "period": "Periodo"
        case "threshold": "Soglia"
        default: "Altra proprietà modificata"
        }
    }
    private func value(_ value: SharedValue?, key: String, deleted: Bool, names: [SharedRecordID: String]?) -> String {
        if deleted { return "Eliminato" }
        guard let value else { return "Non impostato" }
        switch value {
        case let .text(text):
            if key == "contentDigest" { return "Contenuto di questa versione" }
            return text.isEmpty ? "Vuoto" : text
        case let .decimal(amount):
            if ["amount", "destinationAmount", "initialBalance", "targetAmount", "currentAmount", "creditLimit"].contains(key) {
                return amount.formatted(.currency(code: currency))
            }
            return amount.formatted()
        case let .date(date): return date.formatted(date: .abbreviated, time: .shortened)
        case let .flag(flag): return flag ? "Sì" : "No"
        case let .integer(number): return number.formatted()
        case let .number(number): return number.formatted()
        case let .reference(id): return names?[id] ?? "Riferimento senza nome"
        case let .references(values): return values.isEmpty ? "Nessuno" : values.map { names?[$0] ?? "Riferimento senza nome" }.joined(separator: ", ")
        }
    }
}

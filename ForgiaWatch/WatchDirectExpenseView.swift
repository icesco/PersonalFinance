import SwiftUI

struct WatchDirectExpenseView: View {
    let connection: WatchConnection
    let bookID: UUID
    @State private var contoID: UUID?
    @State private var categoryID: UUID?
    @State private var amount = ""
    @State private var note = ""

    var body: some View {
        Form {
            if connection.remote.savedID != nil {
                Label("Spesa registrata", systemImage: "checkmark.circle.fill")
                if let message = connection.message { Text(message).font(.caption) }
                Button("Nuova spesa") {
                    connection.resetRemote()
                    amount = ""; note = ""
                }
            } else if let quote = connection.remote.quote {
                WatchExpenseConfirmation(quote: quote, connection: connection)
            } else if let book = connection.overview.books.first(where: { $0.id == bookID }) {
                Text("\(book.name) · \(book.currency)").font(.caption)
                Picker("Conto", selection: $contoID) {
                    Text("Scegli").tag(nil as UUID?)
                    ForEach(book.conti ?? []) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Categoria", selection: $categoryID) {
                    Text("Scegli").tag(nil as UUID?)
                    ForEach(book.categories ?? []) { Text($0.name).tag(Optional($0.id)) }
                }
                TextField("Importo", text: $amount)
                TextField("Descrizione", text: $note)
                Button("Controlla budget") {
                    guard let contoID, let categoryID else { return }
                    connection.reviewExpense(book: book, contoID: contoID, categoryID: categoryID, amount: amount, note: note)
                }
                .disabled(contoID == nil || categoryID == nil || amount.isEmpty || connection.isSending)
                if let message = connection.message { Text(message).font(.caption) }
            } else {
                Text("Libro non disponibile. Aggiorna Formi su iPhone.")
            }
            if connection.isSending { ProgressView() }
        }
        .navigationTitle("Nuova spesa")
        .task {
            if let input = connection.remote.input, input.bookID == bookID {
                contoID = input.contoID; categoryID = input.categoryID
                amount = NSDecimalNumber(decimal: input.amount).stringValue
                note = input.note
            }
        }
    }
}

struct WatchExpenseConfirmation: View {
    let quote: RemoteExpenseQuote
    let connection: WatchConnection
    var body: some View {
        Section("Conferma spesa") {
            Text(quote.input.amount, format: .currency(code: quote.input.currency)).font(.title2)
            Text("\(quote.bookName) · \(quote.contoName)").font(.caption)
            Text(quote.categoryName).font(.caption)
            if !quote.input.note.isEmpty { Text(quote.input.note).font(.caption) }
        }
        Section("Dopo questa spesa") {
            if quote.budgets.isEmpty {
                Text("Nessun budget associato a questa categoria.").font(.caption)
            }
            ForEach(quote.budgets) { budget in
                VStack(alignment: .leading) {
                    Text(budget.name).font(.headline)
                    Text(budget.remaining, format: .currency(code: quote.input.currency))
                        .foregroundStyle(budget.remaining < 0 ? .red : .primary)
                    Text(budget.remaining < 0 ? "Budget superato" : "Budget residuo").font(.caption2)
                }
            }
            Text("Basato sulle spese registrate. Non indica la disponibilità del conto.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        Button(connection.remote.confirmationWasSent ? "Riprova conferma" : "Conferma e salva") {
            connection.confirmExpense()
        }
        .disabled(connection.isSending)
        if !connection.remote.confirmationWasSent {
            Button("Modifica") { connection.resetRemote() }.disabled(connection.isSending)
        }
        if let message = connection.message { Text(message).font(.caption) }
    }
}

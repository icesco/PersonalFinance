import SwiftUI
import SwiftData
import FinanceCore

struct SharedContoDestinationView: View {
    let scope: SharedBookScope
    let receivedBookID: UUID
    let title: String
    let onComplete: (UUID) -> Void
    @Environment(DataStorageManager.self) private var storage
    @Environment(\.dismiss) private var dismiss
    @Query private var books: [Account]
    @Query private var memberships: [SharedBookMembership]
    @State private var choice: Choice?
    @State private var newName = ""
    @State private var error: String?
    private enum Choice: Hashable { case existing(UUID), newBook }
    private var receivedBook: Account? { books.first { $0.id == receivedBookID } }
    private var eligibleBooks: [Account] {
        books.filter { book in
            book.id != receivedBookID && book.isActive == true && book.currency == receivedBook?.currency &&
            !memberships.contains { $0.localBookID == book.id && $0.localContoID == nil }
        }.sorted { ($0.name ?? "").localizedStandardCompare($1.name ?? "") == .orderedAscending }
    }
    private var canContinue: Bool {
        switch choice {
        case let .existing(id): eligibleBooks.contains { $0.id == id }
        case .newBook: !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && newName.count <= 100
        case nil: false
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(title).font(.headline)
                    Text("Scegli in quale libro aggiungere il conto condiviso. Gli altri conti del libro rimangono privati.")
                        .foregroundStyle(.secondary)
                }
                if !eligibleBooks.isEmpty {
                    Section("I tuoi libri") {
                        ForEach(eligibleBooks) { book in
                            Button { choice = .existing(book.id) } label: {
                                HStack {
                                    Label(book.name ?? "Libro", systemImage: "book.closed")
                                    Spacer(minLength: 12)
                                    if choice == .existing(book.id) { Image(systemName: "checkmark") }
                                }.frame(minHeight: 44).contentShape(Rectangle())
                            }
                            .accessibilityIdentifier("shared-conto-book-\(book.id)")
                        }
                    }
                }
                Section {
                    Button { choice = .newBook } label: {
                        HStack {
                            Label("Crea un nuovo libro", systemImage: "plus")
                            Spacer(minLength: 12)
                            if choice == .newBook { Image(systemName: "checkmark") }
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("shared-conto-new-book")
                    if choice == .newBook {
                        TextField("Nome del libro", text: $newName)
                            .accessibilityIdentifier("shared-conto-new-book-name")
                    }
                } footer: {
                    Text("Puoi scegliere un libro nella valuta del conto, oppure crearne uno dedicato alle spese condivise.")
                }
                Section {
                    Button("Aggiungi conto", action: complete)
                        .frame(minHeight: 44)
                        .disabled(!canContinue)
                        .accessibilityIdentifier("shared-conto-complete-acceptance")
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Dove aggiungere il conto")
            .toolbarTitleDisplayMode(.inline)
            .toolbar { FinanceDismissToolbar { Button("Scegli più tardi") { dismiss() } } }
            .onAppear { if newName.isEmpty { newName = title } }
        }
    }

    private func complete() {
        guard canContinue, let choice, let container = storage.currentContainer else { return }
        let destination: SharedContoPlacement.Destination
        switch choice {
        case let .existing(id): destination = .existing(id)
        case .newBook: destination = .newBook(name: newName)
        }
        do {
            let id = try SharedContoPlacement.completeAcceptance(scope: scope, destination: destination, container: container)
            onComplete(id)
            dismiss()
        } catch {
            self.error = "Il conto non è stato inserito nel libro scelto. I dati ricevuti restano disponibili: scegli un altro libro o riprova."
        }
    }
}

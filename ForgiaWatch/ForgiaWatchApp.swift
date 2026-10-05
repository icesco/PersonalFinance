import SwiftUI

@main
struct ForgiaWatchApp: App {
    @State private var connection = WatchConnection()
    @State private var showExpense = false
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            WatchHomeView(connection: connection)
                .tint(.orange)
                .onChange(of: phase) { _, phase in if phase == .active { connection.refresh() } }
                .onOpenURL { url in
                    guard url.absoluteString == "forgia://watch/expense" else { return }
                    showExpense = true
                }
                .sheet(isPresented: $showExpense) {
                    NavigationStack {
                        WatchExpenseView(connection: connection, book: nil)
                    }
                }
        }
    }
}

struct WatchHomeView: View {
    let connection: WatchConnection
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            NavigationStack {
                List {
                    if let draft = connection.pendingDraft {
                        NavigationLink {
                            WatchExpenseView(connection: connection,
                                             book: connection.overview.usable(at: context.date)
                                                ? connection.overview.books.first { $0.id == draft.bookID } : nil,
                                             restoredDraft: draft)
                        } label: {
                            Label("Bozza da inviare", systemImage: "tray.and.arrow.up")
                        }
                    }
                    NavigationLink {
                        WatchExpenseView(connection: connection, book: nil)
                    } label: { Label("Prepara spesa", systemImage: "plus.circle.fill") }
                    if connection.overview.usable(at: context.date) {
                        ForEach(connection.overview.books) { book in
                            NavigationLink { WatchBookView(book: book, connection: connection) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.name).font(.headline)
                                    Text(book.monthSpent, format: .currency(code: book.currency)).monospacedDigit()
                                    Text("Spese del mese").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Text("Aggiornato \(connection.overview.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text(connection.overview.hidden ? "Attiva il riepilogo Apple Watch nelle impostazioni di Forgia su iPhone." : "Riepilogo da aggiornare. Apri Forgia su iPhone.")
                            .font(.caption)
                    }
                    Button("Aggiorna", systemImage: "arrow.clockwise") { connection.refresh() }
                        .disabled(connection.isSending)
                    if let message = connection.message { Text(message).font(.caption) }
                }
                .navigationTitle("Forgia")
            }
            .id(connection.overview.usable(at: context.date))
        }
    }
}

struct WatchBookView: View {
    let book: WatchBook
    let connection: WatchConnection
    var body: some View {
        List {
            Section("Spese del mese") { Text(book.monthSpent, format: .currency(code: book.currency)).font(.title3).monospacedDigit() }
            if let remaining = book.budgetRemaining {
                Section(book.budgetName ?? "Budget") {
                    Text(remaining, format: .currency(code: book.currency)).foregroundStyle(remaining < 0 ? .red : .primary)
                    Text("Residuo registrato").font(.caption)
                }
            }
            Text("Scadenze nei prossimi 7 giorni: \(book.upcomingCount)")
            if !(book.conti ?? []).isEmpty, !(book.categories ?? []).isEmpty {
                NavigationLink("Registra spesa") { WatchDirectExpenseView(connection: connection, bookID: book.id) }
            }
            NavigationLink("Prepara su iPhone") { WatchExpenseView(connection: connection, book: book) }
        }
        .navigationTitle(book.name)
    }
}

struct WatchExpenseView: View {
    let connection: WatchConnection
    let book: WatchBook?
    var restoredDraft: WatchExpenseDraft? = nil
    @State private var amount = ""
    @State private var note = ""
    private var targetBookID: UUID? { restoredDraft != nil ? restoredDraft?.bookID : book?.id }
    var body: some View {
        Form {
            Text(book.map { "\($0.name) · \($0.currency)" }
                 ?? (targetBookID == nil ? "Valuta del libro selezionato su iPhone" : "Libro originale della bozza su iPhone"))
                .font(.caption)
            TextField("Importo", text: $amount)
            TextField("Descrizione", text: $note)
            Button("Invia bozza a iPhone") { connection.prepare(amount: amount, note: note, bookID: targetBookID) }
                .disabled(connection.isSending)
            if connection.isSending { ProgressView() }
            if let message = connection.message { Text(message).font(.caption) }
            Text("La spesa viene registrata solo dopo la conferma in Forgia su iPhone.").font(.caption2).foregroundStyle(.secondary)
        }
        .navigationTitle("Nuova spesa")
        .task {
            if let draft = restoredDraft ?? connection.pendingDraft, draft.bookID == targetBookID {
                amount = draft.amount; note = draft.note
            }
        }
    }
}

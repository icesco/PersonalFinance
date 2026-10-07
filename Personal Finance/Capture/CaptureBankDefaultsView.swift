import SwiftUI
import SwiftData
import FinanceCore

enum CaptureBankDefaultsStorage {
    static let key = "capture.bankRoutingDefaults"
    static func decode(_ data: Data) -> [CaptureBankDefault] {
        (try? JSONDecoder().decode([CaptureBankDefault].self, from: data)) ?? []
    }
}

struct CaptureBankDefaultsView: View {
    @AppStorage(CaptureBankDefaultsStorage.key) private var stored = Data()
    @Query(sort: \Conto.name) private var conti: [Conto]
    @State private var editing: CaptureBankDefault?
    @State private var showingEditor = false
    @State private var error: String?
    private var defaults: [CaptureBankDefault] { CaptureBankDefaultsStorage.decode(stored).sorted { $0.bank.localizedStandardCompare($1.bank) == .orderedAscending } }
    var body: some View {
        List {
            Section {
                Text("Questi default vengono conservati su questo dispositivo.")
                    .font(.footnote).foregroundStyle(ForgiaPalette.mutedText)
                Text("Indica lo stesso nome usato nel campo “Banca o app di origine” del comando rapido. Il conto viene proposto solo per le notifiche bancarie; puoi cambiarlo durante la revisione.")
                    .font(.footnote).foregroundStyle(ForgiaPalette.mutedText)
                Text("Se l’automazione indica già un conto di destinazione, quello ha la precedenza. Con un unico libro e conto attivi, Formi li propone anche senza configurare un default.")
                    .font(.footnote).foregroundStyle(ForgiaPalette.mutedText)
            }
            Section("Conti predefiniti per banca") {
                ForEach(defaults) { item in
                    Button { editing = item; showingEditor = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.bank).font(.headline).foregroundStyle(Color.primary)
                                if let conto = conti.first(where: { $0.id == item.contoID && $0.account?.id == item.bookID && $0.isActive == true && $0.account?.isActive == true }) {
                                    Text("\(conto.account?.name ?? "Libro") · \(conto.name ?? "Conto")").font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                                } else {
                                    Text("Destinazione non disponibile · Aggiorna il default").font(.caption).foregroundStyle(ForgiaPalette.spending)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                        }
                    }.buttonStyle(.plain)
                    .swipeActions { Button("Rimuovi", role: .destructive) { save(defaults.filter { $0.id != item.id }) } }
                }
                Button { editing = nil; showingEditor = true } label: { Label("Aggiungi banca", systemImage: "plus") }
                    .accessibilityIdentifier("capture-bank-default-add")
            }
        }
        .scrollContentBackground(.hidden).listRowBackground(ForgiaPalette.surface).themedBackground()
        .navigationTitle("Conti predefiniti").toolbarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingEditor) {
            CaptureBankDefaultEditor(existing: editing, defaults: defaults) { value in
                save(defaults.filter { $0.id != editing?.id } + [value])
            }
        }
        .alert("Impossibile salvare", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func save(_ values: [CaptureBankDefault]) {
        do { stored = try JSONEncoder().encode(values) } catch { self.error = error.localizedDescription }
    }
}

private struct CaptureBankDefaultEditor: View {
    let existing: CaptureBankDefault?
    let defaults: [CaptureBankDefault]
    let onSave: (CaptureBankDefault) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Conto.name) private var conti: [Conto]
    @State private var bank = ""
    @State private var bookID: UUID?
    @State private var contoID: UUID?
    private var active: [Conto] { conti.filter { $0.isActive == true && $0.account?.isActive == true } }
    private var books: [Account] {
        var seen = Set<UUID>()
        return active.compactMap(\.account).filter { seen.insert($0.id).inserted }.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
    private var scoped: [Conto] { active.filter { $0.account?.id == bookID } }
    private var duplicate: Bool { defaults.contains { $0.id == CaptureClassifier.bankKey(bank) && $0.id != existing?.id } }
    private var valid: Bool { !CaptureClassifier.bankKey(bank).isEmpty && bank.count <= 160 && !duplicate && bookID != nil && scoped.contains { $0.id == contoID } }
    var body: some View {
        Form {
            Section("Banca o app di origine") {
                TextField("Ad esempio Revolut", text: $bank).accessibilityIdentifier("capture-default-bank")
                Text("Usa il nome configurato nell’azione “Acquisisci notifica bancaria” di Comandi Rapidi.").font(.footnote).foregroundStyle(ForgiaPalette.mutedText)
                if duplicate { Text("Questa banca ha già un conto predefinito.").foregroundStyle(.red) }
            }
            Section("Destinazione proposta") {
                Picker("Libro", selection: $bookID) {
                    Text("Scegli un libro").tag(nil as UUID?)
                    ForEach(books) { Text($0.name ?? "Libro").tag(Optional($0.id)) }
                }.accessibilityIdentifier("capture-default-book")
                Picker("Conto", selection: $contoID) {
                    Text("Scegli un conto").tag(nil as UUID?)
                    ForEach(scoped) { Text($0.name ?? "Conto").tag(Optional($0.id)) }
                }.disabled(bookID == nil).accessibilityIdentifier("capture-default-account")
            }
            Section {
                Button("Salva default") {
                    guard valid, let bookID, let contoID else { return }
                    onSave(CaptureBankDefault(bank: bank.trimmingCharacters(in: .whitespacesAndNewlines), bookID: bookID, contoID: contoID))
                    dismiss()
                }.disabled(!valid).accessibilityIdentifier("capture-default-save")
            }
        }
        .scrollContentBackground(.hidden).listRowBackground(ForgiaPalette.surface).themedBackground()
        .navigationTitle(existing == nil ? "Aggiungi banca" : "Modifica banca").toolbarTitleDisplayMode(.inline)
        .onAppear {
            bank = existing?.bank ?? ""
            bookID = existing?.bookID ?? (books.count == 1 ? books[0].id : nil)
            contoID = existing?.contoID ?? (scoped.count == 1 ? scoped[0].id : nil)
        }
        .onChange(of: bookID) { _, _ in if !scoped.contains(where: { $0.id == contoID }) { contoID = scoped.count == 1 ? scoped[0].id : nil } }
    }
}

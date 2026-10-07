import SwiftUI
import SwiftData
import FinanceCore

struct AccountSelectionModal: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStateManager.self) private var appState
    @Query(sort: \Account.name) private var accounts: [Account]
    @State private var showingAccountCreation = false
    #if os(iOS)
    @State private var selectedDetent: PresentationDetent = .large
    #endif

    private var activeAccounts: [Account] { accounts.filter { $0.isActive == true } }
    private var isInitialSelection: Bool { appState.selectedAccount == nil && !appState.showAllAccounts }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if activeAccounts.isEmpty {
                        emptyState
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("I tuoi libri")
                                .font(.system(.title, design: .serif, weight: .semibold))
                            Text("Scegli quale vuoi consultare.")
                                .font(.subheadline)
                                .foregroundStyle(ForgiaPalette.mutedText)
                        }

                        if activeAccounts.count > 1 {
                            AllAccountsSelectionCard(accounts: activeAccounts) {
                                appState.selectAllAccounts()
                                dismiss()
                            }
                        }

                        VStack(spacing: 12) {
                            ForEach(activeAccounts) { account in
                                AccountSelectionCard(account: account) {
                                    appState.selectAccount(account)
                                    dismiss()
                                }
                            }
                        }
                    }

                    NavigationLink {
                        BooksSettingsView()
                    } label: {
                        HStack(spacing: 10) {
                            Label("Gestisci libri", systemImage: "books.vertical")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                        .font(.subheadline)
                        .foregroundStyle(ForgiaPalette.mutedText)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .themedBackground()
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                if !isInitialSelection {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Chiudi", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Nuovo libro", systemImage: "plus") { showingAccountCreation = true }
                        .labelStyle(.iconOnly)
                }
            }
        }
        .tint(ForgiaPalette.accent)
        .interactiveDismissDisabled(isInitialSelection)
        #if os(iOS)
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .presentationBackground(ForgiaPalette.canvas)
        #endif
        .sheet(isPresented: $showingAccountCreation) {
            CreateAccountView { newAccount in
                appState.selectAccount(newAccount)
                dismiss()
            }
            .environment(appState)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "book.closed")
                .font(.largeTitle)
                .foregroundStyle(ForgiaPalette.accent)
            Text("Il tuo prossimo libro")
                .font(.system(.title2, design: .serif, weight: .semibold))
            Text("Crea un libro per raccogliere conti e movimenti in un unico spazio.")
                .foregroundStyle(ForgiaPalette.mutedText)
            Button("Crea un libro", systemImage: "plus") { showingAccountCreation = true }
                .buttonStyle(.borderedProminent)
        }
        .unifiedCard()
    }
}

struct AccountSelectionCard: View {
    let account: Account
    let onSelect: () -> Void
    @Environment(AppStateManager.self) private var appState

    private var isSelected: Bool {
        !appState.showAllAccounts && account.id == appState.selectedAccount?.id
    }

    private var contiLabel: String {
        account.activeConti.count == 1 ? "1 conto" : "\(account.activeConti.count) conti"
    }

    var body: some View {
        BookSelectionRow(
            title: account.name ?? "Libro",
            subtitle: "\(contiLabel) · \(account.currency ?? "EUR")",
            icon: "book.closed",
            balances: [BookSelectionBalance(currency: account.currency ?? "EUR", amount: account.totalBalance)],
            isSelected: isSelected,
            action: onSelect
        )
    }
}

struct AllAccountsSelectionCard: View {
    let accounts: [Account]
    let onSelect: () -> Void
    @Environment(AppStateManager.self) private var appState

    private var balances: [BookSelectionBalance] {
        Dictionary(grouping: accounts, by: { $0.currency ?? "EUR" })
            .map { BookSelectionBalance(currency: $0.key, amount: $0.value.reduce(.zero) { $0 + $1.totalBalance }) }
            .sorted { $0.currency < $1.currency }
    }

    var body: some View {
        BookSelectionRow(
            title: "Tutti i libri",
            subtitle: "\(accounts.count) libri · \(accounts.reduce(0) { $0 + $1.activeConti.count }) conti",
            icon: "books.vertical",
            balances: balances,
            isSelected: appState.showAllAccounts,
            action: onSelect
        )
    }
}

private struct BookSelectionBalance: Identifiable {
    let currency: String
    let amount: Decimal
    var id: String { currency }
}

private struct BookSelectionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let balances: [BookSelectionBalance]
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(ForgiaPalette.accent)
                    .frame(width: 44, height: 44)
                    .background(ForgiaPalette.sageSurface, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                    ForEach(balances) { balance in
                        Text(balance.amount, format: .currency(code: balance.currency))
                            .font(.system(.headline, design: .serif, weight: .semibold))
                            .foregroundStyle(balance.amount < 0 ? ForgiaPalette.deficit : ForgiaPalette.balance)
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? ForgiaPalette.accent : ForgiaPalette.border)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(isSelected ? ForgiaPalette.accent.opacity(0.65) : ForgiaPalette.border,
                                  lineWidth: isSelected ? 1.5 : 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if DEBUG
/// Presents the actual picker with an isolated store and synthetic, mixed-currency books.
struct CurrencySelectionFixture: View {
    @State private var appState: AppStateManager
    @State private var showingSelection = true
    @State private var container: ModelContainer

    init() {
        let container = try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let state = AppStateManager(persistsSelection: false)
        for (name, currency, amount) in [
            ("Personale", "EUR", Decimal(2450)),
            ("Famiglia", "EUR", Decimal(1820)),
            ("Viaggi", "USD", Decimal(350))
        ] {
            let book = Account(name: name, currency: currency)
            let conto = Conto(name: "Conto demo", type: .checking, initialBalance: amount)
            conto.account = book
            book.conti = [conto]
            container.mainContext.insert(book)
            if name == "Personale" { state.selectAccount(book) }
        }
        try! container.mainContext.save()
        _container = State(initialValue: container)
        _appState = State(initialValue: state)
    }

    var body: some View {
        Group {
            if ProcessInfo.processInfo.arguments.contains("UITEST_BOOK_ZOOM") {
                MainTabView()
            } else {
                VStack(spacing: 20) {
                    Text(appState.showAllAccounts ? "Tutti i libri" : appState.selectedAccount?.name ?? "Scegli libro")
                    Button("Cambia libro") { showingSelection = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .themedBackground()
                .sheet(isPresented: $showingSelection) { AccountSelectionModal() }
            }
        }
        .environment(appState)
        .modelContainer(container)

    }
}

#Preview { CurrencySelectionFixture() }
#endif

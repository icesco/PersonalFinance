import SwiftUI
import SwiftData
import FinanceCore

/// The daily entry point: one estimate, its inputs, and the changes worth checking.
struct TodayView: View {
    enum Screen { case home, analysis }

    @Environment(AppStateManager.self) private var appState
    @Query private var accounts: [Account]
    @Query private var resolutions: [RecurrenceResolution]
    @Query private var transactions: [FinanceTransaction]

    var screen: Screen = .home

    @State private var showingImport = false
    @State private var showingBudgets = false
    @State private var showingBalances = false

    private var snapshot: TodaySnapshot {
        let selectedAccounts: [Account]
        if appState.showAllAccounts {
            selectedAccounts = accounts.filter { $0.isActive == true }
        } else {
            selectedAccounts = appState.selectedAccount.map { [$0] } ?? []
        }
        let conti = selectedAccounts.flatMap(\.activeConti)
        let contoIDs = Set(conti.map(\.id))
        let currency = selectedAccounts.first?.currency ?? "EUR"
        let now = Date()
        let horizon = Calendar.current.date(byAdding: .day, value: 45, to: now) ?? now

        let relevant = transactions.filter { transaction in
            (transaction.fromContoId.map { contoIDs.contains($0) } ?? false) ||
            (transaction.toContoId.map { contoIDs.contains($0) } ?? false)
        }
        let entries = relevant.map { transaction in
            DirectionTransaction(
                date: transaction.date,
                amount: transaction.amount ?? 0,
                type: transaction.type,
                categoryID: transaction.categoryId,
                categoryName: transaction.category?.name ?? "Da classificare",
                isRecurring: transaction.isRecurring == true || transaction.recurrenceSourceID != nil
            )
        }
        let resolvedKeys = Set(resolutions.map(\.key))
        let planned = relevant.flatMap { transaction -> [PlannedCashMovement] in
            guard transaction.isRecurring == true,
                  transaction.type != .transfer else { return [] }
            if transaction.type == .expense,
               !(transaction.fromContoId.map { contoIDs.contains($0) } ?? false) { return [] }
            if transaction.type == .income,
               !(transaction.toContoId.map { contoIDs.contains($0) } ?? false) { return [] }
            return transaction.recurrenceDates(after: now, through: horizon)
                .filter { !resolvedKeys.contains(RecurrenceResolution.key(sourceID: transaction.id, date: $0)) }
                .map { date in
                PlannedCashMovement(
                    date: date,
                    amount: transaction.amount ?? 0,
                    type: transaction.type,
                    title: transaction.transactionDescription ?? transaction.category?.name ?? "Movimento previsto"
                )
            }
        }

        let liquid = conti
            .filter { [.checking, .savings, .cash].contains($0.type) }
            .reduce(Decimal(0)) { $0 + $1.balance }
        let cardDebt = conti
            .filter { $0.type == .credit }
            .reduce(Decimal(0)) { $0 + max(0, -$1.balance) }
        let direction = SpendingDirectionCalculator.calculate(
            transactions: entries,
            planned: planned,
            liquidBalance: liquid,
            creditDebt: cardDebt,
            balancesVerified: conti.filter { [.checking, .savings, .cash, .credit].contains($0.type) }
                .allSatisfy { $0.initialBalance != nil },
            now: now
        )
        return TodaySnapshot(
            entries: entries,
            contoIDs: contoIDs,
            accountName: appState.showAllAccounts ? "Tutti i libri" : selectedAccounts.first?.name ?? "Il tuo libro",
            currency: currency,
            hasMixedCurrencies: Set(selectedAccounts.compactMap(\.currency)).count > 1,
            direction: direction,
            planned: planned.filter { $0.type == .expense && $0.date > now }.sorted { $0.date < $1.date }
        )
    }

    var body: some View {
        let snapshot = snapshot
        NavigationStack {
            Group {
                if screen == .analysis {
                    if snapshot.hasMixedCurrencies {
                        ContentUnavailableView {
                            Label("Seleziona un solo libro", systemImage: "chart.pie")
                        } description: {
                            Text("L'analisi richiede movimenti nella stessa valuta.")
                        } actions: {
                            Button("Scegli libro") { appState.presentAccountSelection() }
                                .buttonStyle(.borderedProminent)
                            NavigationLink("Saldo storico per libro") { BalanceHistoryView() }
                        }
                        .themedBackground()
                    } else {
                        SpendingOverviewView(transactions: snapshot.entries, currency: snapshot.currency, scopeContoIDs: snapshot.contoIDs,
                                             initialBookID: appState.showAllAccounts ? nil : appState.selectedAccount?.id)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            header(snapshot: snapshot)
                            TodayMarginCard(
                                snapshot: snapshot,
                                onVerify: { showingBalances = true },
                                onImport: { showingImport = true },
                                onAddIncome: { appState.presentQuickTransaction(type: .income, planned: true) }
                            )
                            quickActions
                            if !snapshot.hasMixedCurrencies {
                                SpendingCommitmentSummary(direction: snapshot.direction, currency: snapshot.currency, scopeContoIDs: snapshot.contoIDs)
                                TodayRecentActivityCard(snapshot: snapshot)
                                if !snapshot.planned.isEmpty {
                                    TodayCommitmentsCard(snapshot: snapshot)
                                }
                                if !snapshot.direction.shifts.isEmpty {
                                    TodayShiftsCard(shifts: snapshot.direction.shifts, currency: snapshot.currency)
                                }
                            }
                            Button { showingBudgets = true } label: {
                                HStack {
                                    Label("I tuoi budget", systemImage: "scope")
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ForgiaPalette.accent)
                                .padding(.vertical, 6)
                            }
                            .accessibilityIdentifier("today-budgets")
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 14)
                        .padding(.bottom, 32)
                    }
                    .themedBackground()
                    #if os(iOS)
                    .toolbar(.hidden, for: .navigationBar)
                    #endif
                }
            }
            .sheet(isPresented: $showingImport) { CSVImportView() }
            .sheet(isPresented: $showingBudgets) { BudgetView() }
            .sheet(isPresented: $showingBalances) {
                if let account = appState.selectedAccount {
                    BalanceReconciliationView(account: account)
                }
            }
        }
    }

    private func header(snapshot: TodaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 12) {
                Text("Forgia")
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .tracking(-1)
                Spacer()
                Button { appState.presentAccountSelection() } label: {
                    HStack(spacing: 6) {
                        Text(snapshot.accountName).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .glassEffect(.regular.interactive(), in: Capsule())
                }
                .accessibilityLabel("Scegli libro: \(snapshot.accountName)")
            }
            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.caption.weight(.medium))
                .textCase(.uppercase)
                .tracking(0.7)
                .foregroundStyle(ForgiaPalette.mutedText)
        }
        .foregroundStyle(.primary)
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            quickAction("Spesa", symbol: "arrow.up.right", fill: ForgiaPalette.apricotSurface) {
                appState.presentQuickTransaction(type: .expense)
            }
            quickAction("Entrata", symbol: "arrow.down.left", fill: ForgiaPalette.sageSurface) {
                appState.presentQuickTransaction(type: .income)
            }
            quickAction("Importa", symbol: "square.and.arrow.down", fill: ForgiaPalette.surface) {
                showingImport = true
            }
        }
    }

    private func quickAction(_ title: String, symbol: String, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ForgiaPalette.accent)
                    .frame(width: 40, height: 40)
                    .background(fill, in: Circle())
                Text(title).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(ForgiaPalette.border, lineWidth: 0.7) }
        }
        .buttonStyle(.plain)
    }
}

private struct TodaySnapshot {
    let entries: [DirectionTransaction]
    let contoIDs: Set<UUID>
    let accountName: String
    let currency: String
    let hasMixedCurrencies: Bool
    let direction: SpendingDirection
    let planned: [PlannedCashMovement]
}

private struct TodayMarginCard: View {
    let snapshot: TodaySnapshot
    let onVerify: () -> Void
    let onImport: () -> Void
    let onAddIncome: () -> Void
    @State private var showsCalculation = false
    @State private var showsPurchaseCheck = false
    @ScaledMetric(relativeTo: .largeTitle) private var marginFontSize: CGFloat = 43

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 7) {
                Text("QUANTO PUOI ANCORA SPENDERE")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.1)
                Image(systemName: "info.circle").font(.caption)
                Spacer()
            }
            .foregroundStyle(ForgiaPalette.mutedText)

            if snapshot.hasMixedCurrencies {
                Label("Seleziona un solo libro o una sola valuta per stimare il margine.", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
            } else if let margin = snapshot.direction.estimatedMargin {
                Text(margin, format: .currency(code: snapshot.currency))
                    .font(.system(size: marginFontSize, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .tracking(-1)
                    .monospacedDigit()
                    .foregroundStyle(margin >= 0 ? Color.primary : Color.red)
                if let nextIncome = snapshot.direction.nextIncome {
                    Text("Fino alla prossima entrata · \(nextIncome.date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "it_IT"))))")
                        .font(.subheadline)
                        .foregroundStyle(ForgiaPalette.mutedText)
                }
                Text(margin >= 0
                     ? "Margine extra stimato, dopo impegni e spese abituali."
                     : "Le uscite previste superano la disponibilità: rivedi le spese prima della prossima entrata.")
                    .font(.subheadline)
                    .foregroundStyle(margin >= 0 ? ForgiaPalette.mutedText : .red)
                Button("Posso fare una spesa?") { showsPurchaseCheck = true }
                    .buttonStyle(.glassProminent)
                    .tint(ForgiaPalette.accent)
                DisclosureGroup("Come è calcolato", isExpanded: $showsCalculation) {
                    VStack(spacing: 9) {
                        TodayAmountRow(label: "Disponibilità registrata", amount: snapshot.direction.liquidBalance, currency: snapshot.currency)
                        TodayAmountRow(label: "Debito sulle carte", amount: -snapshot.direction.creditDebt, currency: snapshot.currency)
                        TodayAmountRow(label: "Uscite previste", amount: -snapshot.direction.committedOutgoings, currency: snapshot.currency)
                        TodayAmountRow(label: "Spesa abituale stimata", amount: -snapshot.direction.typicalVariableOutgoings, currency: snapshot.currency)
                        Text("Conferma i saldi dei conti prima di decidere una spesa.")
                            .font(.caption)
                            .foregroundStyle(ForgiaPalette.mutedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline.weight(.medium))
                .tint(ForgiaPalette.accent)
            } else {
                Text("Stima da completare")
                    .font(.system(.title, design: .serif, weight: .semibold))
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(ForgiaPalette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                if snapshot.direction.availability == .unverifiedBalances {
                    primaryAction("Verifica i saldi", action: onVerify)
                } else if snapshot.direction.availability == .staleData || snapshot.direction.availability == .noMovements {
                    primaryAction("Aggiorna i movimenti", action: onImport)
                } else if snapshot.direction.availability == .noPlannedIncome {
                    primaryAction("Registra la prossima entrata", action: onAddIncome)
                }
                if let latest = snapshot.direction.latestMovement {
                    Text("Ultimo movimento: \(latest.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "it_IT"))))")
                        .font(.caption)
                        .foregroundStyle(ForgiaPalette.mutedText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(ForgiaPalette.border, lineWidth: 0.7) }
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $showsPurchaseCheck) {
            PurchaseCheckView(margin: snapshot.direction.estimatedMargin, currency: snapshot.currency)
        }
    }

    private var statusMessage: String {
        switch snapshot.direction.availability {
        case .noMovements: "Aggiungi o importa i movimenti per iniziare."
        case .staleData: "Aggiorna i movimenti: i dati sono troppo vecchi per stimare quanto resta."
        case .shortHistory: "Servono almeno 45 giorni di movimenti per stimare la spesa abituale."
        case .sparseSpending: "Servono più spese recenti, distribuite su almeno due mesi, per stimare un margine attendibile."
        case .unverifiedBalances: "Verifica il saldo attuale di ogni conto e carta prima di usare la stima."
        case .noPlannedIncome: "Registra un'entrata ricorrente prevista entro 45 giorni per calcolare il margine fino a quella data."
        case .ready: ""
        }
    }

    private func primaryAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ForgiaPalette.onAccent)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(ForgiaPalette.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct TodayRecentActivityCard: View {
    let snapshot: TodaySnapshot
    @Environment(AppStateManager.self) private var appState

    var body: some View {
        Button { appState.selectTab(.analysis) } label: {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("NEGLI ULTIMI 30 GIORNI")
                        .font(.caption2.weight(.semibold))
                        .tracking(1)
                        .foregroundStyle(ForgiaPalette.mutedText)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ForgiaPalette.accent)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(snapshot.direction.recentExpenses, format: .currency(code: snapshot.currency))
                        .font(.system(size: 31, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("di uscite")
                        .font(.subheadline)
                        .foregroundStyle(ForgiaPalette.mutedText)
                }
                if let category = snapshot.direction.largestOutflows.first {
                    Divider().overlay(ForgiaPalette.border)
                    HStack(spacing: 10) {
                        Image(systemName: "chart.pie.fill")
                            .font(.caption)
                            .foregroundStyle(ForgiaPalette.accent)
                            .frame(width: 30, height: 30)
                            .background(ForgiaPalette.sageSurface, in: Circle())
                        Text("Soprattutto \(category.name.lowercased())")
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(category.amount, format: .currency(code: snapshot.currency))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                } else {
                    Text("Importa o registra movimenti per scoprire dove spendi.")
                        .font(.subheadline)
                        .foregroundStyle(ForgiaPalette.mutedText)
                }
                if snapshot.direction.availability == .staleData,
                   let latest = snapshot.direction.latestMovement {
                    Label("Dati al \(latest.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "it_IT"))))", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(ForgiaPalette.mutedText)
                }
            }
            .foregroundStyle(.primary)
            .unifiedCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dove spendi, ultimi 30 giorni")
    }
}

private struct TodayAmountRow: View {
    let label: String
    let amount: Decimal
    let currency: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(ForgiaPalette.mutedText)
            Spacer()
            Text(amount, format: .currency(code: currency)).monospacedDigit()
        }
        .font(.subheadline)
    }
}

private struct TodayCommitmentsCard: View {
    let snapshot: TodaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Impegni in arrivo").font(.headline)
            if snapshot.planned.isEmpty {
                Text("Nessuna uscita ricorrente registrata. Aggiungi le scadenze importanti per completare la stima.")
                    .foregroundStyle(ForgiaPalette.mutedText)
            } else {
                ForEach(Array(snapshot.planned.prefix(3).enumerated()), id: \.offset) { _, item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.title).lineLimit(1)
                            Text(item.date, format: .dateTime.day().month(.abbreviated))
                                .font(.caption)
                                .foregroundStyle(ForgiaPalette.mutedText)
                        }
                        Spacer()
                        Text(item.amount, format: .currency(code: snapshot.currency))
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .unifiedCard()
    }
}

private struct TodayShiftsCard: View {
    let shifts: [SpendingShift]
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Da controllare").font(.headline)
            if shifts.isEmpty {
                Text("Nessuno scostamento affidabile da segnalare con i dati disponibili.")
                    .foregroundStyle(ForgiaPalette.mutedText)
            } else {
                ForEach(Array(shifts.enumerated()), id: \.offset) { _, shift in
                    NavigationLink {
                        TransactionListView(initialCategoryID: shift.categoryID)
                            #if os(iOS)
                            .toolbar(.visible, for: .navigationBar)
                            #endif
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(shift.categoryName).font(.subheadline.weight(.semibold))
                            Text("Hai speso \(shift.spent.formatted(.currency(code: currency))): \(shift.excess.formatted(.currency(code: currency))) oltre il ritmo dei tre mesi precedenti.")
                                .font(.caption)
                                .foregroundStyle(ForgiaPalette.mutedText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if shift.categoryName != shifts.last?.categoryName { Divider() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .unifiedCard()
    }
}

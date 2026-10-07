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

        let inputs = SpendingDirectionInputs.build(conti: conti, transactions: transactions,
                                                   resolutions: resolutions, now: now, horizon: horizon)
        let direction = SpendingDirectionCalculator.calculate(
            transactions: inputs.transactions,
            planned: inputs.planned,
            liquidBalance: inputs.liquidBalance,
            creditDebt: inputs.creditDebt,
            balancesVerified: inputs.balancesVerified,
            now: now
        )
        return TodaySnapshot(
            entries: inputs.transactions,
            contoIDs: contoIDs,
            accountName: appState.showAllAccounts ? "Tutti i libri" : selectedAccounts.first?.name ?? "Il tuo libro",
            currency: currency,
            hasMixedCurrencies: Set(selectedAccounts.compactMap(\.currency)).count > 1,
            direction: direction,
            planned: inputs.planned.filter { $0.type == .expense && $0.date > now }.sorted { $0.date < $1.date }
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
                                FinanceCalendarPreview(contoIDs: snapshot.contoIDs, currency: snapshot.currency)
                                SpendingCommitmentSummary(direction: snapshot.direction, currency: snapshot.currency, scopeContoIDs: snapshot.contoIDs)
                                TodayActivityLayout(snapshot: snapshot)
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
                        #if os(macOS)
                        .frame(maxWidth: 1040)
                        .frame(maxWidth: .infinity)
                        #endif
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
            .modifier(TransactionAddButtonModifier(isVisible: screen == .analysis))
            .financePresentation(isPresented: $showingImport, title: "Importa CSV", width: 800) { CSVImportView() }
            .financePresentation(isPresented: $showingBudgets, title: "Budget", width: 800) { BudgetView() }
            .financePresentation(isPresented: $showingBalances, title: "Verifica saldi") {
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

    var body: some View {
        NavigationLink {
            AnalysisDetailScreen(title: "Il tuo margine", periodTitle: snapshot.accountName) {
                TodayMarginDetailContent(snapshot: snapshot, onVerify: onVerify, onImport: onImport, onAddIncome: onAddIncome)
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                AnalysisPreviewHeading(title: "Quanto puoi ancora spendere", icon: "circle.dotted", tint: ForgiaPalette.margin)
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        if snapshot.hasMixedCurrencies {
                            Text("Seleziona un solo libro").font(.title3.weight(.semibold))
                            Text("Il margine richiede una sola valuta").font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                        } else if let margin = snapshot.direction.estimatedMargin {
                            Text(margin, format: .currency(code: snapshot.currency))
                                .font(.system(.title, design: .rounded, weight: .semibold))
                                .foregroundStyle(margin >= 0 ? ForgiaPalette.margin : ForgiaPalette.deficit).monospacedDigit().financeNumericMotion(margin)
                            Text("Margine stimato").font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                            if let nextIncome = snapshot.direction.nextIncome {
                                Text("Fino al \(nextIncome.date, format: .dateTime.day().month(.abbreviated))")
                                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                            }
                        } else {
                            Text("Stima da completare").font(.title3.weight(.semibold))
                            Text("Apri per vedere cosa manca").font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    let available = snapshot.direction.liquidBalance - snapshot.direction.creditDebt
                    if !snapshot.hasMixedCurrencies, let margin = snapshot.direction.estimatedMargin,
                       available > 0, margin >= 0, margin <= available {
                        FinancialSharePreview(share: NSDecimalNumber(decimal: margin / available).doubleValue, icon: "wallet.bifold")
                            .accessibilityHidden(true)
                    }
                }
            }.unifiedCard(tint: ForgiaPalette.margin).foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .financeCardEntrance()
        .accessibilityIdentifier("today-margin-preview")
    }
}

private struct TodayMarginDetailContent: View {
    let snapshot: TodaySnapshot
    let onVerify: () -> Void
    let onImport: () -> Void
    let onAddIncome: () -> Void
    @State private var showsCalculation = false
    @State private var showsMarginInfo = false
    @State private var showsPurchaseCheck = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Button { showsMarginInfo = true } label: {
                HStack(spacing: 7) {
                    Text("QUANTO PUOI ANCORA SPENDERE")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.1)
                    Image(systemName: "info.circle").font(.caption)
                    Spacer()
                }
                .foregroundStyle(ForgiaPalette.mutedText)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Come è calcolato quanto puoi ancora spendere")
            .accessibilityIdentifier("today-margin-info")

            if snapshot.hasMixedCurrencies {
                Label("Seleziona un solo libro o una sola valuta per stimare il margine.", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
            } else if let margin = snapshot.direction.estimatedMargin {
                TodayMarginHero(margin: margin, available: snapshot.direction.liquidBalance - snapshot.direction.creditDebt,
                                currency: snapshot.currency)
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
                        TodayAmountRow(label: "Saldo maturato", amount: snapshot.direction.liquidBalance, currency: snapshot.currency)
                        TodayAmountRow(label: "Debito sulle carte", amount: -snapshot.direction.creditDebt, currency: snapshot.currency)
                        TodayAmountRow(label: "Uscite previste", amount: -snapshot.direction.committedOutgoings, currency: snapshot.currency)
                        TodayAmountRow(label: "Spesa abituale stimata", amount: -snapshot.direction.typicalVariableOutgoings, currency: snapshot.currency)
                        Text("Il saldo esclude i movimenti futuri. Le uscite previste includono le spese programmate e le ricorrenze fino alla prossima entrata. Conferma i saldi dei conti prima di decidere una spesa.")
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
        .sheet(isPresented: $showsMarginInfo) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Un margine, non una promessa")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                        Text("Partiamo dal saldo maturato, sottraiamo il debito sulle carte, le uscite previste e le spese abituali stimate fino alla prossima entrata.")
                        if !snapshot.hasMixedCurrencies {
                            TodayAmountRow(label: "Saldo maturato", amount: snapshot.direction.liquidBalance, currency: snapshot.currency)
                            TodayAmountRow(label: "Debito sulle carte", amount: -snapshot.direction.creditDebt, currency: snapshot.currency)
                            TodayAmountRow(label: "Uscite previste", amount: -snapshot.direction.committedOutgoings, currency: snapshot.currency)
                            TodayAmountRow(label: "Spesa abituale stimata", amount: -snapshot.direction.typicalVariableOutgoings, currency: snapshot.currency)
                        }
                        Text(snapshot.hasMixedCurrencies ? "Seleziona un libro con una sola valuta per ottenere una stima." : snapshot.direction.estimatedMargin == nil ? statusMessage : "La stima dipende dai movimenti registrati e dai saldi verificati. Le entrate future non sono denaro già disponibile.")
                            .font(.callout).foregroundStyle(.secondary)
                    }.padding(24)
                }
                .navigationTitle("Il tuo margine")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { showsMarginInfo = false } } }
            }
            .presentationDetents([.medium, .large])
        }
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
                Text("Nessuna uscita prevista nei prossimi 45 giorni. Aggiungi le scadenze importanti per completare la stima.")
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

private struct TodayActivityLayout: View {
    let snapshot: TodaySnapshot
    var body: some View {
        #if os(macOS)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), alignment: .top)], alignment: .leading, spacing: 24) {
            cards
        }
        #else
        cards
        #endif
    }
    @ViewBuilder private var cards: some View {
        TodayRecentActivityCard(snapshot: snapshot)
        if !snapshot.planned.isEmpty { TodayCommitmentsCard(snapshot: snapshot) }
        if !snapshot.direction.shifts.isEmpty {
            TodayShiftsCard(shifts: snapshot.direction.shifts, currency: snapshot.currency)
        }
    }
}

#if DEBUG
/// Exercises the real margin card without inserting or changing ledger records.
struct TodayMarginVisualFixture: View {
    private var snapshot: TodaySnapshot {
        let now = Date()
        let entries = (0..<30).map { index in
            DirectionTransaction(date: Calendar.current.date(byAdding: .day, value: -(index * 3 + 1), to: now)!,
                amount: 45, type: .expense, categoryID: nil, categoryName: "Spese quotidiane", isRecurring: false)
        }
        let planned = [
            PlannedCashMovement(date: Calendar.current.date(byAdding: .day, value: 14, to: now)!, amount: 2200, type: .income, title: "Stipendio"),
            PlannedCashMovement(date: Calendar.current.date(byAdding: .day, value: 5, to: now)!, amount: 480, type: .expense, title: "Affitto")
        ]
        let direction = SpendingDirectionCalculator.calculate(transactions: entries, planned: planned,
            liquidBalance: 3000, creditDebt: 120, balancesVerified: true, now: now)
        return TodaySnapshot(entries: entries, contoIDs: [], accountName: "Esempio", currency: "EUR",
            hasMixedCurrencies: false, direction: direction, planned: planned.filter { $0.type == .expense })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Anteprima · dati illustrativi").font(.caption).foregroundStyle(.secondary)
                    TodayMarginCard(snapshot: snapshot, onVerify: {}, onImport: {}, onAddIncome: {})
                }.padding(22)
            }
            .themedBackground()
            .navigationTitle("Il tuo margine")
            .toolbarTitleDisplayMode(.inline)
        }
    }
}
#endif

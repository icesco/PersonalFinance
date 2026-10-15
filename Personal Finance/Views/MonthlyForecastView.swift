import SwiftUI
import SwiftData
import FinanceCore

private var monthlyForecastLocale: Locale {
    Locale(identifier: Locale.preferredLanguages.first ?? Locale.current.identifier)
}

struct MonthlyForecastView: View {
    let conti: [Conto]
    let currency: String
    @Environment(\.scenePhase) private var scenePhase
    @Query private var memberships: [SharedBookMembership]
    @Query private var budgets: [Budget]
    @Query private var transactions: [FinanceCore.Transaction]
    @Query private var resolutions: [RecurrenceResolution]
    @State private var selectedID: UUID?
    @State private var month: Date

    init(conti: [Conto], currency: String, initialDate: Date = Date()) {
        self.conti = conti
        self.currency = currency
        _selectedID = State(initialValue: conti.first(where: \.supportsMonthlyForecast)?.id)
        let calendar = Calendar.current
        let currentMonth = calendar.dateInterval(of: .month, for: Date())!.start
        let requestedMonth = calendar.dateInterval(of: .month, for: initialDate)!.start
        _month = State(initialValue: max(currentMonth, requestedMonth))
    }

    var body: some View {
        let eligible = conti.filter(\.supportsMonthlyForecast)
        let selected = eligible.first { $0.id == selectedID } ?? eligible.first
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !eligible.isEmpty {
                    MonthlyForecastAccountPicker(conti: eligible, selection: $selectedID)
                    MonthlyForecastMonthPicker(month: $month)
                }
                if let selected {
                    let report = MonthlyForecastCalculator.build(conto: selected, transactions: transactions,
                        resolutions: resolutions, month: month, budgets: budgets)
                    MonthlyForecastAccountContent(report: report, contoID: selected.id, currency: currency,
                        participants: MonthlyForecastParticipants.people(conto: selected, memberships: memberships))
                        .id(selected.id)
                } else {
                    ContentUnavailableView("Nessun conto corrente", systemImage: "wallet.bifold",
                        description: Text("La previsione del mese è disponibile solo per i conti correnti attivi."))
                }
            }.frame(maxWidth: 760).frame(maxWidth: .infinity).padding(22)
        }
        .themedBackground(tint: ForgiaPalette.calendar)
        .navigationTitle("Previsione del mese")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { clampToCurrentMonth() }
        .onChange(of: scenePhase) { if scenePhase == .active { clampToCurrentMonth() } }
        .onChange(of: eligible.map(\.id)) {
            if !eligible.contains(where: { $0.id == selectedID }) { selectedID = eligible.first?.id }
        }
    }
    private func clampToCurrentMonth() {
        let currentMonth = Calendar.current.dateInterval(of: .month, for: Date())!.start
        if month < currentMonth { month = currentMonth }
    }
}

private struct MonthlyForecastAccountPicker: View {
    let conti: [Conto]
    @Binding var selection: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conto da prevedere").font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(conti) { conto in
                        Button { selection = conto.id } label: {
                            HStack(spacing: 6) {
                                Text(conto.name ?? "Conto").font(.subheadline.weight(.semibold))
                                if conto.id == selection {
                                    Image(systemName: "checkmark").font(.caption.weight(.bold))
                                }
                            }
                            .padding(.horizontal, 14).frame(minHeight: 48)
                            .foregroundStyle(conto.id == selection ? ForgiaPalette.onAccent : ForgiaPalette.accent)
                            .background(conto.id == selection ? ForgiaPalette.accent : ForgiaPalette.accent.opacity(0.08),
                                        in: Capsule())
                            .contentShape(Capsule())
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("monthly-forecast-account-\(conto.name ?? conto.id.uuidString)")
                            .accessibilityAddTraits(conto.id == selection ? .isSelected : [])
                    }
                }
            }
        }.accessibilityIdentifier("monthly-forecast-accounts")
    }
}

private struct MonthlyForecastMonthPicker: View {
    @Binding var month: Date
    private var canGoBack: Bool {
        Calendar.current.compare(month, to: Date(), toGranularity: .month) == .orderedDescending
    }
    var body: some View {
        HStack {
            Button("Mese precedente", systemImage: "chevron.left") {
                guard canGoBack else { return }
                month = Calendar.current.date(byAdding: .month, value: -1, to: month)!
            }.labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                .frame(width: 48, height: 48).accessibilityIdentifier("monthly-forecast-previous")
                .disabled(!canGoBack)
            Spacer(minLength: 8)
            Text(month.formatted(.dateTime.month(.wide).year().locale(monthlyForecastLocale))).font(.system(.title3, design: .serif, weight: .bold))
                .multilineTextAlignment(.center).accessibilityIdentifier("monthly-forecast-month")
            Spacer(minLength: 8)
            Button("Mese successivo", systemImage: "chevron.right") {
                month = Calendar.current.date(byAdding: .month, value: 1, to: month)!
            }.labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                .frame(width: 48, height: 48).accessibilityIdentifier("monthly-forecast-next")
        }.foregroundStyle(ForgiaPalette.accent)
    }
}

private struct MonthlyForecastAccountContent: View {
    let sourceReport: MonthlyForecast
    let currency: String
    let contoID: UUID
    let participants: [TransactionPerson]
    @AppStorage private var mode: String
    @AppStorage private var percentageText: String
    @AppStorage private var fixedText: String
    @AppStorage private var includingVariables: Bool
    @AppStorage private var excludedCategoriesJSON: String
    @State private var showsDetails = false

    init(report: MonthlyForecast, contoID: UUID, currency: String, participants: [TransactionPerson]) {
        self.sourceReport = report
        self.currency = currency
        self.contoID = contoID
        self.participants = participants
        let key = "formi.forecast.safety.\(contoID.uuidString).\(currency)"
        _mode = AppStorage(wrappedValue: "percentage", "\(key).mode")
        _percentageText = AppStorage(wrappedValue: "0", "\(key).percentage")
        _fixedText = AppStorage(wrappedValue: "0", "\(key).fixed")
        _includingVariables = AppStorage(wrappedValue: false, "\(key).includeVariables")
        _excludedCategoriesJSON = AppStorage(wrappedValue: "[]", "\(key).excludedVariableCategories")
    }

    private var excludedCategories: Binding<Set<String>> {
        Binding(get: {
            Set((try? JSONDecoder().decode([String].self, from: Data(excludedCategoriesJSON.utf8))) ?? [])
        }, set: { ids in
            if let data = try? JSONEncoder().encode(ids.sorted()), let json = String(data: data, encoding: .utf8) {
                excludedCategoriesJSON = json
            }
        })
    }

    var body: some View {
        let report = sourceReport.excludingVariableCategories(excludedCategories.wrappedValue)
        let selectedMode = MonthlySafetyMargin.Mode(rawValue: mode) ?? .percentage
        let input = selectedMode == .percentage ? percentageText : fixedText
        let safety = MarginScenario.expense(from: input).flatMap {
            MonthlySafetyMargin(necessary: report.necessary(includingVariables: includingVariables), mode: selectedMode, value: $0, currency: currency)
        }
        VStack(alignment: .leading, spacing: 20) {
            if report.period == .current {
                MonthlyForecastCoverageSummary(report: report, safety: safety, currency: currency, includingVariables: includingVariables)
            }
            MonthlyForecastSummary(report: report, currency: currency, safety: safety, includingVariables: $includingVariables)
            if includingVariables {
                MonthlyForecastCategorySelection(report: sourceReport, currency: currency, excluded: excludedCategories)
            }
            if report.period == .current {
                MonthlyForecastFundingSplitView(contoID: contoID, currency: currency, participants: participants,
                    shortfall: report.fundingShortfall(safety: safety, includingVariables: includingVariables))
            }
            if report.period != .past {
                MonthlyForecastSafetyEditor(report: report, currency: currency, mode: $mode,
                    value: selectedMode == .percentage ? $percentageText : $fixedText, safety: safety, includingVariables: includingVariables)
            }
            DisclosureGroup(isExpanded: $showsDetails) {
                VStack(spacing: 20) {
                    MonthlyForecastCommitments(report: report, currency: currency)
                    MonthlyForecastCoverage(report: report, currency: currency, safety: safety, includingVariables: includingVariables)
                }.padding(.top, 16)
            } label: {
                Label("Dettagli del calcolo", systemImage: "list.bullet")
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 48)
            }.tint(ForgiaPalette.accent).accessibilityIdentifier("monthly-forecast-details")
        }
    }
}

private struct MonthlyForecastCategorySelection: View {
    let report: MonthlyForecast
    let currency: String
    @Binding var excluded: Set<String>
    @State private var isExpanded = false

    var body: some View {
        let selectedReport = report.excludingVariableCategories(excluded)
        VStack(alignment: .leading, spacing: 0) {
            Button { isExpanded.toggle() } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Categorie da includere").font(.subheadline.weight(.semibold))
                        Text("\(report.estimates.filter { !excluded.contains($0.id) }.count) di \(report.estimates.count) selezionate")
                            .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold))
                }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityIdentifier("monthly-forecast-categories")
                .accessibilityValue(isExpanded ? String(localized: "Espanso") : String(localized: "Compresso"))
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Scegli budget e spese abituali da aggiungere. Il residuo del budget sostituisce lo storico delle sue categorie. Le scadenze programmate restano sempre nel totale.")
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                    if let limitation = selectedReport.estimateLimitation {
                        Text(limitation).font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                    }
                    if report.hasBudgetBasis, let limitation = report.historyLimitation {
                        Text("Usiamo i budget del conto. La parte storica è esclusa: \(limitation)")
                            .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                    }
                    if report.estimates.isEmpty {
                        Text("Non ci sono categorie con uno storico sufficiente per la stima.")
                            .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                    }
                    ForEach(report.estimates) { estimate in
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: Binding(get: { !excluded.contains(estimate.id) }, set: { included in
                                if included { excluded.remove(estimate.id) } else { excluded.insert(estimate.id) }
                            })) {
                                Text(estimate.name).font(.subheadline.weight(.semibold))
                            }.frame(minHeight: 48).accessibilityIdentifier("monthly-forecast-category-\(estimate.name)")
                            if estimate.budgetID != nil {
                                MonthlyForecastBudgetBasis(estimate: estimate, currency: currency)
                            } else {
                            MonthlyForecastAmountLink(title: "Media mensile nello storico",
                                amount: report.estimateLimitation == nil ? estimate.monthlyAverage(over: report.sampleMonths.count) : nil,
                                currency: currency) {
                                MonthlyForecastDetail(title: estimate.name, events: estimate.samples, currency: currency,
                                    explanation: "Spese abituali dei tre mesi completi precedenti. La media divide il totale per tre, includendo i mesi senza spese. La stima usa invece il valore centrale dei tre totali mensili.") {
                                    ForEach(report.sampleMonths, id: \.timeIntervalSinceReferenceDate) { month in
                                        let rows = estimate.samples.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
                                        LabeledContent(month.formatted(.dateTime.month(.wide).year().locale(monthlyForecastLocale))) {
                                            MonthlyForecastAmount(amount: MonthlyForecast.total(rows), currency: currency)
                                        }
                                    }
                                }
                            }
                            if report.estimateLimitation == nil {
                                LabeledContent("Base mensile della stima") { Text(estimate.monthlyBaseline, format: .currency(code: currency)) }
                                LabeledContent("Ancora da spendere · stima") { Text(estimate.remaining, format: .currency(code: currency)) }
                            }
                            }
                        }
                        if estimate.id != report.estimates.last?.id { Divider() }
                    }
                }.padding(.top, 12)
            }
        }.tint(ForgiaPalette.accent).unifiedCard()
    }
}

private struct MonthlyForecastCoverageSummary: View {
    let report: MonthlyForecast
    let safety: MonthlySafetyMargin?
    let currency: String
    let includingVariables: Bool

    private var status: MonthlyForecast.CoverageStatus {
        report.coverageStatus(safety: safety, includingVariables: includingVariables)
    }
    private var tint: Color {
        switch status {
        case .coveredByBalance: ForgiaPalette.balance
        case .coveredWithPlannedInflows: ForgiaPalette.calendar
        case .shortfall: ForgiaPalette.deficit
        case .unavailable: ForgiaPalette.mutedText
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch status {
            case .coveredByBalance:
                Label("Il saldo basta", systemImage: "checkmark.circle.fill").font(.title3.weight(.semibold))
                if let balance = report.balance, let required = safety?.requiredWithReserve {
                    Text("Hai \(balance, format: .currency(code: currency)) sul conto: coprono i \(required, format: .currency(code: currency)) necessari, inclusa la riserva scelta.")
                }
                if let ending = report.endingProjectedBalance, let reserve = safety?.reserve {
                    let remaining = ending - (includingVariables ? report.variableRemaining ?? 0 : 0) - reserve
                    Text("Dopo i movimenti previsti restano \(remaining, format: .currency(code: currency)) oltre alla riserva.")
                        .font(.subheadline.weight(.medium))
                }
            case .coveredWithPlannedInflows:
                Label("Coperto con le entrate previste", systemImage: "clock.badge.checkmark").font(.title3.weight(.semibold))
                Text("Il saldo di oggi da solo non basta. Le entrate e i trasferimenti programmati permettono di coprire le scadenze e mantenere la riserva, se arrivano nelle date previste.")
            case .shortfall(let gap):
                Label("Serve aggiungere denaro", systemImage: "exclamationmark.circle.fill").font(.title3.weight(.semibold))
                Text("Mancano \(gap, format: .currency(code: currency)) per coprire le spese considerate e mantenere la riserva alle scadenze.")
            case .unavailable:
                Label("Copertura da verificare", systemImage: "questionmark.circle").font(.title3.weight(.semibold))
                if let limitation = report.coverageLimitation { Text(limitation) }
                else if includingVariables, let limitation = report.estimateLimitation { Text(limitation) }
                else { Text("Controlla il saldo, gli importi considerati e la riserva scelta per sapere se il conto basta. Trovi le voci nei dettagli del calcolo.") }
            }
            Text(includingVariables ? "Comprende i budget residui e le stime selezionate. Gli altri imprevisti possono cambiare il risultato." : "Vale per le spese programmate. Le altre spese non programmate restano escluse.")
                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
        }.foregroundStyle(tint).frame(maxWidth: .infinity, alignment: .leading)
            .unifiedCard(tint: tint).accessibilityIdentifier("monthly-forecast-coverage-status")
    }
}

private struct MonthlyForecastSafetyEditor: View {
    let report: MonthlyForecast
    let currency: String
    @Binding var mode: String
    @Binding var value: String
    let safety: MonthlySafetyMargin?
    let includingVariables: Bool
    @FocusState private var editing: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnalysisPreviewHeading(title: "Margine di sicurezza", icon: "shield.lefthalf.filled",
                tint: ForgiaPalette.accent, showsChevron: false)
            Text("Una riserva da tenere sul conto per gli imprevisti.")
                .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            Picker("Come calcolare la riserva", selection: $mode) {
                Text("Percentuale").tag("percentage")
                Text("Importo fisso").tag("fixed")
            }.pickerStyle(.segmented).accessibilityIdentifier("monthly-safety-mode")
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(mode == "percentage" ? "Percentuale del necessario" : "Importo della riserva")
                        .font(.caption.weight(.medium)).foregroundStyle(ForgiaPalette.mutedText)
                    Spacer(minLength: 8)
                    if editing {
                        Button("Fine") { editing = false }
                            .font(.subheadline.weight(.semibold)).buttonStyle(.plain)
                            .foregroundStyle(ForgiaPalette.accent).frame(minWidth: 44, minHeight: 44)
                    }
                }.frame(minHeight: 44)
                HStack(spacing: 12) {
                    TextField(mode == "percentage" ? "0" : "0,00", text: $value)
                        .font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(ForgiaPalette.accent).textFieldStyle(.plain)
                        .focused($editing).submitLabel(.done).onSubmit { editing = false }
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .accessibilityLabel(mode == "percentage" ? "Percentuale del margine di sicurezza" : "Importo del margine di sicurezza in \(currency)")
                        .accessibilityIdentifier("monthly-safety-value")
                    Text(mode == "percentage" ? "%" : currency)
                        .font(.subheadline.weight(.medium)).foregroundStyle(ForgiaPalette.mutedText)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 56)
                .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(editing ? ForgiaPalette.accent : ForgiaPalette.border.opacity(0.4), lineWidth: editing ? 1.5 : 1)
                }
            }
            MonthlyForecastAmountLink(title: "Riserva per imprevisti", amount: safety?.reserve, currency: currency) {
                ScrollView { MonthlyForecastSafetyBasis(report: report, safety: safety, currency: currency, includingVariables: includingVariables).padding(22) }
                    .navigationTitle("Margine di sicurezza").themedBackground(tint: ForgiaPalette.accent)
            }
            if safety == nil {
                Text("Inserisci un numero valido, da zero in su. Puoi usare la virgola o il punto decimale.")
                    .font(.caption).foregroundStyle(ForgiaPalette.deficit)
            } else if mode == "percentage" && report.necessary(includingVariables: includingVariables) == nil {
                Text("La percentuale richiede una base completa. Puoi escludere la stima delle spese abituali oppure scegliere un importo fisso.")
                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            }
            Text("La scelta viene ricordata per questo conto. La riserva non è una spesa prevista e non crea movimenti. Imposta zero per escluderla.")
                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
        }.unifiedCard(tint: ForgiaPalette.accent)
    }
}

private struct MonthlyForecastSafetyBasis: View {
    let report: MonthlyForecast
    let safety: MonthlySafetyMargin?
    let currency: String
    let includingVariables: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Il margine di sicurezza si aggiunge a quanto resta necessario: non alle spese già pagate e non al totale delle spese del mese.")
                .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            LabeledContent("Necessario senza riserva") { MonthlyForecastAmount(amount: report.necessary(includingVariables: includingVariables), currency: currency) }
            if let safety, safety.mode == .percentage {
                LabeledContent("Percentuale scelta") { Text(safety.value / 100, format: .percent) }
            }
            LabeledContent("Riserva scelta") { MonthlyForecastAmount(amount: safety?.reserve, currency: currency) }
            LabeledContent("Necessario + riserva") { MonthlyForecastAmount(amount: safety?.requiredWithReserve, currency: currency) }
        }
    }
}

private struct MonthlyForecastSummary: View {
    let report: MonthlyForecast
    let currency: String
    let safety: MonthlySafetyMargin?
    @Binding var includingVariables: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnalysisPreviewHeading(title: report.period == .past ? "Consuntivo del mese" : "Quanto resta da pagare",
                icon: "calendar.badge.clock", tint: ForgiaPalette.accent, illustration: .budget, showsChevron: false)
            if report.period != .past {
                MonthlyForecastAmountLink(title: "Totale ancora necessario", amount: safety?.requiredWithReserve, currency: currency, prominent: true) {
                    MonthlyForecastDetail(title: "Totale ancora necessario", events: report.recurring + report.occasional,
                        currency: currency, explanation: "Ricorrenti e occasionali programmate ancora da pagare, più la riserva scelta. I budget residui e le spese abituali stimate si aggiungono solo se attivi l'opzione; le spese già registrate sono escluse.") {
                        MonthlyForecastSafetyBasis(report: report, safety: safety, currency: currency, includingVariables: includingVariables)
                        if includingVariables { MonthlyForecastEstimateBasis(report: report, currency: currency) }
                    }
                }
                if report.necessary(includingVariables: includingVariables) != nil {
                    Text(includingVariables ? "Scadenze note + budget e stime scelti + riserva" : "Scadenze note + riserva scelta. Escluse le altre spese non programmate.")
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                }
                Toggle("Aggiungi budget e spese abituali", isOn: $includingVariables)
                    .tint(ForgiaPalette.accent).accessibilityIdentifier("monthly-forecast-include-variables")
                if report.necessary(includingVariables: includingVariables) == nil {
                    Text("Il totale con stima non è disponibile. Disattiva l'opzione per consultare solo gli impegni conosciuti.")
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                }
            }
            Divider().padding(.vertical, 2)
            MonthlyForecastAmountLink(title: report.period == .past ? "Spese registrate" : "Totale del mese · include le registrate",
                                      amount: report.monthTotal(includingVariables: includingVariables), currency: currency) {
                MonthlyForecastDetail(title: "Totale del mese", events: report.recorded + (report.period == .past ? [] : report.recurring + report.occasional),
                                      currency: currency, explanation: "Registrate + scadenze residue; le spese abituali residue si aggiungono solo se attivi l'opzione. La riserva resta separata. Nei mesi conclusi: solo spese registrate.") {
                    if report.period != .past && includingVariables { MonthlyForecastEstimateBasis(report: report, currency: currency) }
                }
            }
        }.unifiedCard(tint: ForgiaPalette.accent).financeCardEntrance()
    }
}

private struct MonthlyForecastCommitments: View {
    let report: MonthlyForecast
    let currency: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnalysisPreviewHeading(title: "Spese e scadenze", icon: "calendar", tint: ForgiaPalette.calendar, showsChevron: false)
            MonthlyForecastEventLink(title: "Ricorrenti ancora da registrare", events: report.recurring, currency: currency,
                explanation: "Include le ricorrenze scadute del mese ancora irrisolte. Le occorrenze saltate o già registrate sono escluse. Apri la serie originale per verificarle.")
            MonthlyForecastEventLink(title: "Occasionali programmate da pagare", events: report.occasional, currency: currency,
                explanation: "Movimenti non ricorrenti con una data futura nel mese, già presenti nel registro.")
            MonthlyForecastEventLink(title: "Impegni conosciuti · senza stime", events: report.recurring + report.occasional, currency: currency,
                explanation: "Somma delle ricorrenti irrisolte e delle spese occasionali programmate.")
            if report.period != .past {
                MonthlyForecastAmountLink(title: "Variabili residue · budget e stime", amount: report.variableRemaining, currency: currency) {
                    ScrollView { MonthlyForecastEstimateBasis(report: report, currency: currency).padding(22) }
                        .navigationTitle("Base della stima")
                }
            }
            Divider()
            MonthlyForecastEventLink(title: "Già registrate", events: report.recorded, currency: currency, explanation: "Spese del mese con data non successiva a oggi.")
            MonthlyForecastEventLink(title: "Di cui occasionali programmate", events: report.recordedOccasional, currency: currency,
                explanation: "Provenienza dalla programmazione conservata dopo il pagamento. Per i dati precedenti, la creazione prima del giorno della scadenza costituisce la base della distinzione.")
            MonthlyForecastEventLink(title: "Di cui non programmate", events: report.recordedUnscheduled, currency: currency,
                explanation: "Spese non ricorrenti già sostenute, senza evidenza di programmazione. Non sono imprevisti futuri e non vengono aggiunte alle scadenze.")
            Text("Gli imprevisti futuri non sono stimati. Gli importi programmati sono impegni conosciuti, non una conferma di pagamento.")
                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
        }.unifiedCard()
    }
}

private struct MonthlyForecastCoverage: View {
    let report: MonthlyForecast
    let currency: String
    let safety: MonthlySafetyMargin?
    let includingVariables: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnalysisPreviewHeading(title: "Copertura delle scadenze", icon: "wallet.bifold",
                tint: ForgiaPalette.balance, illustration: .balance, showsChevron: false)
            MonthlyForecastAmountLink(title: "Saldo attuale del conto", amount: report.balance, currency: currency) {
                MonthlyForecastDetail(title: "Saldo attuale", events: report.balanceMovements, currency: currency,
                    explanation: "Saldo iniziale + entrate − spese + trasferimenti ricevuti − trasferimenti inviati. Solo movimenti con data non successiva a oggi.") {
                    if let opening = report.openingBalance {
                        LabeledContent("Saldo iniziale") { Text(opening, format: .currency(code: currency)) }
                    } else { Text("Saldo iniziale da verificare") }
                }
            }
            MonthlyForecastEventLink(title: "Entrate programmate", events: report.income, currency: currency,
                explanation: "Solo entrate già programmate o ricorrenze irrisolte. Le entrate scadute non contribuiscono alla copertura finché non vengono registrate.")
            MonthlyForecastEventLink(title: "Trasferimenti programmati · saldo netto", events: report.transfers, currency: currency,
                explanation: "Apporti da altri conti e giroconti in uscita, con segno dal punto di vista di questo conto. Non sono consumi né nuove entrate. Non vengono ipotizzati trasferimenti mancanti.")
            if let limitation = report.coverageLimitation {
                Text(limitation).font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            } else {
                MonthlyForecastAmountLink(title: "Quanto manca alle scadenze", amount: report.deadlineShortfall, currency: currency) {
                    MonthlyForecastDetail(title: "Copertura delle scadenze", events: report.recurring + report.occasional + report.income + report.transfers,
                        currency: currency, explanation: "Partiamo dal saldo attuale e calcoliamo il saldo netto per giorno. L'importo è il massimo deficit prima di fine mese. Un'entrata successiva non copre una scadenza precedente; l'ordine all'interno dello stesso giorno non è stimato.") {
                        if let balance = report.balance {
                            LabeledContent("Saldo di partenza") { Text(balance, format: .currency(code: currency)) }
                        }
                    }
                }
                MonthlyForecastAmountLink(title: "Quanto manca includendo la stima", amount: report.estimatedShortfall, currency: currency) {
                    MonthlyForecastDetail(title: "Copertura con variabili", events: report.recurring + report.occasional + report.income + report.transfers,
                        currency: currency, explanation: "Massimo tra il deficit delle scadenze e il deficit a fine mese aggiungendo le variabili residue. Le variabili non hanno una data prevista: può servire liquidità prima.") {
                        MonthlyForecastEstimateBasis(report: report, currency: currency)
                    }
                }
                let gap = safety?.shortfall(minimumBalance: report.minimumProjectedBalance,
                    endingBalance: report.endingProjectedBalance, variableRemaining: includingVariables ? report.variableRemaining : 0)
                MonthlyForecastAmountLink(title: "Quanto manca con la riserva", amount: gap, currency: currency) {
                    MonthlyForecastDetail(title: "Copertura con riserva", events: report.recurring + report.occasional + report.income + report.transfers,
                        currency: currency, explanation: "La riserva deve restare disponibile dopo ogni scadenza. Le variabili stimate si aggiungono a fine mese solo se attivi l'opzione. Entrate successive non coprono scadenze precedenti.") {
                        MonthlyForecastSafetyBasis(report: report, safety: safety, currency: currency, includingVariables: includingVariables)
                        if includingVariables { MonthlyForecastEstimateBasis(report: report, currency: currency) }
                    }
                }
            }
        }.unifiedCard()
    }
}

private struct MonthlyForecastEventLink: View {
    let title: String
    let events: [FinanceCalendarEvent]
    let currency: String
    let explanation: String
    var body: some View {
        MonthlyForecastAmountLink(title: title, amount: MonthlyForecast.total(events), currency: currency) {
            MonthlyForecastDetail(title: title, events: events, currency: currency, explanation: explanation) { EmptyView() }
        }
    }
}

private struct MonthlyForecastAmountLink<Detail: View>: View {
    let title: String
    let amount: Decimal?
    let currency: String
    var prominent = false
    @ViewBuilder let detail: () -> Detail
    var body: some View {
        NavigationLink(destination: detail) {
            HStack(spacing: 12) {
                if prominent {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                        if let amount {
                            Text(amount, format: .currency(code: currency))
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                .monospacedDigit().financeNumericMotion(amount)
                                .foregroundStyle(ForgiaPalette.accent)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Non disponibile").font(.title3.weight(.semibold))
                                .foregroundStyle(ForgiaPalette.mutedText)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { Text(title); Spacer(minLength: 8); MonthlyForecastAmount(amount: amount, currency: currency) }
                        VStack(alignment: .leading, spacing: 6) { Text(title); MonthlyForecastAmount(amount: amount, currency: currency) }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.subheadline).foregroundStyle(.primary)
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            }.frame(minHeight: 48).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct MonthlyForecastAmount: View {
    let amount: Decimal?
    let currency: String
    var body: some View {
        Group {
            if let amount {
                Text(amount, format: .currency(code: currency)).font(.system(.subheadline, design: .rounded, weight: .semibold)).monospacedDigit()
                    .financeNumericMotion(amount).foregroundStyle(ForgiaPalette.calendar)
            } else { Text("Non disponibile").font(.caption).foregroundStyle(ForgiaPalette.mutedText) }
        }
    }
}

private struct MonthlyForecastDetail<Supplement: View>: View {
    let title: String
    let events: [FinanceCalendarEvent]
    let currency: String
    let explanation: String
    @ViewBuilder let supplement: () -> Supplement
    @Query private var transactions: [FinanceCore.Transaction]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(explanation).font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).cardInset()
                supplement()
                if events.isEmpty { Text("Nessun movimento in questa voce.").foregroundStyle(ForgiaPalette.mutedText) }
                ForEach(events) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.date.formatted(.dateTime.day().month().year().locale(monthlyForecastLocale))).font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                        if let row = transactions.first(where: { $0.id == event.transactionID }) {
                            NavigationLink { TransactionDetailView(transaction: row) } label: {
                                FinanceCalendarEventRow(event: event, currency: currency)
                            }.buttonStyle(.plain).frame(minHeight: 48)
                        } else { FinanceCalendarEventRow(event: event, currency: currency) }
                    }
                }
            }.frame(maxWidth: 760).frame(maxWidth: .infinity).padding(22)
        }.navigationTitle(Text(title)).themedBackground(tint: ForgiaPalette.calendar)
    }
}

private struct MonthlyForecastEstimateBasis: View {
    let report: MonthlyForecast
    let currency: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let limitation = report.estimateLimitation { Text(limitation).foregroundStyle(ForgiaPalette.mutedText) }
            if report.hasBudgetBasis {
                Text("I budget mensili selezionati sostituiscono lo storico delle proprie categorie. Dal limite sottraiamo le spese registrate e le scadenze già comprese negli impegni; aggiungiamo soltanto il residuo, mai un importo negativo.")
                    .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            }
            if report.estimates.contains(where: { $0.budgetID == nil }) {
            Text("Per ogni singola categoria usiamo il valore centrale dei totali dei tre mesi completi precedenti, includendo i mesi senza spese. Servono almeno tre movimenti in almeno due mesi. Questo limita il peso di un mese eccezionale. Sottraiamo le spese già registrate e le occasionali programmate della stessa categoria; il residuo non scende sotto zero. Le fatture di altre categorie non riducono, ad esempio, la stima del supermercato.")
                .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            ForEach(report.sampleMonths, id: \.timeIntervalSinceReferenceDate) { month in
                Text(month.formatted(.dateTime.month(.wide).year().locale(monthlyForecastLocale))).font(.caption)
            }
            }
            ForEach(report.estimates) { estimate in
                if estimate.budgetID != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(estimate.name).font(.headline)
                        MonthlyForecastBudgetBasis(estimate: estimate, currency: currency)
                    }.unifiedCard()
                } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(estimate.name).font(.headline)
                    if report.estimateLimitation == nil {
                        LabeledContent("Base mensile abituale") { Text(estimate.monthlyBaseline, format: .currency(code: currency)) }
                        MonthlyForecastEventLink(title: "Variabili già registrate", events: estimate.recordedSamples, currency: currency,
                            explanation: "Spese variabili del mese sottratte dalla base abituale di questa categoria.")
                        MonthlyForecastEventLink(title: "Occasionali programmate · anche già pagate", events: estimate.scheduledSamples, currency: currency,
                            explanation: "Occasionali del mese sottratte dalla base abituale della stessa categoria per evitare un doppio conteggio.")
                        LabeledContent("Residuo stimato") { Text(estimate.remaining, format: .currency(code: currency)) }
                    }
                    MonthlyForecastEventLink(title: "Movimenti della base storica", events: estimate.samples,
                        currency: currency, explanation: "Spese della categoria usate nella stima: sommiamo ciascun mese e scegliamo il valore centrale dei tre totali. Non è una previsione certa delle prossime spese.")
                }.unifiedCard()
                }
            }
            if !report.historyExclusions.isEmpty {
                Text("Movimenti esclusi dalla stima").font(.headline)
                Text("Restano nel registro e nel saldo. I possibili pagamenti ricorrenti vengono esclusi solo dalla stima, senza contrassegnare alcuna scadenza come pagata.")
                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                ForEach(report.historyExclusions) { exclusion in
                    MonthlyForecastEventLink(title: String(localized: exclusion.reason.explanation), events: exclusion.events,
                        currency: currency, explanation: String(localized: exclusion.reason.explanation))
                }
            }
        }
    }
}

private struct MonthlyForecastBudgetBasis: View {
    let estimate: MonthlyVariableEstimate
    let currency: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Budget mensile · sostituisce lo storico delle categorie incluse")
                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            if let limitation = estimate.limitation {
                Text(limitation).font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            } else {
                LabeledContent("Limite mensile") { Text(estimate.monthlyBaseline, format: .currency(code: currency)) }
                MonthlyForecastEventLink(title: "Spese già registrate", events: estimate.recordedSamples, currency: currency,
                    explanation: "Spese del conto e delle categorie del budget già registrate nel mese.")
                MonthlyForecastEventLink(title: "Scadenze già nel totale", events: estimate.scheduledSamples, currency: currency,
                    explanation: "Scadenze considerate separatamente: vengono sottratte dal budget per non contarle due volte.")
                LabeledContent("Budget residuo da aggiungere") { Text(estimate.remaining, format: .currency(code: currency)) }
            }
        }.font(.subheadline)
    }
}

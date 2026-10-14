import SwiftUI
import SwiftData
import FinanceCore

private var monthlyForecastLocale: Locale {
    Locale(identifier: Locale.preferredLanguages.first ?? Locale.current.identifier)
}

struct MonthlyForecastView: View {
    let conti: [Conto]
    let currency: String
    @Query private var transactions: [FinanceCore.Transaction]
    @Query private var resolutions: [RecurrenceResolution]
    @State private var selectedID: UUID?
    @State private var month: Date

    init(conti: [Conto], currency: String, initialDate: Date = Date()) {
        self.conti = conti
        self.currency = currency
        _selectedID = State(initialValue: conti.first?.id)
        _month = State(initialValue: initialDate)
    }

    var body: some View {
        let selected = conti.first { $0.id == selectedID } ?? conti.first
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MonthlyForecastAccountPicker(conti: conti, selection: $selectedID)
                MonthlyForecastMonthPicker(month: $month)
                if let selected {
                    let report = MonthlyForecastCalculator.build(conto: selected, transactions: transactions,
                        resolutions: resolutions, month: month)
                    MonthlyForecastAccountContent(report: report, contoID: selected.id, currency: currency)
                        .id(selected.id)
                } else {
                    ContentUnavailableView("Nessun conto disponibile", systemImage: "wallet.bifold")
                }
            }.frame(maxWidth: 760).frame(maxWidth: .infinity).padding(22)
        }
        .themedBackground(tint: ForgiaPalette.calendar)
        .navigationTitle("Previsione del mese")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: conti.map(\.id)) {
            if !conti.contains(where: { $0.id == selectedID }) { selectedID = conti.first?.id }
        }
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
    var body: some View {
        HStack {
            Button("Mese precedente", systemImage: "chevron.left") {
                month = Calendar.current.date(byAdding: .month, value: -1, to: month)!
            }.labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                .frame(width: 48, height: 48).accessibilityIdentifier("monthly-forecast-previous")
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
    let report: MonthlyForecast
    let currency: String
    @AppStorage private var mode: String
    @AppStorage private var percentageText: String
    @AppStorage private var fixedText: String

    init(report: MonthlyForecast, contoID: UUID, currency: String) {
        self.report = report
        self.currency = currency
        let key = "formi.forecast.safety.\(contoID.uuidString).\(currency)"
        _mode = AppStorage(wrappedValue: "percentage", "\(key).mode")
        _percentageText = AppStorage(wrappedValue: "0", "\(key).percentage")
        _fixedText = AppStorage(wrappedValue: "0", "\(key).fixed")
    }

    var body: some View {
        let selectedMode = MonthlySafetyMargin.Mode(rawValue: mode) ?? .percentage
        let input = selectedMode == .percentage ? percentageText : fixedText
        let safety = MarginScenario.expense(from: input).flatMap {
            MonthlySafetyMargin(necessary: report.remaining, mode: selectedMode, value: $0, currency: currency)
        }
        VStack(alignment: .leading, spacing: 20) {
            MonthlyForecastSummary(report: report, currency: currency, safety: safety)
            if report.period != .past {
                MonthlyForecastSafetyEditor(report: report, currency: currency, mode: $mode,
                    value: selectedMode == .percentage ? $percentageText : $fixedText, safety: safety)
            }
            MonthlyForecastCommitments(report: report, currency: currency)
            MonthlyForecastCoverage(report: report, currency: currency, safety: safety)
        }
    }
}

private struct MonthlyForecastSafetyEditor: View {
    let report: MonthlyForecast
    let currency: String
    @Binding var mode: String
    @Binding var value: String
    let safety: MonthlySafetyMargin?
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
                ScrollView { MonthlyForecastSafetyBasis(report: report, safety: safety, currency: currency).padding(22) }
                    .navigationTitle("Margine di sicurezza").themedBackground(tint: ForgiaPalette.accent)
            }
            if safety == nil {
                Text("Inserisci un numero valido, da zero in su. Puoi usare la virgola o il punto decimale.")
                    .font(.caption).foregroundStyle(ForgiaPalette.deficit)
            } else if mode == "percentage" && report.remaining == nil {
                Text("La percentuale richiede una previsione completa. Con storico insufficiente puoi scegliere un importo fisso; il totale completo resta non disponibile.")
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
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Il margine di sicurezza si aggiunge a quanto resta necessario: non alle spese già pagate e non al totale delle spese del mese.")
                .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            LabeledContent("Necessario senza riserva") { MonthlyForecastAmount(amount: report.remaining, currency: currency) }
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
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnalysisPreviewHeading(title: report.period == .past ? "Consuntivo del mese" : "Quanto resta da coprire",
                icon: "calendar.badge.clock", tint: ForgiaPalette.accent, illustration: .budget, showsChevron: false)
            if report.period != .past {
                MonthlyForecastAmountLink(title: "Totale ancora necessario", amount: safety?.requiredWithReserve, currency: currency, prominent: true) {
                    MonthlyForecastDetail(title: "Totale ancora necessario", events: report.recurring + report.occasional,
                        currency: currency, explanation: "Scadenze ancora da registrare + variabili residue stimate. Le spese già registrate sono escluse.") {
                        MonthlyForecastSafetyBasis(report: report, safety: safety, currency: currency)
                        MonthlyForecastEstimateBasis(report: report, currency: currency)
                    }
                }
                if report.remaining != nil {
                    Text((safety?.reserve ?? 0) > 0 ? "Spese previste + margine di sicurezza" : "Scadenze note + spese abituali stimate")
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                }
                if report.remaining == nil {
                    Text("Il totale completo non è disponibile. Gli impegni conosciuti restano consultabili qui sotto.")
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                }
            }
            Divider().padding(.vertical, 2)
            MonthlyForecastAmountLink(title: report.period == .past ? "Spese registrate" : "Totale del mese · include le registrate",
                                      amount: report.monthTotal, currency: currency) {
                MonthlyForecastDetail(title: "Totale del mese", events: report.recorded + (report.period == .past ? [] : report.recurring + report.occasional),
                                      currency: currency, explanation: "Nel mese corrente e futuro: registrate + scadenze residue + stima residua. Nei mesi conclusi: solo spese registrate.") {
                    if report.period != .past { MonthlyForecastEstimateBasis(report: report, currency: currency) }
                }
            }
        }.unifiedCard(tint: ForgiaPalette.accent).financeCardEntrance()
            .accessibilityIdentifier("monthly-forecast-summary")
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
                MonthlyForecastAmountLink(title: "Variabili residue · stima", amount: report.variableRemaining, currency: currency) {
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
                    endingBalance: report.endingProjectedBalance, variableRemaining: report.variableRemaining)
                MonthlyForecastAmountLink(title: "Quanto manca con la riserva", amount: gap, currency: currency) {
                    MonthlyForecastDetail(title: "Copertura con riserva", events: report.recurring + report.occasional + report.income + report.transfers,
                        currency: currency, explanation: "La riserva deve restare disponibile dopo ogni scadenza e dopo le variabili stimate a fine mese. Calcoliamo il massimo deficit rispetto a questa soglia; entrate successive non coprono scadenze precedenti.") {
                        MonthlyForecastSafetyBasis(report: report, safety: safety, currency: currency)
                        MonthlyForecastEstimateBasis(report: report, currency: currency)
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
            Text("Media mensile dei tre mesi completi precedenti a oggi, per macro categoria, con mesi senza spese pari a zero. Esclude ricorrenti, trasferimenti e occasionali con evidenza di programmazione. Dalla media sottraiamo le variabili già registrate e le occasionali programmate del mese scelto; il residuo non scende sotto zero. Non è una previsione stagionale.")
                .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            ForEach(report.sampleMonths, id: \.timeIntervalSinceReferenceDate) { month in
                Text(month.formatted(.dateTime.month(.wide).year().locale(monthlyForecastLocale))).font(.caption)
            }
            ForEach(report.estimates) { estimate in
                VStack(alignment: .leading, spacing: 8) {
                    Text(estimate.name).font(.headline)
                    if report.estimateLimitation == nil {
                        LabeledContent("Media mensile") { Text(estimate.monthlyAverage, format: .currency(code: currency)) }
                        MonthlyForecastEventLink(title: "Variabili già registrate", events: estimate.recordedSamples, currency: currency,
                            explanation: "Spese variabili del mese sottratte dalla media di questa categoria.")
                        MonthlyForecastEventLink(title: "Occasionali programmate · anche già pagate", events: estimate.scheduledSamples, currency: currency,
                            explanation: "Occasionali del mese sottratte dalla media per evitare un doppio conteggio.")
                        LabeledContent("Residuo stimato") { Text(estimate.remaining, format: .currency(code: currency)) }
                    }
                    MonthlyForecastEventLink(title: "Movimenti della base storica", events: estimate.samples,
                        currency: currency, explanation: "Spese variabili usate nella media di questa categoria. La somma è divisa per tre mesi, inclusi i mesi senza movimenti.")
                }.unifiedCard()
            }
        }
    }
}

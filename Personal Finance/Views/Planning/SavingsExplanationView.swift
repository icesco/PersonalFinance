import SwiftUI
import Charts
import FinanceCore

struct SavingsExplanationView: View {
    var plan: BudgetingPlan? = nil
    var monthlyReport: MonthlySavingsReport? = nil
    var recordedReport: RecordedSavingsReport? = nil
    var currency = "EUR"
    @Environment(\.dismiss) private var dismiss
    @State private var showingGuides = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "chart.bar.xaxis").font(.largeTitle).foregroundStyle(ForgiaPalette.accent)
                        Text("Dai un significato ai numeri").font(.system(.title, design: .serif, weight: .semibold))
                        Text("Il piano ti aiuta a dare spazio alle necessità, ai desideri e ai tuoi progetti. Il grafico confronta ciò che hai registrato con il riferimento che hai scelto.")
                            .foregroundStyle(.secondary)
                    }
                    SavingsChartReadingGuide(currency: currency)
                    SavingsAdviceSection(plan: plan, monthlyReport: monthlyReport, recordedReport: recordedReport, currency: currency)
                    SavingsAllocationIllustration(plan: plan, currency: currency)
                    SavingsTransferIllustration(currency: currency)
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Come partire", systemImage: "signpost.right").font(.headline)
                        Text("Scegli entrate nette mensili di riferimento, distribuisci le categorie e controlla l'anteprima. Durante il mese registra i movimenti e rivedi i limiti quando cambiano entrate o impegni.")
                        Text("I conti di risparmio sono facoltativi. Per misurare gli accantonamenti scegli i conti dedicati e registra anche trasferimenti e uscite. Sarai tu a effettuare gli accantonamenti.")
                        Text("Saldi iniziali, ricorrenze future e progressi inseriti manualmente negli obiettivi sono esclusi dal calcolo. I risultati descrivono i dati registrati, che possono essere incompleti.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button { showingGuides = true } label: { Label("Guide e approfondimenti", systemImage: "book") }
                        Link("Consigli sul budget · CFPB", destination: URL(string: "https://www.consumerfinance.gov/archive/blog/budgeting-how-to-create-a-budget-and-stick-with-it/")!)
                            .font(.caption)
                    }.unifiedCard()
                }.padding(22)
            }
            .themedBackground()
            .navigationTitle("Come funziona il risparmio")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
            .financePresentation(isPresented: $showingGuides, title: "Guide", width: 640) { BudgetingGuidesView() }
        }
    }
}

private struct SavingsChartReadingGuide: View {
    let currency: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Come leggere il grafico").font(.headline)
            SavingsComparisonChart(title: "Esempio · accantonamenti", actual: 220, reference: 400,
                currency: currency, isCeiling: false, isInProgress: true)
            Text("La barra piena è il valore registrato; la linea tratteggiata è il limite o l'obiettivo. Una barra sotto zero indica un valore negativo.")
                .font(.subheadline)
            Text("Per le spese, restare entro il limite è in linea con il piano. Per il risparmio, raggiungere l'obiettivo è in linea con il piano. Nel mese ancora aperto un obiettivo da completare resta in corso.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Il tasso è (entrate − spese) ÷ entrate × 100. Per più mesi si usano i totali, non la media delle percentuali. Descrive il margine: gli accantonamenti sono una misura distinta. Senza un obiettivo applicabile al periodo e ai conti selezionati, il grafico mostra il valore senza assegnargli un voto.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Rimborsi, prestiti e disinvestimenti registrati come entrate possono alterare il tasso. Controlla la classificazione dei movimenti prima di interpretarlo.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct SavingsAllocationIllustration: View {
    let plan: BudgetingPlan?
    let currency: String
    private var example: BudgetingPlan {
        if let plan, plan.method != .manual { return plan }
        return BudgetingPlan(monthlyIncome: 2000)
    }
    private var slices: [SavingsAllocationSlice] {
        [SavingsAllocationSlice(id: "needs", title: "Necessità", amount: example.roundedLimit(for: .needs, currency: currency), color: ForgiaPalette.accent),
         SavingsAllocationSlice(id: "wants", title: "Desideri", amount: example.roundedLimit(for: .wants, currency: currency), color: .orange),
         SavingsAllocationSlice(id: "savings", title: "Risparmio", amount: example.roundedSavingsTarget(currency: currency), color: .blue)]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(plan?.method != nil && plan?.method != .manual ? "La distribuzione scelta" : "Un esempio con il 50/30/20").font(.headline)
            ZStack {
                Chart(slices.filter { $0.amount > 0 }) { slice in
                    SectorMark(angle: .value("Quota", NSDecimalNumber(decimal: slice.amount).doubleValue),
                               innerRadius: .ratio(0.68), angularInset: 3)
                        .foregroundStyle(slice.color).cornerRadius(5)
                }.chartLegend(.hidden).accessibilityHidden(true)
                VStack(spacing: 3) {
                    SavingsChartValue(value: example.monthlyIncome, currency: currency).font(.headline)
                    Text("Entrate di riferimento").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(height: 180)
            ForEach(slices) { slice in
                HStack {
                    Circle().fill(slice.color).frame(width: 10, height: 10).accessibilityHidden(true)
                    SavingsAmountRow(title: slice.title, amount: slice.amount, currency: currency)
                }.accessibilityElement(children: .combine)
            }
            Text("L'app prepara due limiti di spesa e un obiettivo di risparmio. Puoi adattare la distribuzione alla tua situazione.")
                .font(.caption).foregroundStyle(.secondary)
        }.unifiedCard()
    }
}

private struct SavingsAllocationSlice: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let amount: Decimal
    let color: Color
}

private struct SavingsTransferIllustration: View {
    let currency: String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Margine e accantonamenti sono diversi").font(.headline)
            Text("Un esempio di movimenti registrati").font(.caption).foregroundStyle(.secondary)
            SavingsAmountRow(title: "Entrate", amount: 2000, currency: currency)
            SavingsAmountRow(title: "Spese", amount: 1600, currency: currency)
            SavingsAmountRow(title: "Margine", amount: 400, currency: currency)
            Divider()
            Label("Dal corrente al risparmio", systemImage: "arrow.right.circle.fill").foregroundStyle(ForgiaPalette.accent)
            SavingsAmountRow(title: "Importo accantonato", amount: 300, currency: currency)
            Label("Dal risparmio al corrente", systemImage: "arrow.left.circle.fill").foregroundStyle(.orange)
            SavingsAmountRow(title: "Importo utilizzato", amount: 80, currency: currency)
            SavingsComparisonChart(title: "Accantonamenti netti", actual: 220, reference: 400, currency: currency, isCeiling: false, isInProgress: true)
            Text("300 − 80 = 220 accantonati. I 400 di margine restano una misura diversa. I trasferimenti tra due conti di risparmio selezionati si annullano.")
                .font(.caption).foregroundStyle(.secondary)
        }.unifiedCard()
    }
}

private struct SavingsAdviceSection: View {
    let plan: BudgetingPlan?
    let monthlyReport: MonthlySavingsReport?
    let recordedReport: RecordedSavingsReport?
    let currency: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Un passo utile per te", systemImage: "lightbulb").font(.headline)
            if let report = monthlyReport, !report.hasInvalidAmounts {
                if report.income <= 0 {
                    Text("Prima verifica le entrate del mese") .font(.subheadline.weight(.semibold))
                    Text("Non risultano entrate positive registrate. Controlla che i movimenti del libro siano completi prima di interpretare il margine.")
                } else if report.margin < 0 {
                    Text("Le spese registrate superano le entrate").font(.subheadline.weight(.semibold))
                    Text("Controlla quali categorie pesano di più e le prossime scadenze. Verifica anche eventuali entrate mancanti prima di rivedere il piano.")
                } else {
                    Text("Hai un margine positivo o in equilibrio").font(.subheadline.weight(.semibold))
                    Text("Confronta il margine con gli impegni ancora da pagare. Poi decidi quanto destinare ai tuoi progetti e registra gli accantonamenti quando li effettui.")
                }
                if let plan, plan.method != .manual {
                    if report.unclassifiedExpenses != 0 { Text("Completa le categorie del piano: alcune spese non sono ancora nel confronto tra necessità e desideri.") }
                    if report.needsSpent > plan.roundedLimit(for: .needs, currency: currency) {
                        Text("Le necessità hanno superato il limite scelto. Valuta se il riferimento è sostenibile rispetto alle spese essenziali e, se serve, adatta le percentuali.")
                    }
                    if report.wantsSpent > plan.roundedLimit(for: .wants, currency: currency) {
                        Text("I desideri hanno superato il limite scelto. Guarda le categorie di questo gruppo prima di decidere cosa ridurre o rinviare.")
                    }
                }
                if report.netSetAside == nil {
                    Text(report.needsSavingsReview ? "Rivedi la selezione dei conti di risparmio: alcuni non sono più disponibili o hanno cambiato tipo." : "Se vuoi misurare gli accantonamenti, scegli i conti di risparmio dal pulsante di modifica del piano.")
                } else if let net = report.netSetAside, net < 0 {
                    Text("Hai utilizzato più fondi accantonati di quanti ne hai aggiunti nel mese. Verifica i movimenti e rivedi l'obiettivo in base agli impegni attuali.")
                }
            } else if let report = recordedReport {
                if report.hasInvalidAmounts { Text("Controlla gli importi mancanti o non validi prima di interpretare il risultato.") }
                else if report.income <= 0 { Text("Controlla le entrate registrate nel periodo: senza entrate positive il tasso non è calcolabile.") }
                else if report.remainder < 0 { Text("Le spese registrate superano le entrate. Guarda le categorie che pesano di più e verifica che i movimenti del periodo siano completi.") }
                else { Text("Il periodo mostra un margine disponibile dopo le spese registrate. Confrontalo con gli impegni ancora da pagare prima di decidere quanto accantonare.") }
            } else {
                Text("Parti da una distribuzione sostenibile e aggiorna il piano quando cambiano entrate o impegni. Un metodo è un riferimento che puoi adattare.")
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .unifiedCard()
    }
}

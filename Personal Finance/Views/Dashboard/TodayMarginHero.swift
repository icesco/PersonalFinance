import SwiftUI
import FinanceCore

struct TodayMarginHero: View {
    let margin: Decimal
    let available: Decimal
    let currency: String
    var expense: Decimal? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var remaining: Decimal { expense.flatMap { MarginScenario(margin: margin, expense: $0, currency: currency)?.remaining } ?? margin }
    private var hasBoundedShare: Bool { available > 0 && margin >= 0 && margin <= available }
    private var share: Double { hasBoundedShare ? NSDecimalNumber(decimal: max(0, remaining) / available).doubleValue : 0 }
    private var tint: Color { remaining < 0 ? ForgiaPalette.deficit : remaining == 0 ? ForgiaPalette.calendar : ForgiaPalette.margin }

    var body: some View {
        VStack(spacing: 8) {
            if hasBoundedShare && !dynamicTypeSize.isAccessibilitySize {
                FinancialRing(share: share, tint: tint,
                              referenceShare: expense == nil ? nil : NSDecimalNumber(decimal: margin / available).doubleValue) {
                    marginValue
                }
                .frame(maxWidth: 280)
                Text(share, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.weight(.medium)).monospacedDigit()
                    .foregroundStyle(tint)
                    .accessibilityLabel("Quota residua del saldo netto")
                    .accessibilityValue(Text(share, format: .percent.precision(.fractionLength(0))))
                Text("del saldo netto")
                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            } else {
                marginValue
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var marginValue: some View {
        VStack(spacing: 6) {
            Text(expense == nil ? "Margine stimato" : "Dopo l’imprevisto")
                .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            Text(remaining, format: .currency(code: currency))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.26), value: remaining)
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.5)
                .accessibilityIdentifier("margin-scenario-remaining")
            Text(remaining < 0 ? "Oltre il margine" : remaining == 0 ? "Margine esaurito" : "Residuo stimato")
                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
    }
}

struct MarginScenarioSection: View {
    let margin: Decimal
    let available: Decimal
    let currency: String
    @State private var amountText = "300"
    @FocusState private var editing: Bool
    private var expense: Decimal? { MarginScenario.expense(from: amountText) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Simula un imprevisto").font(.headline)
            HStack {
                Text("Importo in \(currency)").font(.subheadline)
                Spacer(minLength: 8)
                TextField("Importo", text: $amountText)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
                    .textFieldStyle(.roundedBorder)
                    .focused($editing)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .accessibilityLabel("Importo dell’imprevisto in \(currency)")
                    .accessibilityIdentifier("margin-scenario-expense")
            }
            if editing {
                Button("Fine") { editing = false }.buttonStyle(.bordered)
            }
            TodayMarginHero(margin: margin, available: available, currency: currency, expense: expense)
            if let expense, let scenario = MarginScenario(margin: margin, expense: expense, currency: currency) {
                Text(scenario.remaining < 0
                     ? "Mancherebbero \(-scenario.remaining, format: .currency(code: currency))"
                     : "Resterebbero \(scenario.remaining, format: .currency(code: currency))")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("margin-scenario-result")
                if available > 0 && margin >= 0 && margin <= available {
                    HStack(spacing: 12) {
                        Label("Residuo", systemImage: "circle.fill").foregroundStyle(scenario.remaining < 0 ? ForgiaPalette.deficit : scenario.remaining == 0 ? ForgiaPalette.calendar : ForgiaPalette.margin)
                        Label("Prima dell’imprevisto", systemImage: "circle.fill").foregroundStyle(ForgiaPalette.spending)
                    }.font(.caption)
                }
            } else {
                Text("Inserisci un importo valido, da zero in su.")
                    .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                    .accessibilityIdentifier("margin-scenario-invalid")
            }
            Text("Nessun movimento registrato")
                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            MarginScenarioExplanation(available: available, currency: currency,
                                      showsSegments: available > 0 && margin >= 0 && margin <= available)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

private struct MarginScenarioExplanation: View {
    let available: Decimal
    let currency: String
    let showsSegments: Bool

    var body: some View {
        DisclosureGroup("Come funziona") {
            VStack(alignment: .leading, spacing: 8) {
                if showsSegments {
                    Text("La finestra ingrandisce il settore della quota residua, con una parte dei settori vicini. Il pallino indica il valore esatto.")
                    Text("Ogni segmento rappresenta 1/6 del saldo netto di \(available, format: .currency(code: currency)).")
                }
                Text("La simulazione sottrae solo questo imprevisto. Le uscite previste e abituali sono già comprese nel margine.")
            }
            .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            .padding(.top, 8)
        }
        .font(.caption).tint(ForgiaPalette.margin)
    }
}

struct MarginEstimateBasis: View {
    let latestMovement: Date?

    var body: some View {
        DisclosureGroup("Su cosa si basa la stima") {
            VStack(alignment: .leading, spacing: 8) {
                Label("Saldi verificati", systemImage: "checkmark.circle")
                Label("Almeno 45 giorni di storico e spese distribuite su più mesi", systemImage: "calendar")
                if let latestMovement {
                    Text("Ultimo movimento: \(latestMovement, format: .dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "it_IT")))")
                }
                Text("Sono considerate le uscite registrate o programmate e la spesa abituale stimata fino alla prossima entrata. Gli imprevisti non registrati restano esclusi.")
            }.font(.caption).foregroundStyle(ForgiaPalette.mutedText).padding(.top, 8)
        }.font(.subheadline.weight(.medium)).tint(ForgiaPalette.margin)
    }
}

import SwiftUI
import FinanceCore

struct MonthlyForecastFundingSplitView: View {
    let currency: String
    let participants: [TransactionPerson]
    let shortfall: Decimal?
    @AppStorage private var enabled: Bool
    @AppStorage private var mode: String
    @AppStorage private var percentageText: String
    @AppStorage private var firstName: String
    @AppStorage private var secondName: String
    @FocusState private var editingPercentage: Bool

    init(contoID: UUID, currency: String, participants: [TransactionPerson], shortfall: Decimal?) {
        self.currency = currency
        self.participants = participants
        self.shortfall = shortfall
        let key = "formi.forecast.split.\(contoID.uuidString).\(currency)"
        let pairKey = participants.count == 2 ? participants.map(\.id).joined(separator: "|") : "manual"
        _enabled = AppStorage(wrappedValue: participants.count == 2, "\(key).enabled")
        _mode = AppStorage(wrappedValue: "equal", "\(key).\(pairKey).mode")
        _percentageText = AppStorage(wrappedValue: "50", "\(key).\(pairKey).percentage")
        _firstName = AppStorage(wrappedValue: "", "\(key).firstName")
        _secondName = AppStorage(wrappedValue: "", "\(key).secondName")
    }

    private var firstLabel: String {
        if participants.count == 2 { return personLabel(participants[0], position: 1) }
        return firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Tu") : firstName
    }
    private var secondLabel: String {
        if participants.count == 2 { return personLabel(participants[1], position: 2) }
        return secondName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Altra persona") : secondName
    }
    private func personLabel(_ person: TransactionPerson, position: Int) -> String {
        if person.id == TransactionPeople.current?.id { return String(localized: "Tu") }
        return person.name.isEmpty ? String(localized: "Persona \(position)") : person.name
    }

    var body: some View {
        if (shortfall ?? 0) > 0 || enabled {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Dividi quanto manca", isOn: $enabled)
                    .font(.headline).tint(ForgiaPalette.accent)
                    .accessibilityIdentifier("monthly-funding-split-enabled")
                if enabled {
                    if let shortfall {
                        LabeledContent("Totale da versare") {
                            Text(shortfall, format: .currency(code: currency)).fontWeight(.semibold)
                        }
                        if shortfall == 0 {
                            Text("Il conto copre già il necessario: al momento non servono altri versamenti.")
                                .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                        }
                        if participants.count != 2 {
                            HStack {
                                TextField("Tu", text: $firstName).accessibilityLabel("Prima persona")
                                TextField("Altra persona", text: $secondName).accessibilityLabel("Seconda persona")
                            }.textFieldStyle(.roundedBorder).frame(minHeight: 44)
                        }
                        Picker("Ripartizione", selection: $mode) {
                            Text("Metà ciascuno").tag("equal")
                            Text("Quote diverse").tag("custom")
                        }.pickerStyle(.segmented).accessibilityIdentifier("monthly-funding-split-mode")
                        if mode == "custom" {
                            HStack(spacing: 12) {
                                Text("Quota di \(firstLabel)").font(.subheadline)
                                Spacer(minLength: 8)
                                TextField("50", text: $percentageText)
                                    .multilineTextAlignment(.trailing).textFieldStyle(.plain)
                                    .font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
                                    .focused($editingPercentage).onSubmit { editingPercentage = false }
                                    #if os(iOS)
                                    .keyboardType(.decimalPad)
                                    #endif
                                    .accessibilityLabel("Percentuale della prima persona")
                                    .accessibilityIdentifier("monthly-funding-split-percentage")
                                Text("%")
                            }.padding(12).frame(minHeight: 48).cardInset()
                            if editingPercentage {
                                Button("Fine") { editingPercentage = false }
                                    .frame(minWidth: 44, minHeight: 44).frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                        let percentage = mode == "equal" ? Decimal(50) : MarginScenario.expense(from: percentageText)
                        if let percentage, let split = MonthlyFundingSplit(shortfall: shortfall, firstPercentage: percentage, currency: currency) {
                            share(name: firstLabel, percentage: split.firstPercentage, amount: split.firstAmount, id: "monthly-funding-first")
                            share(name: secondLabel, percentage: split.secondPercentage, amount: split.secondAmount, id: "monthly-funding-second")
                        } else {
                            Text("Inserisci una percentuale da 0 a 100. La seconda quota completa il totale.")
                                .font(.caption).foregroundStyle(ForgiaPalette.deficit)
                        }
                        Text("Le quote indicano quanto versare in aggiunta al saldo e ai movimenti già previsti. Comprendono la riserva scelta.")
                            .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                    } else {
                        Text("Completa i dati della copertura per calcolare le quote da versare.")
                            .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                    }
                }
            }.unifiedCard(tint: ForgiaPalette.balance)
        }
    }

    private func share(name: String, percentage: Decimal, amount: Decimal, id: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(name)
                Text(percentage / 100, format: .percent.precision(.fractionLength(0...2))).foregroundStyle(ForgiaPalette.mutedText)
                Spacer(minLength: 8)
                Text(amount, format: .currency(code: currency)).fontWeight(.semibold).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("\(name) · \(percentage / 100, format: .percent.precision(.fractionLength(0...2)))")
                Text(amount, format: .currency(code: currency)).fontWeight(.semibold).monospacedDigit()
            }
        }.frame(minHeight: 44).accessibilityElement(children: .combine).accessibilityIdentifier(id)
    }
}

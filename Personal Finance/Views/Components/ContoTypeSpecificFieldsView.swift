import SwiftUI
import FinanceCore

struct ContoTypeSpecificFieldsView: View {
    let selectedType: ContoType
    let currency: String

    @Binding var creditLimit: Decimal?
    @Binding var statementClosingDay: Int?
    @Binding var paymentDueDay: Int?
    @Binding var annualInterestRate: Decimal?
    @Binding var savingsGoal: Decimal?

    var body: some View {
        switch selectedType {
        case .credit:
            creditCardFields
        case .investment:
            investmentFields
        case .savings:
            savingsFields
        default:
            EmptyView()
        }
    }

    // MARK: - Credit Card Fields

    private var creditCardFields: some View {
        Section("Carta di Credito") {
            HStack {
                Text("Plafond Mensile")
                Spacer()
                TextField("0,00", value: $creditLimit, format: .currency(code: currency))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }

            Picker("Chiusura Estratto Conto", selection: closingDayBinding) {
                Text("Non impostato").tag(0)
                ForEach(1...28, id: \.self) { day in
                    Text("Giorno \(day)").tag(day)
                }
            }

            Picker("Giorno Addebito", selection: paymentDayBinding) {
                Text("Non impostato").tag(0)
                ForEach(1...28, id: \.self) { day in
                    Text("Giorno \(day)").tag(day)
                }
            }
        }
    }

    // MARK: - Investment Fields

    private var investmentFields: some View {
        Section("Investimenti") {
            HStack {
                Text("Tasso Annuo (%)")
                Spacer()
                TextField("0,00", value: $annualInterestRate, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    // MARK: - Savings Fields

    private var savingsFields: some View {
        Section("Obiettivo di Risparmio") {
            HStack {
                Text("Obiettivo")
                Spacer()
                TextField("0,00", value: $savingsGoal, format: .currency(code: currency))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    // MARK: - Helpers

    private var closingDayBinding: Binding<Int> {
        Binding(
            get: { statementClosingDay ?? 0 },
            set: { statementClosingDay = $0 == 0 ? nil : $0 }
        )
    }

    private var paymentDayBinding: Binding<Int> {
        Binding(
            get: { paymentDueDay ?? 0 },
            set: { paymentDueDay = $0 == 0 ? nil : $0 }
        )
    }
}

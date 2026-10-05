import SwiftUI
import FinanceCore

struct AmountCalculatorView: View {
    let initialAmount: Decimal
    let currency: String
    let onApply: (Decimal) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var expression = ""

    private var result: Decimal? {
        guard var value = try? AmountCalculator.evaluate(expression) else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &value, formatter.maximumFractionDigits, .plain)
        return rounded
    }
    private let keys = ["7", "8", "9", "÷", "4", "5", "6", "×", "1", "2", "3", "−", "0", ",", "(", "+", ")", "C", "⌫"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    TextField("12,50 + 8", text: $expression)
                        .font(.title2.monospacedDigit())
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Calcolo")
                    if let result {
                        Text(result, format: .currency(code: currency))
                            .font(.largeTitle.monospacedDigit())
                            .accessibilityIdentifier("calculator-result")
                        if result <= 0 {
                            Text("L'importo da usare deve essere maggiore di zero.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else if !expression.isEmpty {
                        Text(errorMessage).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(keys, id: \.self) { key in
                            Button { press(key) } label: {
                                Text(key).font(.title2).frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(key == "C" ? "Azzera calcolo" : key == "⌫" ? "Cancella ultima cifra" : key)
                        }
                    }
                    Button("Usa importo") {
                        if let result, result > 0 { onApply(result); dismiss() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(result == nil || (result ?? 0) <= 0)
                    Text("Il risultato viene arrotondato alla precisione della valuta e riportato nel modulo. Il movimento sarà registrato solo quando premi Salva.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }
            .navigationTitle("Calcolatrice")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
            .onAppear {
                if expression.isEmpty, initialAmount > 0 {
                    expression = NSDecimalNumber(decimal: initialAmount).stringValue.replacingOccurrences(of: ".", with: ",")
                }
            }
        }
        .frame(minWidth: 300, minHeight: 480)
    }

    private var errorMessage: String {
        do { _ = try AmountCalculator.evaluate(expression); return "" }
        catch AmountCalculator.Failure.divisionByZero { return "Non è possibile dividere per zero." }
        catch AmountCalculator.Failure.outOfRange { return "Il calcolo supera i limiti supportati." }
        catch { return "Completa il calcolo per vedere il risultato." }
    }

    private func press(_ key: String) {
        if key == "C" { expression = "" }
        else if key == "⌫" { if !expression.isEmpty { expression.removeLast() } }
        else if expression.count < 128 { expression += key }
    }
}

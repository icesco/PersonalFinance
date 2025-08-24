import SwiftUI
import SwiftData
import FinanceCore

struct CreateContoView: View {
    let account: Account
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationRouter.self) private var navigationRouter
    @State private var contoName = ""
    @State private var selectedType: ContoType = .checking
    @State private var initialBalance: Decimal = 0
    @State private var description = ""
    @State private var selectedColor = "#007AFF"
    
    private let colors = [
        "#007AFF", "#FF3B30", "#FF9500", "#FFCC00",
        "#34C759", "#5AC8FA", "#AF52DE", "#FF2D92",
        "#A2845E", "#8E8E93"
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Dettagli Conto") {
                    TextField("Nome Conto", text: $contoName)
                    
                    Picker("Tipo", selection: $selectedType) {
                        ForEach(ContoType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                    
                    HStack {
                        Text("Saldo Iniziale")
                        Spacer()
                        TextField("0,00", value: $initialBalance, format: .currency(code: account.currency ?? "EUR"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section("Personalizzazione") {
                    HStack {
                        Text("Colore")
                        Spacer()
                        HStack {
                            ForEach(colors, id: \.self) { color in
                                Circle()
                                    .fill(Color(hex: color) ?? .blue)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if selectedColor == color {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.white)
                                                .font(.caption.weight(.bold))
                                        }
                                    }
                                    .onTapGesture {
                                        selectedColor = color
                                    }
                            }
                        }
                    }
                    
                    TextField("Descrizione (opzionale)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }
                
                Section {
                    Text("Il conto rappresenta un singolo strumento finanziario (conto corrente, carta di credito, conto risparmio, ecc.) all'interno del tuo account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Nuovo Conto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        createConto()
                    }
                    .disabled(contoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func createConto() {
        let conto = Conto(
            name: contoName.trimmingCharacters(in: .whitespacesAndNewlines),
            type: selectedType,
            initialBalance: initialBalance,
            contoDescription: description.isEmpty ? nil : description,
            color: selectedColor
        )
        
        conto.account = account
        modelContext.insert(conto)
        
        try? modelContext.save()
        dismiss()
    }
}

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct CreateContoView_Previews: PreviewProvider {
    static var previews: some View {
        let container = try! FinanceCoreModule.createModelContainer(inMemory: true)
        let account = Account(name: "Test Account")
        container.mainContext.insert(account)
        
        return CreateContoView(account: account)
            .modelContainer(container)
    }
}
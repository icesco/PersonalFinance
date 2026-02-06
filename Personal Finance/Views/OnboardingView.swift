//
//  OnboardingView.swift
//  Personal Finance
//
//  Created by Claude on 01/02/26.
//

import SwiftUI
import SwiftData
import FinanceCore

// MARK: - Onboarding Step

private enum OnboardingStep {
    case welcome
    case libroSetup
    case contiSetup
}

// MARK: - Conto Setup Data

private struct ContoSetupData: Identifiable {
    let id = UUID()
    var name: String
    var type: ContoType
    var initialBalance: Decimal
    var creditLimit: Decimal?
    var statementClosingDay: Int?
    var paymentDueDay: Int?
    var annualInterestRate: Decimal?
    var savingsGoal: Decimal?
}

// MARK: - OnboardingView

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState

    @State private var step: OnboardingStep = .welcome
    @State private var libroName = ""
    @State private var libroCurrency = "EUR"
    @State private var contiToCreate: [ContoSetupData] = []
    @State private var showingAddConto = false
    @State private var isCreatingDemo = false

    private let currencies = ["EUR", "USD", "GBP", "CHF"]

    var body: some View {
        Group {
            switch step {
            case .welcome:
                welcomePage
            case .libroSetup:
                libroSetupPage
            case .contiSetup:
                contiSetupPage
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    // MARK: - Welcome Page

    private var welcomePage: some View {
        VStack(spacing: 30) {
            Spacer()

            Image("logo-forgia")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 24))

            Text("Benvenuto in Forgia")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("Forgia il tuo futuro finanziario. Traccia entrate, spese e monitora i tuoi budget con consapevolezza.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    withAnimation {
                        step = .libroSetup
                    }
                } label: {
                    Label("Personalizza il tuo libro", systemImage: "slider.horizontal.3")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    createDemoData()
                } label: {
                    if isCreatingDemo {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Usa dati demo", systemImage: "sparkles")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isCreatingDemo)
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Libro Setup Page

    private var libroSetupPage: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Nome del libro", text: $libroName)
                } header: {
                    Text("Nome")
                } footer: {
                    Text("Il libro contabile raggruppa i tuoi account finanziari.")
                }

                Section("Valuta") {
                    Picker("Valuta", selection: $libroCurrency) {
                        ForEach(currencies, id: \.self) { currency in
                            Text(currencyLabel(for: currency)).tag(currency)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Crea il tuo Libro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Indietro") {
                        withAnimation {
                            step = .welcome
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Avanti") {
                        withAnimation {
                            step = .contiSetup
                        }
                    }
                    .disabled(libroName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Conti Setup Page

    private var contiSetupPage: some View {
        NavigationView {
            List {
                if contiToCreate.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Nessun account",
                            systemImage: "creditcard",
                            description: Text("Aggiungi almeno un account per continuare.")
                        )
                    }
                } else {
                    Section("Account da creare") {
                        ForEach(contiToCreate) { conto in
                            HStack {
                                Image(systemName: conto.type.icon)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 30)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(conto.name)
                                        .font(.body)
                                    Text(conto.type.displayName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text(conto.initialBalance, format: .currency(code: libroCurrency))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onDelete { indexSet in
                            contiToCreate.remove(atOffsets: indexSet)
                        }
                    }
                }

                Section {
                    Button {
                        showingAddConto = true
                    } label: {
                        Label("Aggiungi Account", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("Aggiungi Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Indietro") {
                        withAnimation {
                            step = .libroSetup
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Completa") {
                        completeCustomSetup()
                    }
                    .fontWeight(.semibold)
                    .disabled(contiToCreate.isEmpty)
                }
            }
            .sheet(isPresented: $showingAddConto) {
                AddContoOnboardingSheet(currency: libroCurrency) { newConto in
                    contiToCreate.append(newConto)
                }
            }
        }
    }

    // MARK: - Actions

    private func createDemoData() {
        isCreatingDemo = true
        let service = DemoDataService(modelContext: modelContext)
        Task {
            do {
                try await service.generateDemoData()
                // Select the created demo account
                let descriptor = FetchDescriptor<Account>()
                if let accounts = try? modelContext.fetch(descriptor),
                   let demoAccount = accounts.first {
                    appState.selectAccount(demoAccount)
                }
                appState.completeOnboarding()
            } catch {
                print("Error creating demo data: \(error)")
                isCreatingDemo = false
            }
        }
    }

    private func completeCustomSetup() {
        let account = Account(name: libroName.trimmingCharacters(in: .whitespaces), currency: libroCurrency)
        modelContext.insert(account)

        // Create default categories
        for (name, color, icon) in Category.defaultCategories {
            let category = Category(name: name, color: color, icon: icon)
            category.account = account
            modelContext.insert(category)
        }

        // Create conti
        for contoData in contiToCreate {
            let conto = Conto(
                name: contoData.name,
                type: contoData.type,
                initialBalance: contoData.initialBalance,
                creditLimit: contoData.creditLimit,
                statementClosingDay: contoData.statementClosingDay,
                paymentDueDay: contoData.paymentDueDay,
                annualInterestRate: contoData.annualInterestRate,
                savingsGoal: contoData.savingsGoal
            )
            conto.account = account
            modelContext.insert(conto)
        }

        do {
            try modelContext.save()
            appState.selectAccount(account)
            appState.completeOnboarding()
        } catch {
            print("Error completing custom setup: \(error)")
        }
    }

    private func currencyLabel(for code: String) -> String {
        switch code {
        case "EUR": return "EUR - Euro"
        case "USD": return "USD - Dollaro"
        case "GBP": return "GBP - Sterlina"
        case "CHF": return "CHF - Franco Svizzero"
        default: return code
        }
    }
}

// MARK: - Add Conto Sheet

private struct AddContoOnboardingSheet: View {
    let currency: String
    let onAdd: (ContoSetupData) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedType: ContoType = .checking
    @State private var initialBalance: Decimal = 0
    @State private var creditLimit: Decimal?
    @State private var statementClosingDay: Int?
    @State private var paymentDueDay: Int?
    @State private var annualInterestRate: Decimal?
    @State private var savingsGoal: Decimal?

    var body: some View {
        NavigationView {
            Form {
                Section("Informazioni") {
                    TextField("Nome account", text: $name)

                    Picker("Tipo", selection: $selectedType) {
                        ForEach(ContoType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }

                    HStack {
                        Text("Saldo Iniziale")
                        Spacer()
                        TextField("0,00", value: $initialBalance, format: .currency(code: currency))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                ContoTypeSpecificFieldsView(
                    selectedType: selectedType,
                    currency: currency,
                    creditLimit: $creditLimit,
                    statementClosingDay: $statementClosingDay,
                    paymentDueDay: $paymentDueDay,
                    annualInterestRate: $annualInterestRate,
                    savingsGoal: $savingsGoal
                )
            }
            .navigationTitle("Nuovo Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aggiungi") {
                        let data = ContoSetupData(
                            name: name.trimmingCharacters(in: .whitespaces),
                            type: selectedType,
                            initialBalance: initialBalance,
                            creditLimit: creditLimit,
                            statementClosingDay: statementClosingDay,
                            paymentDueDay: paymentDueDay,
                            annualInterestRate: annualInterestRate,
                            savingsGoal: savingsGoal
                        )
                        onAdd(data)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: selectedType) { _, _ in
                creditLimit = nil
                statementClosingDay = nil
                paymentDueDay = nil
                annualInterestRate = nil
                savingsGoal = nil
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppStateManager())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}

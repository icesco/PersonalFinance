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
    @State private var showingSetupError = false

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
        .alert("Impossibile completare la configurazione", isPresented: $showingSetupError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("I dati non sono stati salvati. Le informazioni inserite sono ancora disponibili: riprova.")
        }
    }

    // MARK: - Welcome Page

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image("logo-forgia")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text("Forgia")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
            }
            .padding(.top, 28)

            Spacer(minLength: 36)

            Text("I tuoi soldi,\npiù chiari.")
                .font(.system(size: 48, weight: .semibold, design: .serif))
                .tracking(-1.5)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)

            Text("Scopri dove spendi, tieni d'occhio i prossimi impegni e scegli con più consapevolezza.")
                .font(.title3)
                .foregroundStyle(ForgiaPalette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            HStack(spacing: 9) {
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(ForgiaPalette.accent)
                Text("Un quadro semplice, costruito sui tuoi movimenti.")
                    .font(.subheadline)
                    .foregroundStyle(ForgiaPalette.mutedText)
            }
            .padding(.top, 28)

            Spacer(minLength: 36)

            VStack(spacing: 14) {
                Button {
                    withAnimation {
                        step = .libroSetup
                    }
                } label: {
                    HStack {
                        Text("Inizia con i tuoi conti")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ForgiaPalette.onAccent)
                        .padding(.horizontal, 20)
                        .frame(height: 54)
                        .frame(maxWidth: .infinity)
                        .background(ForgiaPalette.accent, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                Button {
                    createDemoData()
                } label: {
                    if isCreatingDemo {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Esplora con dati demo")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ForgiaPalette.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isCreatingDemo)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedBackground()
    }

    // MARK: - Libro Setup Page

    private var libroSetupPage: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome del libro", text: $libroName)
                } header: {
                    Text("Nome")
                } footer: {
                    Text("Un libro raggruppa i conti che vuoi seguire insieme.")
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
            .scrollContentBackground(.hidden)
            .themedBackground()
            .navigationTitle("Crea il tuo libro")
            .toolbarTitleDisplayMode(.inline)
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
        NavigationStack {
            List {
                if contiToCreate.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Nessun conto",
                            systemImage: "creditcard",
                            description: Text("Aggiungi almeno un conto per continuare.")
                        )
                    }
                } else {
                    Section("Conti da aggiungere") {
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
                        Label("Aggiungi conto", systemImage: "plus.circle.fill")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .themedBackground()
            .navigationTitle("Aggiungi i tuoi conti")
            .toolbarTitleDisplayMode(.inline)
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
        let conti = contiToCreate.map { data in
            Conto(name: data.name, type: data.type, initialBalance: data.initialBalance,
                  creditLimit: data.creditLimit, statementClosingDay: data.statementClosingDay,
                  paymentDueDay: data.paymentDueDay, annualInterestRate: data.annualInterestRate,
                  savingsGoal: data.savingsGoal)
        }
        do {
            let account = try AccountCreation(context: modelContext).create(
                name: libroName, currency: libroCurrency, conti: conti
            )
            appState.selectAccount(account)
            appState.completeOnboarding()
        } catch {
            showingSetupError = true
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
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
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
            .toolbarTitleDisplayMode(.inline)
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

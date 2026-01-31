//
//  MainTabView.swift
//  Personal Finance
//
//  Tab principale con navigazione semplificata
//

import SwiftUI
import SwiftData
import FinanceCore

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                // iPad / Mac: NavigationSplitView
                iPadLayout
            } else {
                // iPhone: TabView standard
                iPhoneLayout
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.showingQuickTransaction },
            set: { _ in appState.dismissQuickTransaction() }
        )) {
            QuickTransactionModal()
        }
        .sheet(isPresented: Binding(
            get: { appState.showingAccountSelection },
            set: { _ in appState.dismissAccountSelection() }
        )) {
            AccountSelectionModal()
        }
    }

    // MARK: - iPhone Layout

    private var iPhoneLayout: some View {
        ZStack {
            TabView(selection: Binding(
                get: { appState.selectedTab },
                set: { appState.selectTab($0) }
            )) {
                DashboardView()
                    .tabItem {
                        Label("Dashboard", systemImage: appState.selectedTab == .dashboard ? "house.fill" : "house")
                    }
                    .tag(AppTab.dashboard)

                TransactionListView()
                    .tabItem {
                        Label("Transazioni", systemImage: appState.selectedTab == .transactions ? "list.bullet.rectangle.fill" : "list.bullet.rectangle")
                    }
                    .tag(AppTab.transactions)

                SettingsView()
                    .tabItem {
                        Label("Impostazioni", systemImage: appState.selectedTab == .settings ? "gearshape.fill" : "gearshape")
                    }
                    .tag(AppTab.settings)
            }

            // Floating Action Button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    FloatingActionButton {
                        appState.presentQuickTransaction()
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 90)
                }
            }
        }
    }

    // MARK: - iPad Layout

    private var iPadLayout: some View {
        NavigationSplitView {
            // Sidebar
            List(selection: Binding(
                get: { appState.selectedTab },
                set: { if let tab = $0 { appState.selectTab(tab) } }
            )) {
                Section("Menu") {
                    Label("Dashboard", systemImage: "house")
                        .tag(AppTab.dashboard)

                    Label("Transazioni", systemImage: "list.bullet.rectangle")
                        .tag(AppTab.transactions)

                    Label("Impostazioni", systemImage: "gearshape")
                        .tag(AppTab.settings)
                }
            }
            .navigationTitle("Finance")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appState.presentQuickTransaction()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
        } detail: {
            // Content based on selected tab
            switch appState.selectedTab {
            case .dashboard:
                DashboardView()
            case .transactions:
                TransactionListView()
            case .settings:
                SettingsView()
            }
        }
    }
}

// MARK: - Floating Action Button

struct FloatingActionButton: View {
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Quick Transaction Modal

struct QuickTransactionModal: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState

    @State private var selectedConto: Conto?
    @State private var selectedCategory: FinanceCategory?
    @State private var amount: String = ""
    @State private var description: String = ""
    @State private var transactionType: TransactionType = .expense
    @State private var selectedDate = Date()
    @State private var isRecurring = false
    @State private var recurrenceFrequency: RecurrenceFrequency = .monthly

    private var availableConti: [Conto] {
        appState.activeConti(for: appState.selectedAccount)
    }

    private var availableCategories: [FinanceCategory] {
        appState.selectedAccount?.categories?.filter { $0.isActive == true } ?? []
    }

    private var isFormValid: Bool {
        guard let amountValue = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")) else {
            return false
        }
        return selectedConto != nil && selectedCategory != nil && amountValue > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                // Tipo transazione
                Section {
                    Picker("Tipo", selection: $transactionType) {
                        Text("Spesa").tag(TransactionType.expense)
                        Text("Entrata").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 8)
                }

                // Importo (in evidenza)
                Section {
                    HStack {
                        Text("€")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)

                        TextField("0,00", text: $amount)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.leading)
                    }
                    .listRowBackground(Color.clear)
                }

                // Dettagli
                Section("Dettagli") {
                    // Conto
                    Picker("Conto", selection: $selectedConto) {
                        Text("Seleziona").tag(nil as Conto?)
                        ForEach(availableConti, id: \.id) { conto in
                            HStack {
                                Image(systemName: conto.type?.icon ?? "creditcard")
                                Text(conto.name ?? "Conto")
                            }
                            .tag(conto as Conto?)
                        }
                    }

                    // Categoria
                    Picker("Categoria", selection: $selectedCategory) {
                        Text("Seleziona").tag(nil as FinanceCategory?)
                        ForEach(availableCategories, id: \.id) { category in
                            HStack {
                                Image(systemName: category.icon ?? "tag")
                                    .foregroundStyle(Color(hex: category.color ?? "#007AFF"))
                                Text(category.name ?? "Categoria")
                            }
                            .tag(category as FinanceCategory?)
                        }
                    }

                    // Descrizione
                    TextField("Descrizione (opzionale)", text: $description)

                    // Data
                    DatePicker("Data", selection: $selectedDate, displayedComponents: .date)
                }

                // Ricorrenza
                Section("Ricorrenza") {
                    Toggle("Transazione ricorrente", isOn: $isRecurring)

                    if isRecurring {
                        Picker("Frequenza", selection: $recurrenceFrequency) {
                            ForEach(RecurrenceFrequency.allCases, id: \.self) { frequency in
                                Text(frequency.displayName).tag(frequency)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Nuova Transazione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { saveTransaction() }
                        .fontWeight(.semibold)
                        .disabled(!isFormValid)
                }
            }
            .onAppear {
                transactionType = appState.quickTransactionType
                if selectedConto == nil, let firstConto = availableConti.first {
                    selectedConto = firstConto
                }
            }
        }
    }

    private func saveTransaction() {
        guard let amountDecimal = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")),
              let conto = selectedConto,
              let category = selectedCategory else { return }

        let transaction = FinanceTransaction(
            amount: amountDecimal,
            type: transactionType,
            date: selectedDate,
            transactionDescription: description.isEmpty ? nil : description,
            isRecurring: isRecurring,
            recurrenceFrequency: isRecurring ? recurrenceFrequency : nil
        )

        transaction.category = category

        switch transactionType {
        case .expense:
            transaction.fromConto = conto
        case .income:
            transaction.toConto = conto
        case .transfer:
            break
        }

        modelContext.insert(transaction)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error saving transaction: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    MainTabView()
        .environment(AppStateManager())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}

//
//  CreateBudgetView.swift
//  Personal Finance
//
//  Creazione e modifica di un budget: limite, periodo, categorie e soglia di avviso
//

import SwiftUI
import FinanceCore

struct CreateBudgetView: View {
    let account: Account
    let budget: FinanceBudget?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var budgetName: String
    @State private var budgetAmount: String
    @State private var selectedPeriod: BudgetPeriod
    @State private var alertThreshold: Double
    @State private var selectedCategories: Set<FinanceCategory>
    @State private var showingSubcategories = false
    @State private var showingSaveError = false
    @FocusState private var amountFocused: Bool

    init(account: Account, budget: FinanceBudget? = nil) {
        self.account = account
        self.budget = budget
        _budgetName = State(initialValue: budget?.name ?? "")
        _budgetAmount = State(initialValue: budget?.amount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
        _selectedPeriod = State(initialValue: budget?.period ?? .monthly)
        _alertThreshold = State(initialValue: budget?.alertThreshold ?? 0.8)
        _selectedCategories = State(initialValue: Set(budget?.categories ?? []))
    }

    private var currency: String { account.currency ?? "EUR" }
    private var parsedAmount: Decimal? { BalanceInput.parse(budgetAmount, currency: currency) }

    private var hierarchy: CategoryHierarchy {
        CategoryHierarchy(categories: account.categories ?? [], kind: .expense)
    }

    /// Macro categories, plus archived ones this budget still uses so they can be removed.
    private var mainCategories: [FinanceCategory] {
        hierarchy.roots + FinanceCategory.displayOrdered(Array(selectedCategories.filter { $0.isActive != true }))
    }

    private var hasSubcategories: Bool {
        hierarchy.roots.contains { !hierarchy.children(of: $0).isEmpty }
    }

    private var showsSubcategories: Bool {
        showingSubcategories || selectedCategories.contains { $0.isActive == true && $0.parentCategoryId != nil }
    }

    /// With a single category, its name is a sensible default the user can override.
    private var suggestedName: String? {
        guard selectedCategories.count == 1 else { return nil }
        return selectedCategories.first?.name
    }

    private var effectiveName: String {
        let typed = budgetName.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? (suggestedName ?? "") : typed
    }

    private var isFormValid: Bool {
        !effectiveName.isEmpty &&
        (parsedAmount ?? 0) > 0 &&
        !selectedCategories.isEmpty
    }

    /// What still blocks saving, in the order the form asks for it.
    private var missingStep: String? {
        if (parsedAmount ?? 0) <= 0 { return "Inserisci il limite di spesa" }
        if selectedCategories.isEmpty { return "Scegli almeno una categoria" }
        if effectiveName.isEmpty { return "Dai un nome al budget" }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    FormCard(title: "Nome") {
                        FormRow(icon: "character.cursor.ibeam", tint: ForgiaPalette.sageSurface) {
                            TextField(suggestedName ?? "Es. Spesa di casa", text: $budgetName)
                                .font(.title3.weight(.semibold))
                                .submitLabel(.done)
                                .accessibilityLabel("Nome Budget")
                        }
                    }
                    limitCard
                    categoriesSection
                    thresholdCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .background(ForgiaPalette.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaBar(edge: .bottom, spacing: 0) { saveBar }
            .navigationTitle(budget == nil ? "Nuovo budget" : "Modifica budget")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
            .alert("Impossibile salvare", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: { Text("Il budget non è stato salvato. Controlla i dati e riprova.") }
        }
    }

    // MARK: - Limit

    private var limitCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LIMITE DI SPESA")
                .font(.caption2.weight(.semibold)).tracking(1.2)
                .foregroundStyle(ForgiaPalette.mutedText)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(currency)
                    .font(.headline)
                    .foregroundStyle(ForgiaPalette.accent)
                TextField("0,00", text: $budgetAmount)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .focused($amountFocused)
                    .accessibilityLabel("Importo")
                    .accessibilityIdentifier("budget-amount")
            }
            .font(.system(size: 45, weight: .semibold, design: .rounded))
            .minimumScaleFactor(0.7)

            if !budgetAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, (parsedAmount ?? 0) <= 0 {
                Text("Inserisci un importo positivo valido per questa valuta, senza separatori delle migliaia.")
                    .font(.caption).foregroundStyle(.red)
                    .accessibilityIdentifier("budget-amount-invalid")
            }

            periodPicker

            if let amount = parsedAmount, amount > 0 {
                Label("Circa \((amount / Decimal(selectedPeriod.days)).formatted(.currency(code: currency))) al giorno",
                      systemImage: "calendar.day.timeline.left")
                    .font(.subheadline)
                    .foregroundStyle(ForgiaPalette.mutedText)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: selectedPeriod)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [ForgiaPalette.sageSurface, ForgiaPalette.sageSurface.mix(with: ForgiaPalette.surface, by: 0.4)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 25, style: .continuous)
        )
    }

    private var periodPicker: some View {
        HStack(spacing: 6) {
            ForEach(BudgetPeriod.allCases, id: \.self) { period in
                let selected = period == selectedPeriod
                Button {
                    amountFocused = false
                    withAnimation(.snappy) { selectedPeriod = period }
                } label: {
                    Text(period.shortName)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .foregroundStyle(selected ? ForgiaPalette.onAccent : ForgiaPalette.accent)
                        .background(selected ? ForgiaPalette.accent : ForgiaPalette.surface.opacity(0.8), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Periodo")
    }

    // MARK: - Categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Categorie")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ForgiaPalette.mutedText)
                Spacer()
                if !selectedCategories.isEmpty {
                    Text(selectedCategories.count == 1 ? "1 scelta" : "\(selectedCategories.count) scelte")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ForgiaPalette.accent)
                        .contentTransition(.numericText(value: Double(selectedCategories.count)))
                }
            }
            .padding(.horizontal, 4)

            if mainCategories.isEmpty {
                Text("Nessuna categoria di spesa disponibile")
                    .font(.subheadline)
                    .foregroundStyle(ForgiaPalette.mutedText)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            } else {
                categoryGrid(mainCategories)

                if hasSubcategories {
                    Button {
                        withAnimation(.snappy) { showingSubcategories.toggle() }
                    } label: {
                        Label(showsSubcategories ? "Nascondi sottocategorie" : "Scegli sottocategorie",
                              systemImage: showsSubcategories ? "chevron.up" : "chevron.down")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .tint(ForgiaPalette.accent)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                    .disabled(showsSubcategories && !showingSubcategories)

                    if showsSubcategories {
                        Text("Una categoria principale include già tutte le sue sottocategorie.")
                            .font(.caption)
                            .foregroundStyle(ForgiaPalette.mutedText)
                            .padding(.horizontal, 4)
                        ForEach(hierarchy.roots.filter { !hierarchy.children(of: $0).isEmpty }, id: \.id) { root in
                            Label("Sottocategorie di \(root.name ?? "Categoria")", systemImage: root.icon ?? "tag")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(root.tint)
                                .padding(.horizontal, 4)
                                .padding(.top, 6)
                            categoryGrid(hierarchy.children(of: root), includedBy: root)
                        }
                    }
                }
            }
        }
    }

    private func categoryGrid(_ categories: [FinanceCategory], includedBy parent: FinanceCategory? = nil) -> some View {
        let included = parent.map(selectedCategories.contains) ?? false
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(categories, id: \.id) { category in
                BudgetCategoryTile(category: category, isSelected: included || selectedCategories.contains(category)) {
                    amountFocused = false
                    withAnimation(.snappy) {
                        if selectedCategories.contains(category) {
                            selectedCategories.remove(category)
                        } else {
                            selectedCategories.insert(category)
                            // The macro category already covers its subcategories.
                            selectedCategories.subtract(hierarchy.children(of: category))
                        }
                    }
                }
                .disabled(included)
                .opacity(included ? 0.6 : 1)
            }
        }
    }

    // MARK: - Threshold

    private var thresholdCard: some View {
        FormCard(title: "Avviso") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    FormRowIcon(name: "bell.badge", tint: ForgiaPalette.apricotSurface)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Avvisami al \(Int(alertThreshold * 100))%")
                            .font(.body)
                            .contentTransition(.numericText(value: alertThreshold))
                        if let amount = parsedAmount, amount > 0 {
                            Text("Quando arrivi a \((amount * Decimal(alertThreshold)).formatted(.currency(code: currency)))")
                                .font(.caption)
                                .foregroundStyle(ForgiaPalette.mutedText)
                        }
                    }
                    Spacer()
                }
                Slider(value: $alertThreshold.animation(.snappy), in: 0.5...1.0, step: 0.05)
                    .tint(ForgiaPalette.accent)
                    .accessibilityLabel("Soglia di avviso")
            }
            .padding(16)
        }
    }

    // MARK: - Save

    private var saveBar: some View {
        VStack(spacing: 6) {
            if let missingStep {
                Text(missingStep)
                    .font(.caption)
                    .foregroundStyle(ForgiaPalette.mutedText)
            }
            Button(action: saveBudget) {
                Text(budget == nil ? "Crea budget" : "Salva modifiche")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(isFormValid ? ForgiaPalette.accent : ForgiaPalette.border,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(isFormValid ? ForgiaPalette.onAccent : ForgiaPalette.mutedText)
            }
            .disabled(!isFormValid)
            .accessibilityIdentifier("budget-save")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func saveBudget() {
        guard isFormValid else { return }
        do {
            try BudgetEdits(context: modelContext).apply(
                to: budget, account: account, name: effectiveName, amountText: budgetAmount,
                period: selectedPeriod, threshold: alertThreshold,
                categories: selectedCategories.sorted { $0.id.uuidString < $1.id.uuidString }
            )
            dismiss()
        } catch {
            showingSaveError = true
        }
    }
}

/// A selectable category: tinted with the category colour once chosen.
private struct BudgetCategoryTile: View {
    let category: FinanceCategory
    let isSelected: Bool
    let onToggle: () -> Void

    private var color: Color { category.tint }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: category.icon?.isEmpty == false ? category.icon! : "tag")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : color)
                    .frame(width: 34, height: 34)
                    .background(isSelected ? color : color.opacity(0.14), in: Circle())
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(ForgiaPalette.onAccent, ForgiaPalette.accent)
                                .background(ForgiaPalette.surface, in: Circle())
                                .offset(x: 5, y: -5)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                Text(category.name ?? "Categoria")
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 58)
            .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? ForgiaPalette.accent : ForgiaPalette.border.opacity(0.6),
                                  lineWidth: isSelected ? 1.5 : 0.7)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.name ?? "Categoria")
        .accessibilityValue(isSelected ? "Selezionata" : "Non selezionata")
        .accessibilityIdentifier("budget-category-\(category.name ?? "")")
    }
}

private extension BudgetPeriod {
    /// Fits four capsules side by side; the full name stays in the budget list.
    var shortName: String {
        switch self {
        case .weekly: "Settimana"
        case .monthly: "Mese"
        case .quarterly: "Trimestre"
        case .yearly: "Anno"
        }
    }
}

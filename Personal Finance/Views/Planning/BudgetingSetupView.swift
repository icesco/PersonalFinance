import SwiftUI
import FinanceCore

struct BudgetingSetupView: View {
    let account: Account
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    @State private var plan: BudgetingPlan
    @State private var incomeText: String
    @State private var step: Int
    @State private var archiveOverlapping = false
    @State private var showingGuides = false
    @State private var saveError = false

    init(account: Account, startsManual: Bool = false) {
        self.account = account
        var plan = account.budgetingPlan ?? BudgetingPlan()
        if startsManual { plan.method = .manual }
        _plan = State(initialValue: plan)
        _incomeText = State(initialValue: plan.monthlyIncome > 0 ? NSDecimalNumber(decimal: plan.monthlyIncome).stringValue : "")
        _step = State(initialValue: startsManual ? 3 : 0)
    }

    private var categories: [FinanceCategory] {
        (account.categories ?? []).filter { $0.isActive == true && $0.fits(.expense) }
            .sorted { $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending }
    }
    private var income: Decimal? { BalanceInput.parse(incomeText, currency: account.currency ?? "EUR") }
    private var preview: BudgetingPlan {
        var result = plan; result.monthlyIncome = income ?? 0; return result
    }
    private var canContinue: Bool {
        switch step {
        case 1: return preview.isValid
        case 2: return !categories.isEmpty && categories.allSatisfy { plan.group(for: $0) != nil }
        default: return true
        }
    }
    private var overlapping: [FinanceBudget] {
        guard plan.method != .manual else { return [] }
        let ids = Set((account.categories ?? []).filter { $0.fits(.expense) && plan.group(for: $0) != nil }.map(\.id))
        return (account.budgets ?? []).filter {
            $0.isActive == true && $0.planningGroupRaw == nil && !$0.coveredCategoryIDs.isDisjoint(with: ids)
        }.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(stepTitle).font(.system(.title, design: .serif, weight: .semibold))
                    switch step {
                    case 0: BudgetingMethodSelection(method: $plan.method)
                    case 1: BudgetingIncomeStep(plan: $plan, incomeText: $incomeText, currency: account.currency ?? "EUR")
                    case 2: BudgetingCategoryStep(plan: $plan, categories: categories)
                    case 3: BudgetingSavingsStep(plan: $plan, account: account)
                    default:
                        BudgetingPreviewStep(plan: preview, account: account, overlapping: overlapping,
                                             archiveOverlapping: $archiveOverlapping)
                    }
                    Button { showingGuides = true } label: { Label("Come funziona e consigli", systemImage: "info.circle") }
                }
                .padding(20)
            }
            .navigationTitle("Piano di risparmio")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 16) {
                    if step > 0 {
                        Button("Indietro") { step = step == 3 && plan.method == .manual ? 0 : step - 1 }
                            .buttonStyle(.bordered)
                    }
                    Spacer()
                    Button(step == 4 ? "Applica il piano" : "Continua") {
                        if step == 4 { save() }
                        else { step = step == 0 && plan.method == .manual ? 3 : step + 1 }
                    }
                    .buttonStyle(.borderedProminent).tint(ForgiaPalette.accent)
                    .disabled(!canContinue).accessibilityIdentifier("budgeting-continue")
                }
                .padding().background(.regularMaterial)
            }
            .financePresentation(isPresented: $showingGuides, title: "Come funziona", width: 680) { SavingsExplanationView(plan: preview.isValid ? preview : nil, currency: account.currency ?? "EUR") }
            .alert("Piano non salvato", isPresented: $saveError) { Button("OK") { } } message: {
                Text("Controlla entrate, categorie e conti selezionati, poi riprova. Le modifiche al piano non sono state applicate.")
            }
        }
    }

    private var stepTitle: LocalizedStringResource {
        switch step {
        case 0: "Come vuoi organizzarti?"
        case 1: "Da quali entrate partiamo?"
        case 2: "Necessità o desideri?"
        case 3: "Come misuriamo gli accantonamenti?"
        default: "Il tuo piano, prima di applicarlo"
        }
    }
    private func save() {
        do {
            try BudgetingPlanEdits(context: modelContext).apply(preview, to: account, archiveOverlapping: archiveOverlapping)
            appState.triggerDataRefresh(); dismiss()
        } catch { saveError = true }
    }
}

private struct BudgetingMethodSelection: View {
    @Binding var method: BudgetingMethod
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(BudgetingMethod.allCases, id: \.self) { choice in
                Button {
                    method = choice
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: method == choice ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(ForgiaPalette.accent)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(choice.title).font(.headline)
                            Text(choice.explanation).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding().unifiedCard()
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(method == choice ? .isSelected : [])
            }
        }
    }
}

private struct BudgetingIncomeStep: View {
    @Binding var plan: BudgetingPlan
    @Binding var incomeText: String
    let currency: String
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Inserisci le entrate nette mensili su cui vuoi basare il piano. Sono un riferimento scelto da te, distinto dalle entrate già registrate.")
                .foregroundStyle(.secondary)
            TextField("Entrate mensili", text: $incomeText).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("budgeting-income")
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Text(currency).font(.caption).foregroundStyle(.secondary)
            if plan.method == .custom {
                Stepper("Necessità: \(plan.needsPercent)%", value: $plan.needsPercent, in: 0...(100 - plan.wantsPercent))
                Stepper("Desideri: \(plan.wantsPercent)%", value: $plan.wantsPercent, in: 0...(100 - plan.needsPercent))
                Text("Risparmio: \(plan.savingsPercent)%").font(.headline)
            } else {
                Text("50% necessità · 30% desideri · 20% risparmio").font(.headline)
                Button("Adatta le percentuali") { plan.method = .custom }
            }
            Text("Se le entrate variano, scegli una cifra prudente che puoi aggiornare. Se le necessità superano il 50%, puoi adattare le percentuali.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .onAppear {
            if plan.method == .fiftyThirtyTwenty { plan.needsPercent = 50; plan.wantsPercent = 30 }
        }
    }
}

private struct BudgetingCategoryStep: View {
    @Binding var plan: BudgetingPlan
    let categories: [FinanceCategory]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Le sottocategorie seguono la categoria principale, ma puoi scegliere un gruppo diverso. Ogni categoria appartiene a un solo gruppo.")
                .foregroundStyle(.secondary)
            if categories.isEmpty {
                Text("Crea prima almeno una categoria di spesa nelle impostazioni del libro.")
            }
            let hierarchy = CategoryHierarchy(categories: categories, kind: .expense)
            ForEach(hierarchy.roots) { category in
                VStack(alignment: .leading, spacing: 12) {
                    BudgetingCategoryPicker(plan: $plan, category: category, inherits: false)
                    let children = hierarchy.children(of: category)
                    if !children.isEmpty {
                        DisclosureGroup("Sottocategorie di \(category.name ?? "Categoria")") {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(children) { child in
                                    BudgetingCategoryPicker(plan: $plan, category: child, inherits: true)
                                }
                            }.padding(.top, 10)
                        }
                        .font(.subheadline)
                    }
                }
                .padding().unifiedCard()
            }
            Text("Alimentari e ristoranti possono stare in gruppi diversi. La scelta dipende dall'uso che ne fai, non solo dal nome della categoria.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct BudgetingCategoryPicker: View {
    @Binding var plan: BudgetingPlan
    let category: FinanceCategory
    let inherits: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(category.name ?? "Categoria", selection: Binding<BudgetAllocationGroup?>(
                get: { plan.categoryGroups[category.externalID] },
                set: { plan.categoryGroups[category.externalID] = $0 }
            )) {
                Text(inherits ? "Come la categoria principale" : "Scegli il gruppo")
                    .tag(Optional<BudgetAllocationGroup>.none)
                Text("Necessità").tag(Optional(BudgetAllocationGroup.needs))
                Text("Desideri").tag(Optional(BudgetAllocationGroup.wants))
            }.pickerStyle(.menu)
            if plan.group(for: category) == nil {
                Text("Scegli un gruppo per questa categoria o per la sua categoria principale.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct BudgetingSavingsStep: View {
    @Binding var plan: BudgetingPlan
    let account: Account
    private var conti: [Conto] {
        (account.conti ?? []).filter {
            ($0.type == .savings && $0.isActive == true) || plan.savingsContoIDs.contains($0.externalID)
        }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
    private var missingIDs: Set<String> {
        plan.savingsContoIDs.subtracting(Set((account.conti ?? []).map(\.externalID)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scegli i conti in cui tieni il denaro accantonato. Il calcolo considera entrate e uscite registrate nel mese, inclusi i prelievi e le spese da quei conti.")
                .foregroundStyle(.secondary)
            ForEach(conti) { conto in
                Toggle(conto.name ?? "Conto risparmio", isOn: Binding(
                    get: { plan.savingsContoIDs.contains(conto.externalID) },
                    set: { if $0 { plan.savingsContoIDs.insert(conto.externalID) } else { plan.savingsContoIDs.remove(conto.externalID) } }
                ))
                if conto.type != .savings {
                    Text("Questo conto non è più di tipo Risparmio. Deselezionalo oppure aggiorna il tipo del conto prima di salvare.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if conto.isActive != true {
                    Text("Conto archiviato: i suoi movimenti restano inclusi finché è selezionato.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !missingIDs.isEmpty {
                Text("Alcuni conti selezionati non sono più disponibili nel libro.")
                Button("Rimuovi i conti non disponibili dal calcolo") { plan.savingsContoIDs.subtract(missingIDs) }
            }
            if conti.isEmpty {
                Text("Non hai conti di tipo Risparmio. Puoi crearne uno o modificare il tipo di un conto esistente da Pianificazione.")
            }
            Text("Puoi continuare senza selezionare conti: vedrai il margine del mese, mentre gli accantonamenti resteranno non misurati.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Spostare denaro tra due conti selezionati non aumenta il risparmio. Il saldo iniziale e gli obiettivi compilati manualmente non entrano in questo calcolo.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct BudgetingPreviewStep: View {
    let plan: BudgetingPlan
    let account: Account
    let overlapping: [FinanceBudget]
    @Binding var archiveOverlapping: Bool
    private var currency: String { account.currency ?? "EUR" }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(plan.method.title).font(.headline)
            if plan.method != .manual {
                SavingsAmountRow(title: "Entrate di riferimento", amount: plan.monthlyIncome, currency: currency)
                SavingsAmountRow(title: "Limite mensile necessità", amount: plan.roundedLimit(for: .needs, currency: currency), currency: currency)
                SavingsAmountRow(title: "Limite mensile desideri", amount: plan.roundedLimit(for: .wants, currency: currency), currency: currency)
                SavingsAmountRow(title: "Obiettivo di risparmio", amount: plan.roundedSavingsTarget(currency: currency), currency: currency)
                Text("I limiti con importo positivo e categorie associate saranno creati o aggiornati nei budget del libro. L'obiettivo di risparmio non è una spesa e non viene registrato automaticamente.")
                    .font(.caption).foregroundStyle(.secondary)
                if !overlapping.isEmpty {
                    Divider()
                    Text("Budget esistenti sulle stesse categorie").font(.headline)
                    ForEach(overlapping) { budget in Text(budget.name ?? "Budget") }
                    Toggle("Disattiva questi budget quando applico il piano", isOn: $archiveOverlapping)
                    Text("Se li conservi, una spesa potrà comparire anche nei limiti manuali. I budget non devono essere sommati.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("I budget creati dal metodo saranno disattivati. I tuoi budget manuali rimangono disponibili.")
            }
            Divider()
            let selected = (account.conti ?? []).filter { plan.savingsContoIDs.contains($0.externalID) }
            if selected.isEmpty { Text("Accantonamenti: non misurati") }
            else {
                Text("Conti usati per gli accantonamenti").font(.headline)
                ForEach(selected) { Text($0.name ?? "Conto risparmio") }
            }
            Text("Puoi modificare o disattivare il metodo in qualsiasi momento. Nessun movimento viene creato o modificato.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

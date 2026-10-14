import SwiftUI
import SwiftData
import FinanceCore

struct MoneyFlowView: View {
    let transactions: [DirectionTransaction]
    let currency: String
    let interval: DateInterval
    let periodTitle: String
    let scopeContoIDs: Set<UUID>
    @Query private var categories: [FinanceCore.Category]

    var body: some View {
        let report = RecordedFlowReport.calculate(
            transactions: transactions,
            categories: categories.map {
                FlowCategory(id: $0.id, parentID: $0.parentCategoryId,
                             name: $0.name ?? "Categoria", color: $0.color ?? CategoryPalette.fallback)
            }, interval: interval)
        MoneyFlowExplorer(report: report, currency: currency, periodTitle: periodTitle,
                          interval: interval, scopeContoIDs: scopeContoIDs)
            .navigationTitle("Flusso del denaro")
            .toolbarTitleDisplayMode(.inline)
            #if os(iOS)
            .toolbar(.visible, for: .navigationBar)
            #endif
    }
}

private enum MoneyFlowGranularity: String {
    case macroCategories
    case subcategories
}

private struct MoneyFlowExplorer: View {
    let report: RecordedFlowReport
    let currency: String
    let periodTitle: String
    let interval: DateInterval
    let scopeContoIDs: Set<UUID>
    var reduceMotionOverride: Bool? = nil
    @State private var path: [String] = []
    @State private var granularity: MoneyFlowGranularity = .macroCategories
    @State private var chartPosition = ScrollPosition()
    @State private var chartOffset = CGPoint.zero
    @State private var chartOffsets: [String: CGPoint] = [:]
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    private var viewportKey: String { viewportKey(for: path) }
    private func viewportKey(for route: [String]) -> String {
        route.last ?? "overview-\(granularity.rawValue)"
    }
    private var motion: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.24) }
    private var backTitle: String {
        guard path.count > 1 else { return String(localized: "Indietro") }
        var nodes = report.categories
        for id in path.dropLast() {
            guard let node = nodes.first(where: { $0.id == id }) else { break }
            if id == path[path.count - 2] { return String(localized: "Torna a \(node.name)") }
            nodes = node.children
        }
        return String(localized: "Indietro")
    }

    private func navigate(to route: [String], restoring: Bool) {
        chartOffsets[viewportKey] = chartOffset
        let offset = restoring ? chartOffsets[viewportKey(for: route)] : nil
        withAnimation(motion) {
            path = route
            chartPosition.scrollTo(point: offset ?? .zero)
        }
    }

    private var focus: RecordedFlowNode? {
        var nodes = report.categories
        var result: RecordedFlowNode?
        for id in path {
            guard let node = nodes.first(where: { $0.id == id }) else { break }
            result = node
            nodes = node.children
        }
        return result
    }

    private func select(_ node: RecordedFlowNode) {
        func route(in nodes: [RecordedFlowNode]) -> [String]? {
            for candidate in nodes {
                if candidate.id == node.id { return [candidate.id] }
                if let nested = route(in: candidate.children) { return [candidate.id] + nested }
            }
            return nil
        }
        guard let route = route(in: report.categories), route != path else { return }
        navigate(to: route, restoring: false)
    }

    private func goBack(toOverview: Bool = false) {
        navigate(to: toOverview ? [] : Array(path.dropLast()), restoring: true)
    }

    @ViewBuilder
    private func diagram(layout: MoneyFlowLayout) -> some View {
        if reduceMotion {
            MoneyFlowDiagram(layout: layout, currency: currency, focusedID: focus?.id,
                             reduceMotion: true, select: select)
                .id(viewportKey)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.1), value: path)
        } else {
            MoneyFlowDiagram(layout: layout, currency: currency, focusedID: focus?.id,
                             reduceMotion: false, select: select)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if focus != nil {
                MoneyFlowControls(backTitle: backTitle,
                                  back: { goBack() }, reset: { goBack(toOverview: true) })
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .background(ForgiaPalette.surface)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        MoneyFlowSummary(report: report, currency: currency, periodTitle: periodTitle)
                            .id("money-flow-summary")
                        if !report.canDraw {
                            ContentUnavailableView("Flusso non disponibile", systemImage: "arrow.triangle.branch",
                                description: Text(report.hasInvalidAmounts
                                    ? "Alcuni movimenti non hanno un importo valido. Correggili per visualizzare il flusso."
                                    : "Le rettifiche rendono negativa una categoria o le entrate. Consulta i movimenti per leggere questi importi."))
                        } else if report.income == 0 && report.expenses == 0 {
                            ContentUnavailableView {
                                FormiEmptyStateLabel(title: "Nessun movimento nel periodo", artwork: .origami)
                            } description: {
                                Text("Registra un'entrata o un'uscita per vedere il percorso del denaro.")
                            }
                        } else {
                            if focus == nil {
                                VStack(alignment: .leading, spacing: 10) {
                                    Picker("Dettaglio del flusso", selection: Binding(
                                        get: { granularity },
                                        set: { value in
                                            chartOffsets[viewportKey] = chartOffset
                                            withAnimation(motion) {
                                                granularity = value
                                                chartPosition.scrollTo(point: chartOffsets[viewportKey] ?? .zero)
                                            }
                                        }
                                    )) {
                                        Text("Macro categorie").tag(MoneyFlowGranularity.macroCategories)
                                        Text("Sottocategorie").tag(MoneyFlowGranularity.subcategories)
                                    }
                                    .pickerStyle(.segmented)
                                    .accessibilityIdentifier("money-flow-granularity")
                                    if granularity == .macroCategories {
                                        Text("Le uscite sono raggruppate per macro categoria.")
                                            .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                                    } else {
                                        Text("Ogni macro categoria mostra le sue sottocategorie. Scorri il grafico per leggere tutti i dettagli.")
                                            .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                                    }
                                }
                            }
                            VStack(alignment: .leading, spacing: 14) {
                                if let focus {
                                    MoneyFlowFocusDetails(node: focus, expenseTotal: report.expenses,
                                        currency: currency, interval: interval, scopeContoIDs: scopeContoIDs)
                                        .id(focus.id)
                                        .transition(.opacity)
                                }
                                if focus?.children.isEmpty != true {
                                    Text("Tocca una categoria per vedere il suo flusso e le sue sottocategorie.")
                                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                                }
                            }
                            .animation(.easeInOut(duration: reduceMotion ? 0.1 : 0.16), value: path)
                            .id("money-flow-selection")
                            GeometryReader { geometry in
                                let layout = MoneyFlowLayout(report: report, focus: focus,
                                    granularity: granularity,
                                    width: max(320, geometry.size.width - 32))
                                ScrollView([.horizontal, .vertical]) {
                                    diagram(layout: layout)
                                    .padding(16)
                                }
                                .scrollPosition($chartPosition)
                                .onScrollGeometryChange(for: CGPoint.self) { $0.contentOffset } action: { _, offset in
                                    chartOffset = offset
                                }
                                .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 22))
                                .contentShape(Rectangle())

                            }
                            .frame(height: 470)
                            .accessibilityIdentifier("money-flow-diagram")
                            if focus?.children.isEmpty != true {
                                MoneyFlowCategoryList(nodes: focus?.children ?? report.categories,
                                    total: focus?.amount ?? report.expenses, currency: currency, select: select)
                            }
                        }
                        Text("Lo spessore delle fasce rappresenta l'importo. Il margine è la differenza tra entrate e uscite registrate, non il risparmio accantonato. Trasferimenti e movimenti futuri sono esclusi.")
                            .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                    }
                    .padding(22)
                }
                .task(id: path) {
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    withAnimation(motion) {
                        proxy.scrollTo(path.isEmpty ? "money-flow-summary" : "money-flow-selection", anchor: .top)
                    }
                }
            }
        }
        .themedBackground()
    }
}

private struct MoneyFlowSummary: View {
    let report: RecordedFlowReport
    let currency: String
    let periodTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(periodTitle).font(.system(.title2, design: .serif, weight: .semibold))
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    MoneyFlowMetric(title: "Entrate", amount: report.income, currency: currency, color: ForgiaPalette.accent)
                    MoneyFlowMetric(title: "Uscite", amount: report.expenses, currency: currency, color: ForgiaPalette.spending)
                    MoneyFlowMetric(title: report.shortfall > 0 ? "Differenza" : "Margine",
                                    amount: report.shortfall > 0 ? -report.shortfall : report.margin,
                                    currency: currency, color: report.shortfall > 0 ? ForgiaPalette.deficit : ForgiaPalette.margin)
                }
                VStack(alignment: .leading, spacing: 12) {
                    MoneyFlowMetric(title: "Entrate", amount: report.income, currency: currency, color: ForgiaPalette.accent)
                    MoneyFlowMetric(title: "Uscite", amount: report.expenses, currency: currency, color: ForgiaPalette.spending)
                    MoneyFlowMetric(title: report.shortfall > 0 ? "Differenza" : "Margine", amount: report.income - report.expenses,
                                    currency: currency, color: report.shortfall > 0 ? ForgiaPalette.deficit : ForgiaPalette.margin)
                }
            }
            if report.shortfall > 0 {
                Text("Le uscite superano le entrate del periodo. La differenza completa il flusso e non rappresenta un'entrata registrata.")
                    .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            }
        }
    }
}

private struct MoneyFlowMetric: View {
    let title: LocalizedStringKey
    let amount: Decimal
    let currency: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            Text(amount, format: .currency(code: currency))
                .font(.system(.headline, design: .rounded)).foregroundStyle(color).monospacedDigit()
                .fixedSize()
        }
    }
}

private struct MoneyFlowControls: View {
    let backTitle: String
    let back: () -> Void
    let reset: () -> Void
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                backButton
                Spacer(minLength: 0)
                Button("Panoramica", action: reset)
            }
            VStack(alignment: .leading, spacing: 8) {
                backButton
                Button("Panoramica", action: reset)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private var backButton: some View {
        Button(action: back) { Label(backTitle, systemImage: "arrow.turn.up.left") }
            .accessibilityIdentifier("money-flow-back")
    }
}

private struct MoneyFlowFocusDetails: View {
    let node: RecordedFlowNode
    let expenseTotal: Decimal
    let currency: String
    let interval: DateInterval
    let scopeContoIDs: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(node.name).font(.title3.weight(.semibold))
                .accessibilityIdentifier("money-flow-focus-name")
            Text(node.amount, format: .currency(code: currency))
                .font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
            if expenseTotal > 0 {
                let share = NSDecimalNumber(decimal: node.amount / expenseTotal).doubleValue
                Text("\(share, format: .percent.precision(.fractionLength(1))) delle uscite del periodo")
                    .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            }
            if node.children.isEmpty {
                Text("Questo è il dettaglio finale del flusso.")
                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            }
            if let id = node.categoryID, !node.id.hasSuffix(":direct") {
                NavigationLink {
                    TransactionListView(initialCategoryID: id,
                        initialInterval: DateInterval(start: interval.start, end: min(interval.end, Date())),
                        expensesOnly: true, scopeContoIDs: scopeContoIDs,
                        isPushed: true, pushedTitle: node.name)
                } label: {
                    Label("Vedi movimenti", systemImage: "list.bullet")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MoneyFlowCategoryList: View {
    let nodes: [RecordedFlowNode]
    let total: Decimal
    let currency: String
    let select: (RecordedFlowNode) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Distribuzione").font(.headline)
            ForEach(nodes) { node in
                Button { select(node) } label: {
                    MoneyFlowCategoryRow(node: node, total: total, currency: currency)
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("money-flow-category-\(node.name)")
            }
        }
    }
}

private struct MoneyFlowCategoryRow: View {
    let node: RecordedFlowNode
    let total: Decimal
    let currency: String
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Color(hex: node.color)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(node.id.hasSuffix(":direct") ? String(localized: "Direttamente nella categoria") : node.name)
                    .font(.subheadline.weight(.medium))
                if total > 0 {
                    Text(NSDecimalNumber(decimal: node.amount / total).doubleValue, format: .percent.precision(.fractionLength(1)))
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                }
            }
            Spacer(minLength: 4)
            Text(node.amount, format: .currency(code: currency)).font(.subheadline.weight(.semibold)).monospacedDigit()
            if node.categoryID != nil && !node.id.hasSuffix(":direct") {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Vertical whitespace keeps tiny categories readable; ribbon thickness alone encodes money.
private struct MoneyFlowLayout {
    struct Node: Identifiable {
        let id: String
        let title: String
        let amount: Decimal
        let color: Color
        let x: CGFloat
        let y: CGFloat
        let thickness: CGFloat
        let category: RecordedFlowNode?
    }
    struct Ribbon: Identifiable {
        let x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, thickness: CGFloat
        let color: Color
        var category: RecordedFlowNode? = nil
        var overviewID: String = ""
        var id: String { category?.id ?? overviewID }

        func path(minimumThickness: CGFloat = 0) -> Path {
            let height = max(thickness, minimumThickness)
            let startY = y1 - (height - thickness) / 2
            let endY = y2 - (height - thickness) / 2
            let bend = (x2 - x1) * 0.5
            var path = Path()
            path.move(to: CGPoint(x: x1, y: startY))
            path.addCurve(to: CGPoint(x: x2, y: endY),
                          control1: CGPoint(x: x1 + bend, y: startY),
                          control2: CGPoint(x: x2 - bend, y: endY))
            path.addLine(to: CGPoint(x: x2, y: endY + height))
            path.addCurve(to: CGPoint(x: x1, y: startY + height),
                          control1: CGPoint(x: x2 - bend, y: endY + height),
                          control2: CGPoint(x: x1 + bend, y: startY + height))
            path.closeSubpath()
            return path
        }
    }
    var nodes: [Node] = []
    var ribbons: [Ribbon] = []
    let width: CGFloat
    let labelWidth: CGFloat
    var height: CGFloat = 0

    init(report: RecordedFlowReport, focus: RecordedFlowNode?, granularity: MoneyFlowGranularity,
         width: CGFloat) {
        let showsSubcategories = focus == nil && granularity == .subcategories
        let levels = focus != nil ? 2 : (showsSubcategories ? 4 : 3)
        self.width = max(width, showsSubcategories ? 620 : 320)
        let trailingSpace: CGFloat = focus != nil || self.width >= 392 ? 144 : 108
        let step = (self.width - trailingSpace) / CGFloat(levels - 1)
        self.labelWidth = min(124, max(80, step - 22))
        let denominator = focus?.amount ?? max(report.income, report.expenses)
        let unit: CGFloat = denominator > 0 ? 260 / CGFloat(truncating: NSDecimalNumber(decimal: denominator)) : 0
        func thickness(_ amount: Decimal) -> CGFloat { CGFloat(truncating: NSDecimalNumber(decimal: amount)) * unit }
        func extent(_ node: RecordedFlowNode, depth: Int) -> CGFloat {
            if depth > 0, !node.children.isEmpty {
                return node.children.reduce(CGFloat.zero) { $0 + extent($1, depth: depth - 1) }
            }
            return max(84, thickness(node.amount) + 34)
        }
        func place(_ node: RecordedFlowNode, column: Int, start: CGFloat, depth: Int) -> Node {
            let block = extent(node, depth: depth)
            let placed = Node(id: node.id, title: node.name, amount: node.amount, color: Color(hex: node.color),
                              x: 8 + CGFloat(column) * step, y: start + block / 2,
                              thickness: thickness(node.amount), category: node)
            nodes.append(placed)
            if depth > 0, !node.children.isEmpty {
                var cursor = start
                var slot = placed.y - placed.thickness / 2
                for child in node.children {
                    let target = place(child, column: column + 1, start: cursor, depth: depth - 1)
                    ribbons.append(.init(x1: placed.x + 8, y1: slot, x2: target.x,
                                         y2: target.y - target.thickness / 2,
                                         thickness: target.thickness, color: target.color, category: child))
                    slot += target.thickness
                    cursor += extent(child, depth: depth - 1)
                }
            }
            return placed
        }
        if let focus {
            _ = place(focus, column: 0, start: 28, depth: 1)
            height = extent(focus, depth: 1) + 56
            return
        }
        let depth = showsSubcategories ? 1 : 0
        let expenseBlock = max(56, report.categories.reduce(CGFloat.zero) { $0 + extent($1, depth: depth) })
        let expense = Node(id: "expenses", title: String(localized: "Uscite"), amount: report.expenses,
                           color: ForgiaPalette.spending, x: 8 + step, y: 28 + expenseBlock / 2,
                           thickness: thickness(report.expenses), category: nil)
        if report.expenses > 0 { nodes.append(expense) }
        var cursor: CGFloat = 28
        var slot = expense.y - expense.thickness / 2
        for category in report.categories {
            let target = place(category, column: 2, start: cursor, depth: depth)
            ribbons.append(.init(x1: expense.x + 8, y1: slot, x2: target.x,
                                 y2: target.y - target.thickness / 2, thickness: target.thickness,
                                 color: target.color, category: category))
            slot += target.thickness
            cursor += extent(category, depth: depth)
        }
        let marginHeight = report.margin > 0 ? thickness(report.margin) + 64 : 0
        height = expenseBlock + marginHeight + 56
        let income = Node(id: "income", title: String(localized: "Entrate"), amount: report.income,
                          color: ForgiaPalette.accent, x: 8, y: 28 + thickness(report.income) / 2,
                          thickness: thickness(report.income), category: nil)
        if report.income > 0 { nodes.append(income) }
        let covered = thickness(min(report.income, report.expenses))
        if covered > 0 {
            ribbons.append(.init(x1: 16, y1: 28, x2: expense.x, y2: expense.y - expense.thickness / 2,
                                 thickness: covered, color: expense.color, overviewID: "income-expenses"))
        }
        if report.margin > 0 {
            let margin = Node(id: "margin", title: String(localized: "Margine"), amount: report.margin,
                              color: ForgiaPalette.margin, x: expense.x, y: 28 + expenseBlock + marginHeight / 2,
                              thickness: thickness(report.margin), category: nil)
            nodes.append(margin)
            ribbons.append(.init(x1: 16, y1: 28 + covered, x2: margin.x,
                                 y2: margin.y - margin.thickness / 2, thickness: margin.thickness,
                                 color: margin.color, overviewID: "income-margin"))
        }
        if report.shortfall > 0 {
            let deficit = Node(id: "shortfall", title: String(localized: "Differenza"), amount: report.shortfall,
                               color: ForgiaPalette.deficit, x: 8, y: 92 + thickness(report.income) + thickness(report.shortfall) / 2,
                               thickness: thickness(report.shortfall), category: nil)
            nodes.append(deficit)
            ribbons.append(.init(x1: 16, y1: deficit.y - deficit.thickness / 2, x2: expense.x,
                                 y2: expense.y - expense.thickness / 2 + covered,
                                 thickness: deficit.thickness, color: deficit.color, overviewID: "shortfall-expenses"))
            height = max(height, deficit.y + deficit.thickness / 2 + 40)
        }
    }
}

#if DEBUG
/// Deterministic visual fixture; does not create or alter financial records.
struct MoneyFlowVisualFixture: View {
    @State private var state = AppStateManager(persistsSelection: false)
    private static let container = try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
    private static let report: RecordedFlowReport = {
        let home = UUID(), rent = UUID(), utilities = UUID(), food = UUID(), groceries = UUID(), coffee = UUID()
        let date = Date()
        let categories = [
            FlowCategory(id: home, name: "Casa", color: CategoryPalette.prugna),
            FlowCategory(id: rent, parentID: home, name: "Affitto", color: CategoryPalette.prugna),
            FlowCategory(id: utilities, parentID: home, name: "Utenze", color: CategoryPalette.prugna),
            FlowCategory(id: food, name: "Cibo", color: CategoryPalette.terracotta),
            FlowCategory(id: groceries, parentID: food, name: "Alimentari", color: CategoryPalette.terracotta),
            FlowCategory(id: coffee, parentID: food, name: "Bar e caffè", color: CategoryPalette.terracotta)
        ]
        for category in categories {
            let model = FinanceCore.Category(name: category.name, color: category.color,
                                             parentCategoryId: category.parentID)
            model.id = category.id
            container.mainContext.insert(model)
        }
        try! container.mainContext.save()
        var entries = [DirectionTransaction(date: date, amount: 2850, type: .income,
                                           categoryID: nil, categoryName: "Stipendio", isRecurring: false)]
        let expenses: [(UUID?, Decimal)] = [(rent, 890), (utilities, 128), (home, 102.72),
                                          (groceries, 425.31), (coffee, 4.50), (nil, 200)]
        for (id, amount) in expenses {
            entries.append(.init(date: date, amount: amount, type: .expense,
                                 categoryID: id, categoryName: "Da classificare", isRecurring: false))
        }
        return .calculate(transactions: entries, categories: categories,
                          interval: DateInterval(start: date.addingTimeInterval(-100), end: date.addingTimeInterval(100)))
    }()
    var body: some View {
        NavigationStack {
            MoneyFlowExplorer(report: Self.report, currency: "EUR", periodTitle: "Ottobre 2026",
                              interval: Calendar.current.dateInterval(of: .month, for: Date())!, scopeContoIDs: [],
                              reduceMotionOverride: ProcessInfo.processInfo.arguments.contains("UITEST_MONEY_FLOW_REDUCE_MOTION") ? true : nil)
                .navigationTitle("Flusso del denaro")
                .toolbarTitleDisplayMode(.inline)
        }
        .modelContainer(Self.container)
        .environment(state)
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("UITEST_VISUAL_DARK") ? .dark : .light)
    }
}
#Preview("Flusso") { MoneyFlowVisualFixture() }
#endif

private struct MoneyFlowDiagram: View {
    let layout: MoneyFlowLayout
    let currency: String
    let focusedID: String?
    let reduceMotion: Bool
    let select: (RecordedFlowNode) -> Void
    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ForEach(layout.ribbons) { ribbon in
                    MoneyFlowRibbonShape(x1: ribbon.x1, y1: ribbon.y1, x2: ribbon.x2,
                                         y2: ribbon.y2, thickness: ribbon.thickness)
                        .fill(ribbon.color.opacity(0.38))
                        .transition(.opacity)
                }
                ForEach(layout.nodes) { node in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(node.color)
                        .frame(width: 8, height: max(1, node.thickness))
                        .position(x: node.x + 4, y: node.y)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                if let category = layout.nodes.first(where: {
                    $0.category != nil && CGRect(x: $0.x - 12,
                        y: $0.y - max(44, $0.thickness) / 2,
                        width: 32, height: max(44, $0.thickness)).contains(location)
                })?.category {
                    select(category)
                } else if let category = layout.ribbons.reversed().first(where: {
                    $0.category != nil && $0.path(minimumThickness: 22).contains(location)
                })?.category {
                    select(category)
                }
            }
            .accessibilityHidden(true)
            ForEach(layout.nodes) { node in
                MoneyFlowNodeLabel(node: node, currency: currency, width: layout.labelWidth)
                    .accessibilityHidden(node.category != nil && node.id != focusedID)
                    .overlay {
                        if let category = node.category, category.id != focusedID {
                            Button { select(category) } label: {
                                Color.clear.contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("\(node.title), \(node.amount, format: .currency(code: currency))"))
                            .accessibilityHint("Mostra questa categoria e le sue sottocategorie")
                            .accessibilityIdentifier("money-flow-node-\(node.title)")
                        }
                    }
                .position(x: node.x + 12 + layout.labelWidth / 2, y: node.y)
                .transition(.opacity)
            }
        }
        .frame(width: layout.width, height: layout.height)
        .transaction { if reduceMotion { $0.animation = nil } }
    }
}

@Animatable
private struct MoneyFlowRibbonShape: Shape {
    var x1: CGFloat
    var y1: CGFloat
    var x2: CGFloat
    var y2: CGFloat
    var thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        MoneyFlowLayout.Ribbon(x1: x1, y1: y1, x2: x2, y2: y2,
                               thickness: thickness, color: .clear).path()
    }
}

private struct MoneyFlowNodeLabel: View {
    let node: MoneyFlowLayout.Node
    let currency: String
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(node.title).font(.caption.weight(.semibold)).lineLimit(2)
            Text(node.amount, format: .currency(code: currency)).font(.caption2).monospacedDigit()
        }
        .foregroundStyle(.primary)
        .padding(5)
        .frame(width: width, alignment: .leading)
        .background(ForgiaPalette.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: 7))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

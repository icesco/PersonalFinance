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

private struct MoneyFlowExplorer: View {
    let report: RecordedFlowReport
    let currency: String
    let periodTitle: String
    let interval: DateInterval
    let scopeContoIDs: Set<UUID>
    @State private var zoom: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1
    @State private var path: [String] = []

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
    private var effectiveZoom: CGFloat { min(3, max(1, zoom * magnification)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                MoneyFlowSummary(report: report, currency: currency, periodTitle: periodTitle)
                if !report.canDraw {
                    ContentUnavailableView("Flusso non disponibile", systemImage: "arrow.triangle.branch",
                        description: Text(report.hasInvalidAmounts
                            ? "Alcuni movimenti non hanno un importo valido. Correggili per visualizzare il flusso."
                            : "Le rettifiche rendono negativa una categoria o le entrate. Consulta i movimenti per leggere questi importi."))
                } else if report.income == 0 && report.expenses == 0 {
                    ContentUnavailableView("Nessun movimento nel periodo", systemImage: "arrow.triangle.branch",
                        description: Text("Registra un'entrata o un'uscita per vedere il percorso del denaro."))
                } else {
                    MoneyFlowControls(zoom: $zoom, isFocused: focus != nil,
                                      back: { if !path.isEmpty { path.removeLast() }; zoom = 1 },
                                      reset: { path = []; zoom = 1 })
                    if let focus {
                        Text(focus.name).font(.title3.weight(.semibold))
                    }
                    Text("Allarga con due dita o usa + per mostrare le sottocategorie. Trascina per esplorare; tocca una categoria per concentrarti sul suo flusso.")
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                    GeometryReader { geometry in
                        let layout = MoneyFlowLayout(report: report, focus: focus,
                            expanded: effectiveZoom >= 1.4, width: max(320, geometry.size.width - 32))
                        ScrollView([.horizontal, .vertical]) {
                            MoneyFlowDiagram(layout: layout, currency: currency) { node in
                                // Expanded grandchildren must retain their ancestry for Back.
                                func route(in nodes: [RecordedFlowNode]) -> [String]? {
                                    for candidate in nodes {
                                        if candidate.id == node.id { return [candidate.id] }
                                        if let nested = route(in: candidate.children) { return [candidate.id] + nested }
                                    }
                                    return nil
                                }
                                path = route(in: report.categories) ?? []
                                zoom = 1
                            }
                            .scaleEffect(effectiveZoom, anchor: .topLeading)
                            .frame(width: layout.width * effectiveZoom, height: layout.height * effectiveZoom, alignment: .topLeading)
                            .padding(16)
                        }
                        .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 22))
                        .simultaneousGesture(MagnifyGesture()
                            .updating($magnification) { value, state, _ in state = value.magnification }
                            .onEnded { value in zoom = min(3, max(1, zoom * value.magnification)) })
                    }
                    .frame(height: 470)
                    .accessibilityIdentifier("money-flow-diagram")
                    MoneyFlowCategoryList(nodes: focus.map { $0.children.isEmpty ? [$0] : $0.children } ?? report.categories,
                        total: focus?.amount ?? report.expenses, currency: currency,
                        interval: interval, scopeContoIDs: scopeContoIDs) { node in
                            path.append(node.id)
                            zoom = 1
                        }
                }
                Text("Lo spessore delle fasce rappresenta l'importo. Il margine è la differenza tra entrate e uscite registrate, non il risparmio accantonato. Trasferimenti e movimenti futuri sono esclusi.")
                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            }
            .padding(22)
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
    @Binding var zoom: CGFloat
    let isFocused: Bool
    let back: () -> Void
    let reset: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            if isFocused {
                Button(action: back) { Image(systemName: "arrow.turn.up.left") }
                    .accessibilityLabel("Categoria precedente")
            }
            Button("Panoramica", action: reset)
            Spacer(minLength: 0)
            Button { zoom = max(1, zoom - 0.5) } label: { Image(systemName: "minus.magnifyingglass") }
                .disabled(zoom <= 1).accessibilityLabel("Riduci zoom")
            Text(zoom, format: .percent.precision(.fractionLength(0)))
                .font(.caption).monospacedDigit().accessibilityLabel("Livello di zoom")
            Button { zoom = min(3, zoom + 0.5) } label: { Image(systemName: "plus.magnifyingglass") }
                .disabled(zoom >= 3).accessibilityLabel("Aumenta zoom")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

private struct MoneyFlowCategoryList: View {
    let nodes: [RecordedFlowNode]
    let total: Decimal
    let currency: String
    let interval: DateInterval
    let scopeContoIDs: Set<UUID>
    let select: (RecordedFlowNode) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Distribuzione").font(.headline)
            ForEach(nodes) { node in
                if !node.children.isEmpty {
                    Button { select(node) } label: {
                        MoneyFlowCategoryRow(node: node, total: total, currency: currency)
                    }.buttonStyle(.plain)
                } else if let id = node.categoryID, !node.id.hasSuffix(":direct") {
                    NavigationLink {
                        TransactionListView(initialCategoryID: id,
                                            initialInterval: DateInterval(start: interval.start, end: min(interval.end, Date())),
                                            expensesOnly: true, scopeContoIDs: scopeContoIDs,
                                            isPushed: true, pushedTitle: node.name)
                    } label: {
                        MoneyFlowCategoryRow(node: node, total: total, currency: currency)
                    }.buttonStyle(.plain)
                } else {
                    MoneyFlowCategoryRow(node: node, total: total, currency: currency)
                }
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
    struct Ribbon {
        let x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, thickness: CGFloat
        let color: Color
    }
    var nodes: [Node] = []
    var ribbons: [Ribbon] = []
    let width: CGFloat
    let labelWidth: CGFloat
    var height: CGFloat = 0

    init(report: RecordedFlowReport, focus: RecordedFlowNode?, expanded: Bool, width: CGFloat) {
        let levels = expanded ? 4 : 3
        self.width = max(width, expanded ? 624 : 320)
        let trailingSpace: CGFloat = self.width >= 392 ? 144 : 108
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
                                         thickness: target.thickness, color: target.color))
                    slot += target.thickness
                    cursor += extent(child, depth: depth - 1)
                }
            }
            return placed
        }
        if let focus {
            _ = place(focus, column: 0, start: 28, depth: expanded ? 3 : 1)
            height = extent(focus, depth: expanded ? 3 : 1) + 56
            return
        }
        let depth = expanded ? 1 : 0
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
                                 y2: target.y - target.thickness / 2, thickness: target.thickness, color: target.color))
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
                                 thickness: covered, color: expense.color))
        }
        if report.margin > 0 {
            let margin = Node(id: "margin", title: String(localized: "Margine"), amount: report.margin,
                              color: ForgiaPalette.margin, x: expense.x, y: 28 + expenseBlock + marginHeight / 2,
                              thickness: thickness(report.margin), category: nil)
            nodes.append(margin)
            ribbons.append(.init(x1: 16, y1: 28 + covered, x2: margin.x,
                                 y2: margin.y - margin.thickness / 2, thickness: margin.thickness, color: margin.color))
        }
        if report.shortfall > 0 {
            let deficit = Node(id: "shortfall", title: String(localized: "Differenza"), amount: report.shortfall,
                               color: ForgiaPalette.deficit, x: 8, y: 92 + thickness(report.income) + thickness(report.shortfall) / 2,
                               thickness: thickness(report.shortfall), category: nil)
            nodes.append(deficit)
            ribbons.append(.init(x1: 16, y1: deficit.y - deficit.thickness / 2, x2: expense.x,
                                 y2: expense.y - expense.thickness / 2 + covered,
                                 thickness: deficit.thickness, color: deficit.color))
            height = max(height, deficit.y + deficit.thickness / 2 + 40)
        }
    }
}

#if DEBUG
/// Deterministic visual fixture; does not create or alter financial records.
struct MoneyFlowVisualFixture: View {
    private let report: RecordedFlowReport = {
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
            MoneyFlowExplorer(report: report, currency: "EUR", periodTitle: "Ottobre 2026",
                              interval: Calendar.current.dateInterval(of: .month, for: Date())!, scopeContoIDs: [])
                .navigationTitle("Flusso del denaro")
                .toolbarTitleDisplayMode(.inline)
        }
    }
}
#Preview("Flusso") { MoneyFlowVisualFixture() }
#endif

private struct MoneyFlowDiagram: View {
    let layout: MoneyFlowLayout
    let currency: String
    let select: (RecordedFlowNode) -> Void
    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for ribbon in layout.ribbons {
                    let bend = (ribbon.x2 - ribbon.x1) * 0.5
                    var path = Path()
                    path.move(to: CGPoint(x: ribbon.x1, y: ribbon.y1))
                    path.addCurve(to: CGPoint(x: ribbon.x2, y: ribbon.y2),
                                  control1: CGPoint(x: ribbon.x1 + bend, y: ribbon.y1),
                                  control2: CGPoint(x: ribbon.x2 - bend, y: ribbon.y2))
                    path.addLine(to: CGPoint(x: ribbon.x2, y: ribbon.y2 + ribbon.thickness))
                    path.addCurve(to: CGPoint(x: ribbon.x1, y: ribbon.y1 + ribbon.thickness),
                                  control1: CGPoint(x: ribbon.x2 - bend, y: ribbon.y2 + ribbon.thickness),
                                  control2: CGPoint(x: ribbon.x1 + bend, y: ribbon.y1 + ribbon.thickness))
                    path.closeSubpath()
                    context.fill(path, with: .color(ribbon.color.opacity(0.38)))
                }
                for node in layout.nodes {
                    context.fill(Path(roundedRect: CGRect(x: node.x, y: node.y - node.thickness / 2,
                                                         width: 8, height: max(1, node.thickness)), cornerRadius: 3),
                                 with: .color(node.color))
                }
            }
            .accessibilityHidden(true)
            ForEach(layout.nodes) { node in
                Button { if let category = node.category { select(category) } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.id.hasSuffix(":direct") ? String(localized: "Direttamente nella categoria") : node.title)
                            .font(.caption.weight(.semibold)).lineLimit(2)
                        Text(node.amount, format: .currency(code: currency)).font(.caption2).monospacedDigit()
                        if let category = node.category, !category.children.isEmpty {
                            Image(systemName: "plus.magnifyingglass").font(.caption2)
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(5)
                    .frame(width: layout.labelWidth, alignment: .leading)
                    .background(ForgiaPalette.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: 7))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(node.category?.children.isEmpty == false ? "Mostra sottocategorie" : "")
                .position(x: node.x + 12 + layout.labelWidth / 2, y: node.y)
            }
        }
        .frame(width: layout.width, height: layout.height)
    }
}

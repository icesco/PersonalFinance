import Foundation

public struct MonthlyVariableEstimate: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let samples: [FinanceCalendarEvent]
    public let recordedSamples: [FinanceCalendarEvent]
    public let scheduledSamples: [FinanceCalendarEvent]
    public let monthlyBaseline: Decimal
    public let alreadyRecorded: Decimal
    public let scheduled: Decimal
    public var budgetID: UUID? = nil
    public var coveredCategoryIDs: Set<String> = []
    public var limitation: String? = nil
    public var remaining: Decimal { max(0, monthlyBaseline - alreadyRecorded - scheduled) }

    public func monthlyAverage(over months: Int) -> Decimal? {
        guard months > 0, let total = MonthlyForecast.total(samples) else { return nil }
        return total / Decimal(months)
    }
}

public struct MonthlyForecast: Sendable, Equatable {
    public enum Period: Sendable { case past, current, future }
    public enum CoverageStatus: Equatable {
        case coveredByBalance
        case coveredWithPlannedInflows
        case shortfall(Decimal)
        case unavailable
    }
    public let period: Period
    public let interval: DateInterval
    public let recorded: [FinanceCalendarEvent]
    public let recordedOccasional: [FinanceCalendarEvent]
    public let recordedUnscheduled: [FinanceCalendarEvent]
    public let recurring: [FinanceCalendarEvent]
    public let occasional: [FinanceCalendarEvent]
    public let income: [FinanceCalendarEvent]
    /// Signed account movements, kept separate from spending and income.
    public let transfers: [FinanceCalendarEvent]
    public let balanceMovements: [FinanceCalendarEvent]
    public let openingBalance: Decimal?
    public let balance: Decimal?
    public let sampleMonths: [Date]
    public let estimates: [MonthlyVariableEstimate]
    public let historyExclusions: [MonthlyForecastHistoryExclusion]
    public let historyLimitation: String?
    public var hasBudgetBasis: Bool = false
    public var estimateLimitation: String? {
        Self.variableLimitation(estimates: estimates, historyLimitation: historyLimitation, hasBudgetBasis: hasBudgetBasis)
    }

    fileprivate static func variableLimitation(estimates: [MonthlyVariableEstimate], historyLimitation: String?, hasBudgetBasis: Bool) -> String? {
        if let issue = estimates.compactMap(\.limitation).first { return issue }
        var covered: Set<String> = []
        for estimate in estimates where estimate.budgetID != nil {
            if !covered.isDisjoint(with: estimate.coveredCategoryIDs) {
                return "Più budget coprono le stesse categorie. In Categorie da includere selezionane uno per evitare doppi conteggi."
            }
            covered.formUnion(estimate.coveredCategoryIDs)
        }
        return hasBudgetBasis ? nil : historyLimitation
    }
    public let coverageLimitation: String?
    public let minimumProjectedBalance: Decimal?
    public let endingProjectedBalance: Decimal?
    public let deadlineShortfall: Decimal?
    public let estimatedShortfall: Decimal?

    public func excludingVariableCategories(_ ids: Set<String>) -> MonthlyForecast {
        let selected = estimates.filter { !ids.contains($0.id) }
        let shortfall: Decimal?
        if Self.variableLimitation(estimates: selected, historyLimitation: historyLimitation, hasBudgetBasis: hasBudgetBasis) == nil, let endingProjectedBalance, let deadlineShortfall {
            shortfall = max(deadlineShortfall, max(0, selected.reduce(0) { $0 + $1.remaining } - endingProjectedBalance))
        } else { shortfall = nil }
        return MonthlyForecast(period: period, interval: interval, recorded: recorded,
            recordedOccasional: recordedOccasional, recordedUnscheduled: recordedUnscheduled,
            recurring: recurring, occasional: occasional, income: income, transfers: transfers,
            balanceMovements: balanceMovements, openingBalance: openingBalance, balance: balance,
            sampleMonths: sampleMonths, estimates: selected, historyExclusions: historyExclusions,
            historyLimitation: historyLimitation, hasBudgetBasis: hasBudgetBasis, coverageLimitation: coverageLimitation,
            minimumProjectedBalance: minimumProjectedBalance, endingProjectedBalance: endingProjectedBalance,
            deadlineShortfall: deadlineShortfall, estimatedShortfall: shortfall)
    }

    public static func total(_ rows: [FinanceCalendarEvent]) -> Decimal? {
        guard rows.allSatisfy({ $0.amount != nil }) else { return nil }
        return rows.reduce(Decimal.zero) { $0 + ($1.amount ?? 0) }
    }
    public var certainRemaining: Decimal? { Self.total(recurring + occasional) }
    public var variableRemaining: Decimal? { estimateLimitation == nil ? estimates.reduce(0) { $0 + $1.remaining } : nil }
    public var remaining: Decimal? {
        guard let certainRemaining, let variableRemaining else { return nil }
        return certainRemaining + variableRemaining
    }
    public var monthTotal: Decimal? {
        guard let paid = Self.total(recorded) else { return nil }
        if period == .past { return paid }
        guard let remaining else { return nil }
        return paid + remaining
    }

    public func necessary(includingVariables: Bool) -> Decimal? {
        includingVariables ? remaining : certainRemaining
    }

    public func monthTotal(includingVariables: Bool) -> Decimal? {
        guard let paid = Self.total(recorded) else { return nil }
        if period == .past { return paid }
        return necessary(includingVariables: includingVariables).map { paid + $0 }
    }

    public func coverageStatus(safety: MonthlySafetyMargin?, includingVariables: Bool) -> CoverageStatus {
        guard period == .current, coverageLimitation == nil, let balance,
              let safety, let required = safety.requiredWithReserve,
              let gap = safety.shortfall(minimumBalance: minimumProjectedBalance,
                                        endingBalance: endingProjectedBalance,
                                        variableRemaining: includingVariables ? variableRemaining : 0) else { return .unavailable }
        if gap > 0 { return .shortfall(gap) }
        let transfersOut = transfers.reduce(Decimal.zero) { $0 + max(0, -($1.amount ?? 0)) }
        return balance >= required + transfersOut ? .coveredByBalance : .coveredWithPlannedInflows
    }

    public func fundingShortfall(safety: MonthlySafetyMargin?, includingVariables: Bool) -> Decimal? {
        switch coverageStatus(safety: safety, includingVariables: includingVariables) {
        case .coveredByBalance, .coveredWithPlannedInflows: 0
        case .shortfall(let amount): amount
        case .unavailable: nil
        }
    }
}

public enum MonthlyForecastCalculator {
    public static func build(conto: Conto, transactions: [Transaction], resolutions: [RecurrenceResolution],
                             month: Date, now: Date = Date(), calendar: Calendar = .current, budgets: [Budget] = []) -> MonthlyForecast {
        let interval = calendar.dateInterval(of: .month, for: month)!
        let currentStart = calendar.dateInterval(of: .month, for: now)!.start
        let period: MonthlyForecast.Period = interval.end <= now ? .past : interval.start > now ? .future : .current
        var seen: Set<UUID> = []
        let scoped = transactions.filter { row in
            guard seen.insert(row.id).inserted else { return false }
            switch row.type {
            case .expense: return row.fromContoId == conto.id
            case .income: return row.toContoId == conto.id
            case .transfer: return row.fromContoId == conto.id || row.toContoId == conto.id
            }
        }
        let byID = Dictionary(uniqueKeysWithValues: scoped.map { ($0.id, $0) })
        func recurring(_ row: Transaction) -> Bool { row.isRecurring == true || row.recurrenceSourceID != nil }
        func scheduled(_ row: Transaction) -> Bool {
            if row.scheduledOriginDate != nil { return true }
            // Older entries have no provenance field. Only creation before the due day is evidence.
            return row.createdAt.map { $0 < calendar.startOfDay(for: row.date) } ?? false
        }
        func valid(_ row: Transaction) -> Decimal? {
            row.amount.flatMap { !$0.isNaN && $0 >= 0 ? $0 : nil }
        }
        func event(_ row: Transaction, date: Date? = nil, signed: Bool = false) -> FinanceCalendarEvent {
            var amount = valid(row)
            if signed {
                if row.type == .expense || (row.type == .transfer && row.fromContoId == conto.id) { amount = amount.map { -$0 } }
                else if row.type == .transfer { amount = (row.destinationAmount ?? row.amount).flatMap { !$0.isNaN && $0 >= 0 ? $0 : nil } }
            }
            let date = date ?? row.date
            return .init(id: date == row.date ? row.id.uuidString : RecurrenceResolution.key(sourceID: row.id, date: date),
                         transactionID: row.id, date: date, amount: amount, type: row.type,
                         title: row.transactionDescription ?? row.category?.name ?? "Movimento",
                         kind: date <= now ? .recorded : .planned)
        }
        let events = FinanceCalendarEvents.build(transactions: scoped, resolutions: resolutions, contoIDs: [conto.id], interval: interval, now: now)
            .map { item in
                FinanceCalendarEvent(id: item.id, transactionID: item.transactionID, date: item.date,
                                     amount: byID[item.transactionID].flatMap(valid), type: item.type, title: item.title, kind: item.kind)
            }
        let recorded = events.filter { $0.type == .expense && $0.kind == .recorded }
        let pending = events.filter { $0.type == .expense && $0.kind != .recorded }
        let recurringPending = pending.filter { byID[$0.transactionID].map(recurring) == true }
        let occasional = pending.filter { byID[$0.transactionID].map(recurring) == false }
        let income = events.filter { $0.type == .income && $0.kind != .recorded }
        let recordedOccasional = recorded.filter { byID[$0.transactionID].map { !recurring($0) && scheduled($0) } == true }
        let recordedUnscheduled = recorded.filter { byID[$0.transactionID].map { !recurring($0) && !scheduled($0) } == true }
        let resolved = Set(resolutions.map(\.key)).union(scoped.compactMap { row -> String? in
            guard let sourceID = row.recurrenceSourceID else { return nil }
            return row.externalID.hasPrefix("recurrence:") ? row.externalID : RecurrenceResolution.key(sourceID: sourceID, date: row.date)
        })
        var transfers: [FinanceCalendarEvent] = []
        for row in scoped where row.type == .transfer && row.fromContoId != row.toContoId {
            if row.date > now && row.date >= interval.start && row.date < interval.end { transfers.append(event(row, signed: true)) }
            if row.isRecurring == true {
                transfers += RecurrenceOccurrenceService.pendingDates(source: row, interval: interval, resolvedKeys: resolved)
                    .filter { $0 > now }.map { event(row, date: $0, signed: true) }
            }
        }
        let balanceMovements = scoped.filter { $0.date <= now && !($0.type == .transfer && $0.fromContoId == $0.toContoId) }
            .sorted { $0.date < $1.date }.map { event($0, signed: true) }
        let opening = conto.initialBalance.flatMap { $0.isNaN ? nil : $0 }
        let balance = opening.flatMap { initial in MonthlyForecast.total(balanceMovements).map { initial + $0 } }
        let sampleMonths = (1...3).reversed().map { calendar.date(byAdding: .month, value: -$0, to: currentStart)! }
        let historyStart = sampleMonths[0]
        let history = scoped.filter { $0.type == .expense && !recurring($0) && !scheduled($0) && $0.date >= historyStart && $0.date < currentStart }
        let sources = scoped.filter { $0.type == .expense && $0.isRecurring == true && $0.recurrenceFrequency != nil &&
            ($0.recurrenceEndDate == nil || $0.recurrenceEndDate! >= interval.start) }
        let recurringPayments = MonthlyForecastHistory.recurringPayments(history: history, sources: sources, calendar: calendar)
        let incomeCategories = Set(scoped.filter { $0.type == .income }.map(MonthlyForecastHistory.categoryKey))
            .subtracting(["uncategorized"])
        var exclusions: [MonthlyForecastHistoryExclusion.Reason: [Transaction]] = [:]
        let candidates = history.filter { row in
            let reason: MonthlyForecastHistoryExclusion.Reason?
            if recurringPayments.contains(row.id) { reason = .recurringPayment }
            else if incomeCategories.contains(MonthlyForecastHistory.categoryKey(row)) || row.category?.kind == .income { reason = .mixedCategory }
            else { reason = nil }
            if let reason { exclusions[reason, default: []].append(row); return false }
            return true
        }
        let historyGroups = Dictionary(grouping: candidates, by: MonthlyForecastHistory.categoryKey)
        let variableHistory = historyGroups.values.flatMap { rows -> [Transaction] in
            let months = Set(rows.map { calendar.dateInterval(of: .month, for: $0.date)!.start })
            guard rows.count >= 3, months.count >= 2 else {
                exclusions[.sporadic, default: []] += rows
                return []
            }
            return rows
        }
        let activeMonths = Set(variableHistory.map { calendar.dateInterval(of: .month, for: $0.date)!.start })
        let latest = scoped.filter { $0.type != .transfer && $0.date <= now }.map(\.date).max()
        let limitation: String?
        if period == .past { limitation = "Mese concluso: mostriamo le spese registrate e le ricorrenze ancora da verificare, senza stimare spese future." }
        else if !scoped.contains(where: { $0.type != .transfer && $0.date <= historyStart }) || variableHistory.count < 3 || activeMonths.count < 2 {
            limitation = "Storico insufficiente: servono almeno tre mesi di osservazione e tre spese variabili nella stessa categoria in almeno due dei tre mesi completi precedenti."
        } else if variableHistory.contains(where: { valid($0) == nil }) {
            limitation = "Importi dello storico da verificare: la stima non è disponibile."
        } else if latest.map({ now.timeIntervalSince($0) > 14 * 86_400 }) ?? true {
            limitation = "Registro non aggiornato negli ultimi 14 giorni: aggiorna i movimenti per ottenere una stima."
        } else if MonthlyForecast.total(recordedUnscheduled + occasional + recordedOccasional) == nil {
            limitation = "Importi del mese da verificare: non è possibile sottrarli dalla stima."
        } else { limitation = nil }
        func categoryKey(_ row: Transaction) -> String { MonthlyForecastHistory.categoryKey(row) }
        func rounded(_ value: Decimal) -> Decimal {
            var value = value
            var result = Decimal.zero
            NSDecimalRound(&result, &value, 2, .bankers)
            return result
        }
        let grouped = Dictionary(grouping: variableHistory, by: categoryKey)
        var estimates = grouped.map { key, rows in
            let paid = recordedUnscheduled.filter { byID[$0.transactionID].map(categoryKey) == key }
            let scheduled = (occasional + recordedOccasional).filter { byID[$0.transactionID].map(categoryKey) == key }
            let totals = sampleMonths.map { month in
                MonthlyForecast.total(rows.filter { calendar.dateInterval(of: .month, for: $0.date)!.start == month }.map { event($0) }) ?? 0
            }.sorted()
            return MonthlyVariableEstimate(id: key, name: rows.first?.category?.name ?? "Da classificare",
                samples: rows.sorted { $0.date < $1.date }.map { event($0) },
                recordedSamples: paid, scheduledSamples: scheduled,
                monthlyBaseline: rounded(totals[1]),
                alreadyRecorded: MonthlyForecast.total(paid) ?? 0, scheduled: MonthlyForecast.total(scheduled) ?? 0)
        }.sorted { $0.name < $1.name }
        let monthlyBudgets = budgets.filter {
            period != .past && $0.isActive == true && $0.period == .monthly &&
            $0.contoID == conto.id && $0.account?.id == conto.account?.id && $0.coveredContoIDs.contains(conto.id)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        let budgetCategories = Set(monthlyBudgets.flatMap { $0.coveredCategoryIDs.map(\.uuidString) })
        estimates.removeAll { budgetCategories.contains($0.id) || (!monthlyBudgets.isEmpty && limitation != nil) }
        for budget in monthlyBudgets {
            let categories = Set(budget.coveredCategoryIDs.map(\.uuidString))
            func matches(_ event: FinanceCalendarEvent) -> Bool {
                byID[event.transactionID].map { categories.contains(categoryKey($0)) } == true
            }
            let paid = recorded.filter(matches), committed = pending.filter(matches)
            let spent = MonthlyForecast.total(paid), scheduled = MonthlyForecast.total(committed)
            let limit = budget.amount.flatMap { !$0.isNaN && $0 >= 0 ? $0 : nil }
            let issue = limit == nil || spent == nil || scheduled == nil || categories.isEmpty
                ? "Importi o categorie del budget da verificare: residuo non disponibile." : nil
            estimates.append(MonthlyVariableEstimate(id: "budget:\(budget.id.uuidString)", name: budget.name ?? "Budget",
                samples: paid, recordedSamples: paid, scheduledSamples: committed,
                monthlyBaseline: limit ?? 0, alreadyRecorded: spent ?? 0, scheduled: scheduled ?? 0,
                budgetID: budget.id, coveredCategoryIDs: categories, limitation: issue))
        }
        let effectiveLimitation = MonthlyForecast.variableLimitation(estimates: estimates, historyLimitation: limitation, hasBudgetBasis: !monthlyBudgets.isEmpty)
        let coverageLimitation: String?
        if period != .current { coverageLimitation = "Il saldo attuale non rappresenta il saldo di questo mese. La copertura si calcola solo per il mese corrente." }
        else if conto.type == .credit { coverageLimitation = "Questo conto è una carta di credito: il saldo non è liquidità disponibile. Verifica il conto di addebito." }
        else if !conto.supportsMonthlyForecast { coverageLimitation = "La previsione e la copertura sono disponibili solo per i conti correnti attivi." }
        else if balance == nil { coverageLimitation = "Saldo iniziale o movimenti da verificare: copertura non disponibile." }
        else if MonthlyForecast.total(pending + income + transfers) == nil { coverageLimitation = "Importi programmati da verificare: copertura non disponibile." }
        else { coverageLimitation = nil }
        var minimumProjectedBalance: Decimal?
        var endingProjectedBalance: Decimal?
        var deadlineShortfall: Decimal?
        var estimatedShortfall: Decimal?
        if coverageLimitation == nil, let balance {
            // Overdue income is not available until recorded. Expenses overdue still need coverage.
            let cash = pending.map { ($0.date, -($0.amount ?? 0)) } + income.filter { $0.date > now }.map { ($0.date, $0.amount ?? 0) } + transfers.map { ($0.date, $0.amount ?? 0) }
            let byDay = Dictionary(grouping: cash) { calendar.startOfDay(for: max(now, $0.0)) }
            var available = balance
            var minimum = available
            for day in byDay.keys.sorted() {
                available += byDay[day]!.reduce(0) { $0 + $1.1 }
                minimum = min(minimum, available)
            }
            minimumProjectedBalance = minimum
            endingProjectedBalance = available
            deadlineShortfall = max(0, -minimum)
            if effectiveLimitation == nil {
                let variable = estimates.reduce(Decimal.zero) { $0 + $1.remaining }
                estimatedShortfall = max(deadlineShortfall ?? 0, max(0, variable - available))
            }
        }
        return MonthlyForecast(period: period, interval: interval, recorded: recorded, recordedOccasional: recordedOccasional,
            recordedUnscheduled: recordedUnscheduled, recurring: recurringPending, occasional: occasional, income: income,
            transfers: transfers.sorted { $0.date < $1.date }, balanceMovements: balanceMovements, openingBalance: opening,
            balance: balance, sampleMonths: sampleMonths, estimates: estimates,
            historyExclusions: MonthlyForecastHistoryExclusion.Reason.allCases.compactMap { reason in
                exclusions[reason].map { MonthlyForecastHistoryExclusion(reason: reason, events: $0.sorted { $0.date < $1.date }.map { event($0) }) }
            }, historyLimitation: limitation, hasBudgetBasis: !monthlyBudgets.isEmpty,
            coverageLimitation: coverageLimitation, minimumProjectedBalance: minimumProjectedBalance,
            endingProjectedBalance: endingProjectedBalance, deadlineShortfall: deadlineShortfall, estimatedShortfall: estimatedShortfall)
    }
}

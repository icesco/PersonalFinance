import Foundation
import Testing
@testable import FinanceCore

struct SpokenDateParserTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }()

    /// Monday 12 October 2026, 13:40.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 13, minute: 40))!
    }

    private func parse(_ text: String, clause: String? = nil, expression: String = "") -> Date? {
        SpokenDateParser.date(in: text, clause: clause ?? text, expression: expression, now: now, calendar: calendar)
    }

    private func expect(_ text: String, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int,
                        sourceLocation: SourceLocation = #_sourceLocation) {
        guard let date = parse(text) else {
            Issue.record("No date for “\(text)”", sourceLocation: sourceLocation)
            return
        }
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        #expect([parts.month, parts.day, parts.hour, parts.minute] == [month, day, hour, minute],
                "“\(text)”", sourceLocation: sourceLocation)
    }

    @Test func withoutTimeWordsKeepsTheCurrentMoment() {
        #expect(parse("ho speso 12 euro al bar") == now)
    }

    @Test func relativeDaysKeepTheCurrentClockTime() {
        expect("ieri ho speso 5 euro", 10, 11, 13, 40)
        expect("l'altro ieri 20 euro di benzina", 10, 10, 13, 40)
        expect("domani pago l'affitto", 10, 13, 13, 40)
        expect("tre giorni fa 8 euro di pane", 10, 9, 13, 40)
        expect("3 giorni fa 8 euro", 10, 9, 13, 40)
        expect("una settimana fa 40 euro", 10, 5, 13, 40)
        expect("due settimane fa 10 euro", 9, 28, 13, 40)
    }

    @Test func weekdaysResolveToTheMostRecentOneUnlessFuture() {
        expect("sabato ho speso 30 euro", 10, 10, 13, 40)
        expect("lunedì 4 euro di caffè", 10, 12, 13, 40)
        expect("lunedì scorso 4 euro", 10, 5, 13, 40)
        expect("venerdì scorso 12 euro", 10, 9, 13, 40)
        expect("venerdì prossimo pago 50 euro", 10, 16, 13, 40)
    }

    @Test func dayNumbersAndMonths() {
        expect("il 5 ho pagato 40 euro", 10, 5, 13, 40)
        expect("il 20 ho pagato 40 euro", 9, 20, 13, 40)
        expect("il primo ottobre 60 euro", 10, 1, 13, 40)
        expect("5 ottobre 2026 bolletta 48 euro", 10, 5, 13, 40)
    }

    @Test func explicitTimes() {
        expect("alle 20:30 cena 35 euro", 10, 12, 20, 30)
        expect("ieri alle 21.15 cinema 12 euro", 10, 11, 21, 15)
        expect("alle 8 e mezza colazione 3 euro", 10, 12, 8, 30)
        expect("alle 8 e mezza di sera 20 euro", 10, 12, 20, 30)
        expect("alle 7 e un quarto 2 euro", 10, 12, 7, 15)
        expect("alle 9 e 45 parcheggio 2 euro", 10, 12, 9, 45)
        expect("all'una 15 euro", 10, 12, 1, 0)
        expect("il 5 ottobre alle 18 bolletta 48 euro", 10, 5, 18, 0)
        expect("sabato a mezzogiorno pizza 15 euro", 10, 10, 12, 0)
    }

    @Test func partsOfTheDay() {
        expect("stamattina caffè 2 euro", 10, 12, 9, 0)
        expect("stasera cena 40 euro", 10, 12, 20, 0)
        expect("ieri sera 25 euro di sushi", 10, 11, 20, 0)
        expect("ieri pomeriggio 6 euro", 10, 11, 15, 0)
        expect("a pranzo 12 euro", 10, 12, 13, 0)
        expect("ieri a cena 50 euro", 10, 11, 20, 30)
        expect("stasera alle 9 cinema 10 euro", 10, 12, 21, 0)
        expect("ieri sera alle 10 taxi 18 euro", 10, 11, 22, 0)
    }

    @Test func vagueOrConflictingWordsNeedReview() {
        #expect(parse("la settimana scorsa 30 euro") == nil)
        #expect(parse("stanotte taxi 20 euro") == nil)
        #expect(parse("ieri e oggi 20 euro") == nil)
        #expect(parse("il 31 settembre 20 euro") == nil)
    }

    @Test func eachMovementUsesItsOwnClause() {
        let text = "ieri sera ho speso 20 euro al ristorante e oggi a pranzo ho speso 12 euro"
        let first = SpokenDateParser.date(in: text, clause: "ieri sera ho speso 20 euro al ristorante",
                                          expression: "ieri sera", now: now, calendar: calendar)
        let second = SpokenDateParser.date(in: text, clause: "oggi a pranzo ho speso 12 euro",
                                           expression: "oggi a pranzo", now: now, calendar: calendar)
        #expect(first.map { calendar.dateComponents([.day, .hour], from: $0) } == DateComponents(day: 11, hour: 20))
        #expect(second.map { calendar.dateComponents([.day, .hour], from: $0) } == DateComponents(day: 12, hour: 13))
    }

    @Test func sharedDateAppliesToEveryMovement() {
        let text = "ieri ho speso 5 euro al bar e 10 euro di giornali"
        let date = SpokenDateParser.date(in: text, clause: "10 euro di giornali", expression: "", now: now, calendar: calendar)
        #expect(date.map { calendar.component(.day, from: $0) } == 11)
    }

    @Test func amountsAreNotMistakenForDays() {
        #expect(parse("ho pagato 5 euro il bar") == now)
        #expect(parse("ho speso 12,50 euro") == now)
    }
}

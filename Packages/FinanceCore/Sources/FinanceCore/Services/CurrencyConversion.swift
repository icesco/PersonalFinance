import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct CurrencyRateSnapshot: Codable, Sendable {
    public let day: String
    public let perEuro: [String: Decimal]
    public init(day: String, perEuro: [String: Decimal]) { self.day = day; self.perEuro = perEuro }
    public func rate(from: String, to: String) throws -> Decimal {
        if from == to { return 1 }
        guard let source = from == "EUR" ? 1 : perEuro[from],
              let target = to == "EUR" ? 1 : perEuro[to], source > 0, target > 0 else { throw CurrencyConversion.Failure.unsupported }
        var a = target, b = source, result = Decimal.zero
        let error = NSDecimalDivide(&result, &a, &b, .plain)
        guard error == .noError || error == .lossOfPrecision else { throw CurrencyConversion.Failure.invalid }
        return result
    }
}

public enum CurrencyConversion {
    public enum Failure: Error { case invalid, unsupported, invalidFeed }
    public static func convert(_ amount: Decimal, rate: Decimal, currency: String) throws -> Decimal {
        guard amount > 0, rate > 0, !amount.isNaN, !rate.isNaN else { throw Failure.invalid }
        var a = amount, b = rate, product = Decimal.zero, rounded = Decimal.zero
        let status = NSDecimalMultiply(&product, &a, &b, .plain)
        guard status == .noError || status == .lossOfPrecision else { throw Failure.invalid }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        NSDecimalRound(&rounded, &product, formatter.maximumFractionDigits, .plain)
        guard rounded > 0 else { throw Failure.invalid }
        return rounded
    }

    public static func parseECB(_ data: Data) throws -> [CurrencyRateSnapshot] {
        guard data.count <= 2_000_000 else { throw Failure.invalidFeed }
        let delegate = ECBParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), !delegate.snapshots.isEmpty else { throw Failure.invalidFeed }
        return delegate.snapshots.sorted { $0.day > $1.day }
    }

    private final class ECBParser: NSObject, XMLParserDelegate {
        var snapshots: [CurrencyRateSnapshot] = []
        var depth = 0
        var dateDepth = 0
        var day: String?
        var rates: [String: Decimal] = [:]
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
            depth += 1
            if let date = attributes["time"], date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
                day = date; dateDepth = depth; rates = [:]
            } else if day != nil, let code = attributes["currency"], code.count == 3,
                      let raw = attributes["rate"], let rate = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")), rate > 0, !rate.isNaN {
                rates[code] = rate
            }
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if depth == dateDepth, let day, !rates.isEmpty {
                snapshots.append(CurrencyRateSnapshot(day: day, perEuro: rates))
                self.day = nil
            }
            depth -= 1
        }
    }
}

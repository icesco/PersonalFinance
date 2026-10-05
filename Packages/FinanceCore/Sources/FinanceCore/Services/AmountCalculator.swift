import Foundation

/// Small decimal-only calculator. Never evaluates executable expressions or uses binary floating point.
public enum AmountCalculator {
    public enum Failure: Error, Equatable {
        case invalidExpression, divisionByZero, outOfRange
    }

    public static func evaluate(_ expression: String) throws -> Decimal {
        guard expression.count <= 128 else { throw Failure.outOfRange }
        var parser = Parser(characters: Array(expression.filter { !$0.isWhitespace }
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")))
        let result = try parser.sum()
        guard parser.index == parser.characters.count else { throw Failure.invalidExpression }
        return result
    }

    private struct Parser {
        let characters: [Character]
        var index = 0
        var current: Character? { index < characters.count ? characters[index] : nil }
        mutating func sum() throws -> Decimal {
            var value = try product()
            while let op = current, op == "+" || op == "-" {
                index += 1
                value = try operation(value, product(), op)
            }
            return value
        }
        mutating func product() throws -> Decimal {
            var value = try atom()
            while let op = current, op == "*" || op == "/" {
                index += 1
                value = try operation(value, atom(), op)
            }
            return value
        }
        mutating func atom() throws -> Decimal {
            if current == "+" { index += 1; return try atom() }
            if current == "-" { index += 1; return -(try atom()) }
            if current == "(" {
                index += 1
                let value = try sum()
                guard current == ")" else { throw Failure.invalidExpression }
                index += 1
                return value
            }
            let start = index
            var dots = 0
            var digits = 0
            while let character = current, "0123456789.".contains(character) {
                if character == "." { dots += 1 } else { digits += 1 }
                index += 1
            }
            guard digits > 0, dots <= 1, digits <= 28,
                  let value = Decimal(string: String(characters[start..<index]), locale: Locale(identifier: "en_US_POSIX"))
            else { throw Failure.invalidExpression }
            return value
        }
        func operation(_ left: Decimal, _ right: Decimal, _ op: Character) throws -> Decimal {
            var a = left, b = right, result = Decimal.zero
            let error: Decimal.CalculationError
            switch op {
            case "+": error = NSDecimalAdd(&result, &a, &b, .plain)
            case "-": error = NSDecimalSubtract(&result, &a, &b, .plain)
            case "*": error = NSDecimalMultiply(&result, &a, &b, .plain)
            default:
                guard b != 0 else { throw Failure.divisionByZero }
                error = NSDecimalDivide(&result, &a, &b, .plain)
            }
            guard error == .noError || error == .lossOfPrecision else { throw Failure.outOfRange }
            return result
        }
    }
}

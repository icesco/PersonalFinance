import SwiftUI

private struct FinanceCardEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    func body(content: Content) -> some View {
        content
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 8)
            .onAppear {
                guard !appeared else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) { appeared = true }
            }
    }
}

private struct FinanceNumericMotion: ViewModifier {
    let value: Decimal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.contentTransition(.numericText())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: value)
    }
}

private struct FinanceChartReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    func body(content: Content) -> some View {
        content.mask {
            Rectangle().scaleEffect(x: appeared || reduceMotion ? 1 : 0, y: 1, anchor: .leading)
        }
        .onAppear {
            guard !appeared else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { appeared = true }
        }
    }
}

extension View {
    func financeCardEntrance() -> some View { modifier(FinanceCardEntrance()) }
    func financeNumericMotion(_ value: Decimal) -> some View { modifier(FinanceNumericMotion(value: value)) }
    func financeChartReveal() -> some View { modifier(FinanceChartReveal()) }
}

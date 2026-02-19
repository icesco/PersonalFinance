//
//  CategorySparklinesSection.swift
//  Personal Finance
//

import SwiftUI
import FinanceCore

struct CategorySparklinesSection: View {
    let trends: [CategoryTrendData]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trend per Categoria").font(.headline)

            if trends.isEmpty {
                ContentUnavailableView {
                    Label("Dati insufficienti", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("Servono almeno 2 mesi di dati")
                }
            } else {
                ForEach(trends) { trend in
                    HStack(spacing: 12) {
                        Image(systemName: trend.icon)
                            .font(.body)
                            .foregroundStyle(Color(hex: trend.color))
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(trend.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(trend.currentMonth.currencyFormatted)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 100, alignment: .leading)

                        SparklinePath(
                            values: trend.monthlyAmounts.map(\.doubleValue),
                            color: Color(hex: trend.color)
                        )
                        .frame(height: 32)
                        .clipped()

                        Image(systemName: trend.isIncreasing ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(trend.isIncreasing ? .red : .green)
                            .frame(width: 20)
                    }

                    if trend.id != trends.last?.id {
                        Divider()
                    }
                }
            }
        }
        .unifiedCard()
    }
}

private struct SparklinePath: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let minVal = values.min() ?? 0
            let maxVal = values.max() ?? 1
            let range = maxVal - minVal
            let yRange = range > 0 ? range : 1

            // Inset so Catmull-Rom curves don't overshoot the edges
            let hInset: CGFloat = 8
            let vInset: CGFloat = 3
            let drawW = size.width - hInset * 2
            let drawH = size.height - vInset * 2
            let stepX = drawW / CGFloat(values.count - 1)

            func point(at index: Int) -> CGPoint {
                let x = hInset + stepX * CGFloat(index)
                let y = vInset + drawH - (CGFloat((values[index] - minVal) / yRange) * drawH)
                return CGPoint(x: x, y: y)
            }

            // Build monotone catmull-rom path
            var linePath = Path()
            linePath.move(to: point(at: 0))
            for i in 0..<values.count - 1 {
                let p0 = i > 0 ? point(at: i - 1) : point(at: i)
                let p1 = point(at: i)
                let p2 = point(at: i + 1)
                let p3 = i + 2 < values.count ? point(at: i + 2) : point(at: i + 1)

                let cp1 = CGPoint(
                    x: p1.x + (p2.x - p0.x) / 6,
                    y: p1.y + (p2.y - p0.y) / 6
                )
                let cp2 = CGPoint(
                    x: p2.x - (p3.x - p1.x) / 6,
                    y: p2.y - (p3.y - p1.y) / 6
                )
                linePath.addCurve(to: p2, control1: cp1, control2: cp2)
            }

            // Draw filled area
            var areaPath = linePath
            areaPath.addLine(to: CGPoint(x: hInset + drawW, y: size.height))
            areaPath.addLine(to: CGPoint(x: hInset, y: size.height))
            areaPath.closeSubpath()

            context.fill(
                areaPath,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.3), color.opacity(0.0)]),
                    startPoint: CGPoint(x: 0, y: vInset),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            // Draw line
            context.stroke(linePath, with: .color(color), lineWidth: 1.5)
        }
    }
}

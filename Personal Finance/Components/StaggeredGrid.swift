//
//  StaggeredGrid.swift
//  Personal Finance
//
//  Pinterest-style masonry layout using the Layout protocol.
//  Places each subview in the shortest column for a staggered effect.
//

import SwiftUI

struct StaggeredGrid: Layout {
    let columns: Int
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    init(columns: Int = 2, horizontalSpacing: CGFloat = 16, verticalSpacing: CGFloat = 16) {
        self.columns = max(1, columns)
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }

        let width = proposal.width ?? 0
        let columnWidth = columnWidth(for: width)
        var columnHeights = Array(repeating: CGFloat(0), count: columns)

        for subview in subviews {
            let shortest = columnHeights.enumerated().min(by: { $0.element < $1.element })!.offset
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))

            if columnHeights[shortest] > 0 {
                columnHeights[shortest] += verticalSpacing
            }
            columnHeights[shortest] += size.height
        }

        let maxHeight = columnHeights.max() ?? 0
        return CGSize(width: width, height: maxHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }

        let columnWidth = columnWidth(for: bounds.width)
        var columnHeights = Array(repeating: CGFloat(0), count: columns)

        for subview in subviews {
            let shortest = columnHeights.enumerated().min(by: { $0.element < $1.element })!.offset

            // Add spacing before placing (must match sizeThatFits logic)
            if columnHeights[shortest] > 0 {
                columnHeights[shortest] += verticalSpacing
            }

            let x = bounds.minX + CGFloat(shortest) * (columnWidth + horizontalSpacing)
            let y = bounds.minY + columnHeights[shortest]
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: columnWidth, height: size.height)
            )

            columnHeights[shortest] += size.height
        }
    }

    private func columnWidth(for totalWidth: CGFloat) -> CGFloat {
        let gaps = CGFloat(columns - 1) * horizontalSpacing
        return (totalWidth - gaps) / CGFloat(columns)
    }
}

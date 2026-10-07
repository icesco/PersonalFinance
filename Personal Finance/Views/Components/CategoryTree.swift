import SwiftUI
import FinanceCore

extension FinanceCategory {
    /// The category colour, or the palette's fallback for legacy categories without one.
    var tint: Color { Color(hex: color ?? "#007AFF") }
}

/// A category glyph on a wash of its colour. Macro categories get the solid, larger badge.
struct CategoryIcon: View {
    let category: FinanceCategory
    var size: CGFloat = 40
    var prominent = false

    var body: some View {
        Image(systemName: category.icon ?? "tag")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : category.tint)
            .frame(width: size, height: size)
            .background(prominent ? category.tint : category.tint.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// One row of the category tree. A macro category shows a solid badge and its subcategory count;
/// a subcategory hangs from it on a connector line in the family colour.
/// Apply `categoryTreeRowStyle()` in a List so the connector lines join across rows.
struct CategoryTreeRow<Accessory: View>: View {
    enum Level { case macro(childCount: Int), child(isLast: Bool) }

    let category: FinanceCategory
    let level: Level
    var title: String? = nil
    var subtitle: String? = nil
    @ViewBuilder var accessory: () -> Accessory

    static var macroIconSize: CGFloat { 40 }

    var body: some View {
        HStack(spacing: 12) {
            switch level {
            case let .macro(childCount):
                CategoryIcon(category: category, size: Self.macroIconSize, prominent: true)
                    .frame(maxHeight: .infinity)
                    .background {
                        if childCount > 0 {
                            // Stem from the badge down to the first subcategory.
                            TreeStem(offset: Self.macroIconSize / 2)
                                .stroke(category.tint.opacity(0.35), style: StrokeStyle(lineWidth: 2))
                        }
                    }
                labels(font: .body.weight(.semibold),
                       subtitle: subtitle ?? (childCount > 0 ? "\(childCount) sottocategorie" : "Categoria principale"))
            case let .child(isLast):
                TreeConnector(isLast: isLast)
                    .stroke(category.tint.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: Self.macroIconSize)
                    .frame(maxHeight: .infinity)
                CategoryIcon(category: category, size: 30)
                labels(font: .subheadline, subtitle: subtitle)
            }
            Spacer(minLength: 8)
            accessory()
        }
        .frame(minHeight: isMacro ? 64 : 46)
        .contentShape(Rectangle())
    }

    private var isMacro: Bool {
        if case .macro = level { return true }
        return false
    }

    private func labels(font: Font, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title ?? category.name ?? "Categoria")
                .font(font)
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(ForgiaPalette.mutedText)
            }
        }
    }
}

extension CategoryTreeRow where Accessory == EmptyView {
    init(category: FinanceCategory, level: Level, title: String? = nil, subtitle: String? = nil) {
        self.init(category: category, level: level, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Line from just below a centred badge to the bottom of the row.
struct TreeStem: Shape {
    let offset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.midY + offset))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// Vertical line from the row above, with an elbow into this row; the last child stops at the elbow.
struct TreeConnector: Shape {
    let isLast: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: isLast ? rect.midY - 8 : rect.maxY))
        if isLast {
            path.addQuadCurve(to: CGPoint(x: rect.midX + 8, y: rect.midY),
                              control: CGPoint(x: rect.midX, y: rect.midY))
        } else {
            path.move(to: CGPoint(x: rect.midX, y: rect.midY))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

extension View {
    /// Rows touch top to bottom so tree lines stay continuous; only macro rows keep a separator.
    func categoryTreeRowStyle(isMacro: Bool) -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(isMacro ? .automatic : .hidden)
    }
}

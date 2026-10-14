import SwiftUI

enum FormiFeatureArtwork: String, CaseIterable {
    case budget = "FormiBudget"
    case sharedBook = "FormiSharedBook"
    case sharedAccount = "FormiSharedAccount"
    case balance = "FormiBalance"
}

struct FormiFeatureIllustration: View {
    let artwork: FormiFeatureArtwork
    var size: CGFloat = 144
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(artwork.rawValue)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .padding(size * 0.04)
            .frame(width: size, height: size)
            .background(Color(red: 0.89, green: 0.96, blue: 0.93).opacity(colorScheme == .dark ? 1 : 0),
                        in: RoundedRectangle(cornerRadius: size * 0.18))
            .accessibilityHidden(true)
    }
}

enum FormiFeatureSymbol {
    case budget, books, accounts, sharedBook, sharedAccount, balance, categories
}

/// Simplified objects from the illustrations stay legible in compact rows.
struct FormiFeatureIcon: View {
    let symbol: FormiFeatureSymbol
    var size: CGFloat = 34
    var ink: Color?

    var body: some View {
        let ink = ink ?? ForgiaPalette.accent
        Canvas { context, canvas in
            context.scaleBy(x: canvas.width / 40, y: canvas.height / 40)
            let line = StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
            func outline(_ path: Path) { context.stroke(path, with: .color(ink), style: line) }
            func tile(_ rect: CGRect, radius: CGFloat = 3) {
                let path = Path(roundedRect: rect, cornerRadius: radius)
                context.fill(path, with: .color(ink.opacity(0.16)))
                outline(path)
            }
            func stroke(_ points: [CGPoint]) {
                var path = Path()
                path.addLines(points)
                outline(path)
            }
            switch symbol {
            case .budget:
                tile(CGRect(x: 10, y: 5, width: 20, height: 22))
                stroke([CGPoint(x: 17, y: 12), CGPoint(x: 23, y: 12)])
                tile(CGRect(x: 5, y: 18, width: 30, height: 17))
                stroke([CGPoint(x: 6, y: 19), CGPoint(x: 20, y: 28), CGPoint(x: 34, y: 19)])
            case .books, .sharedBook:
                var pages = Path()
                pages.move(to: CGPoint(x: 20, y: 12))
                pages.addQuadCurve(to: CGPoint(x: 5, y: 9), control: CGPoint(x: 12, y: 6))
                pages.addLine(to: CGPoint(x: 5, y: 30))
                pages.addQuadCurve(to: CGPoint(x: 20, y: 33), control: CGPoint(x: 13, y: 27))
                pages.addQuadCurve(to: CGPoint(x: 35, y: 30), control: CGPoint(x: 27, y: 27))
                pages.addLine(to: CGPoint(x: 35, y: 9))
                pages.addQuadCurve(to: CGPoint(x: 20, y: 12), control: CGPoint(x: 28, y: 6))
                pages.closeSubpath()
                context.fill(pages, with: .color(ink.opacity(0.16)))
                outline(pages)
                stroke([CGPoint(x: 20, y: 12), CGPoint(x: 20, y: 32)])
                if symbol == .sharedBook {
                    for x in [12.0, 28.0] {
                        context.fill(Path(ellipseIn: CGRect(x: x - 3, y: 17, width: 6, height: 6)), with: .color(ink))
                    }
                }
            case .accounts, .sharedAccount:
                tile(CGRect(x: 6, y: 9, width: 26, height: 22))
                tile(CGRect(x: 24, y: 17, width: 12, height: 10))
                context.fill(Path(ellipseIn: CGRect(x: 28, y: 20, width: 4, height: 4)), with: .color(ink))
                if symbol == .sharedAccount {
                    for x in [11.0, 19.0] {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: 16, width: 5, height: 5)), with: .color(ink))
                    }
                } else {
                    stroke([CGPoint(x: 11, y: 14), CGPoint(x: 21, y: 14)])
                }
            case .balance:
                tile(CGRect(x: 6, y: 24, width: 6, height: 11), radius: 2)
                tile(CGRect(x: 17, y: 18, width: 6, height: 17), radius: 2)
                tile(CGRect(x: 28, y: 22, width: 6, height: 13), radius: 2)
                stroke([CGPoint(x: 5, y: 16), CGPoint(x: 14, y: 11), CGPoint(x: 24, y: 14), CGPoint(x: 35, y: 7)])
            case .categories:
                tile(CGRect(x: 5, y: 5, width: 13, height: 13), radius: 4)
                context.fill(Path(ellipseIn: CGRect(x: 23, y: 5, width: 13, height: 13)), with: .color(ink))
                tile(CGRect(x: 23, y: 23, width: 13, height: 13), radius: 4)
                var triangle = Path()
                triangle.addLines([CGPoint(x: 11, y: 23), CGPoint(x: 18, y: 35), CGPoint(x: 4, y: 35)])
                triangle.closeSubpath()
                context.fill(triangle, with: .color(ink))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview("Formi objects") {
    HStack(spacing: 20) {
        FormiFeatureIcon(symbol: .budget)
        FormiFeatureIcon(symbol: .books)
        FormiFeatureIcon(symbol: .sharedBook)
        FormiFeatureIcon(symbol: .accounts)
        FormiFeatureIcon(symbol: .sharedAccount)
        FormiFeatureIcon(symbol: .balance)
        FormiFeatureIcon(symbol: .categories)
    }
    .padding()
    .themedBackground()
}

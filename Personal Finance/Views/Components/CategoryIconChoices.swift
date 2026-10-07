import FinanceCore

/// Symbols offered when creating or editing a category, including every default one
/// so a suggested category can be edited without losing its icon.
enum CategoryIconChoices {
    static let all: [String] = {
        let base = [
            "tag", "cart", "car", "house", "fork.knife", "tshirt",
            "gamecontroller", "airplane", "gift", "heart", "book",
            "briefcase", "banknote", "creditcard", "phone", "tv",
            "bolt", "drop", "leaf", "pawprint", "figure.run",

            // Food and everyday shopping
            "basket", "bag", "storefront", "carrot", "fish", "cup.and.saucer",
            "mug", "wineglass", "birthday.cake", "takeoutbag.and.cup.and.straw",

            // Home, utilities and maintenance
            "building.2", "key", "sofa", "bed.double", "lamp.table", "lightbulb",
            "refrigerator", "washer", "oven", "flame", "wifi", "antenna.radiowaves.left.and.right",
            "wrench.and.screwdriver", "hammer", "paintbrush", "shippingbox",

            // Transport and travel
            "bus", "tram", "bicycle", "scooter", "fuelpump", "parkingsign.circle",
            "car.side", "ferry", "suitcase", "globe.europe.africa", "map",
            "location", "tent", "beach.umbrella", "mountain.2",

            // Health, personal care and family
            "cross.case", "pills", "bandage", "stethoscope", "heart.text.square",
            "eye", "eyeglasses", "scissors", "comb", "hands.sparkles",
            "person.2", "figure.and.child.holdinghands", "stroller", "dog", "cat",

            // Leisure, sport and education
            "ticket", "film", "music.note", "headphones", "camera", "paintpalette",
            "puzzlepiece", "soccerball", "basketball", "tennisball", "dumbbell",
            "figure.walk", "figure.hiking", "figure.pool.swim", "graduationcap",
            "books.vertical", "pencil", "backpack",

            // Technology, work and finances
            "iphone", "laptopcomputer", "desktopcomputer", "printer", "applewatch",
            "keyboard", "display", "building.columns", "wallet.pass", "dollarsign.circle",
            "eurosign.circle", "chart.line.uptrend.xyaxis", "chart.pie", "percent",
            "receipt", "doc.text", "checkmark.shield", "lock.shield", "arrow.triangle.2.circlepath",
            "calendar", "clock", "envelope", "tray", "archivebox", "star", "sparkles",
        ]
        var seen = Set<String>()
        return (base + FinanceCategory.defaultCategoryDefinitions.map(\.icon)).filter { seen.insert($0).inserted }
    }()
}

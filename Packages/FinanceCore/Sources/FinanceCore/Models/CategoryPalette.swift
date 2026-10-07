import Foundation

/// Forgia's own category colours: earthy mid-tones that read on both light and dark surfaces,
/// as an icon tint and as a 12–15% background wash. Hex strings, as stored on `Category.color`.
public enum CategoryPalette {
    public struct Swatch: Sendable, Identifiable {
        public let name: String
        public let hex: String
        public var id: String { hex }
    }

    public static let ottanio = "#2F7A72"
    public static let salvia = "#6E8F5A"
    public static let oliva = "#8C8A3A"
    public static let ocra = "#C28B2C"
    public static let albicocca = "#D9824A"
    public static let terracotta = "#BC5B40"
    public static let rosaAntico = "#BA5A72"
    public static let prugna = "#8E5A88"
    public static let malva = "#9A80B0"
    public static let indaco = "#5D64A8"
    public static let petrolio = "#3C7199"
    public static let ardesia = "#62798A"
    public static let cuoio = "#9C6C48"
    public static let tortora = "#8C7D6E"

    public static let swatches: [Swatch] = [
        .init(name: "Ottanio", hex: ottanio), .init(name: "Salvia", hex: salvia),
        .init(name: "Oliva", hex: oliva), .init(name: "Ocra", hex: ocra),
        .init(name: "Albicocca", hex: albicocca), .init(name: "Terracotta", hex: terracotta),
        .init(name: "Rosa antico", hex: rosaAntico), .init(name: "Prugna", hex: prugna),
        .init(name: "Malva", hex: malva), .init(name: "Indaco", hex: indaco),
        .init(name: "Petrolio", hex: petrolio), .init(name: "Ardesia", hex: ardesia),
        .init(name: "Cuoio", hex: cuoio), .init(name: "Tortora", hex: tortora),
    ]

    /// Used when a category has no colour.
    public static let fallback = ottanio

    /// Colours the app used to seed before this palette. A default category still wearing one of
    /// them was never recoloured by the user, so an upgrade may move it to the palette.
    static let legacyDefaultColors: Set<String> = [
        "#4CAF50", "#8BC34A", "#CDDC39", "#FFC107", "#2E7D32", "#388E3C", "#7CB342",
        "#F44336", "#2196F3", "#9C27B0", "#673AB7", "#E91E63", "#FF5722", "#795548",
        "#607D8B", "#FF4081", "#FF6F00", "#1976D2", "#FF9800", "#455A64", "#9E9E9E",
    ]
}

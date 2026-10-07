import Foundation

/// Shared account identity colours for account lists, charts and widget snapshots.
public enum AccountPalette {
    public struct Swatch: Sendable, Identifiable {
        public let name: String
        public let hex: String
        public var id: String { hex }
    }
    public static let ottanio = "#2F7A72"
    public static let petrolio = "#3C7199"
    public static let ocra = "#C28B2C"
    public static let prugna = "#8E5A88"
    public static let terracotta = "#BC5B40"
    public static let salvia = "#6E8F5A"
    public static let rosaAntico = "#BA5A72"
    public static let ardesia = "#62798A"
    public static let cuoio = "#9C6C48"
    public static let indaco = "#5D64A8"

    public static let swatches: [Swatch] = [
        .init(name: "Ottanio", hex: ottanio),
        .init(name: "Petrolio", hex: petrolio),
        .init(name: "Ocra", hex: ocra),
        .init(name: "Prugna", hex: prugna),
        .init(name: "Terracotta", hex: terracotta),
        .init(name: "Salvia", hex: salvia),
        .init(name: "Rosa antico", hex: rosaAntico),
        .init(name: "Ardesia", hex: ardesia),
        .init(name: "Cuoio", hex: cuoio),
        .init(name: "Indaco", hex: indaco),
    ]
    public static let fallback = ottanio
    /// Stored colours are exact user choices, including colours matching an old preset.
    public static func displayColor(stored: String?, id: UUID) -> String {
        if let stored, !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }
        // A deterministic UUID hash keeps colour stable across filters, renames and devices.
        let index = id.uuidString.utf8.reduce(0) { ($0 * 31 + Int($1)) % swatches.count }
        return swatches[index].hex
    }

    public static func suggestedColor(used: [String]) -> String {
        swatches.first { !used.contains($0.hex) }?.hex ?? fallback
    }
}

extension Conto {
    public var displayColorHex: String { AccountPalette.displayColor(stored: color, id: id) }
}

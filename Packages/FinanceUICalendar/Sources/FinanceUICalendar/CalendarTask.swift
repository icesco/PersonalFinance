import SwiftUI

/// Un singolo task/cura da mostrare in calendario.
/// Generico: il package non conosce nulla di `CareSchedule` o SwiftData.
public struct CalendarTask: Identifiable, Hashable, Sendable {
    public let id: String
    /// Chiave di categoria (es. `CareType.rawValue`). Usata per raggruppare in `CalendarDayTasks` e per il pallino colorato nella cella.
    public let categoryID: String
    /// Label leggibile della categoria (es. "Annaffia").
    public let categoryLabel: String
    /// Nome SF Symbol associato alla categoria.
    public let categoryIcon: String
    /// Colore della categoria (di solito da `CareType.color`).
    public let categoryColor: Color
    /// Titolo principale della riga nel dettaglio del giorno (es. nome pianta).
    public let title: String
    /// Sottotitolo opzionale (es. stanza, specie).
    public let subtitle: String?

    public init(
        id: String,
        categoryID: String,
        categoryLabel: String,
        categoryIcon: String,
        categoryColor: Color,
        title: String,
        subtitle: String? = nil
    ) {
        self.id = id
        self.categoryID = categoryID
        self.categoryLabel = categoryLabel
        self.categoryIcon = categoryIcon
        self.categoryColor = categoryColor
        self.title = title
        self.subtitle = subtitle
    }
}

/// Raggruppa i task di un giorno per categoria, mantenendo l'ordine di inserimento.
public struct CalendarDayTasks: Equatable, Sendable {
    public struct Group: Identifiable, Equatable, Sendable {
        public let id: String
        public let label: String
        public let icon: String
        public let color: Color
        public let tasks: [CalendarTask]
    }

    public let date: Date
    public let groups: [Group]

    public var isEmpty: Bool { groups.isEmpty }

    public init(date: Date, tasks: [CalendarTask]) {
        self.date = date
        var order: [String] = []
        var byCategory: [String: [CalendarTask]] = [:]
        var meta: [String: (label: String, icon: String, color: Color)] = [:]
        for t in tasks {
            if byCategory[t.categoryID] == nil {
                order.append(t.categoryID)
                meta[t.categoryID] = (t.categoryLabel, t.categoryIcon, t.categoryColor)
            }
            byCategory[t.categoryID, default: []].append(t)
        }
        self.groups = order.map { id in
            let m = meta[id]!
            return Group(id: id, label: m.label, icon: m.icon, color: m.color, tasks: byCategory[id] ?? [])
        }
    }
}

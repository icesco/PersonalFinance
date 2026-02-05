//
//  Extensions.swift
//  Personal Finance
//
//  Estensioni condivise per l'app
//

import SwiftUI
import UIKit

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    // MARK: - Color Components

    /// Get the RGBA components of the color
    var colorComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
    }

    // MARK: - Color Manipulation

    /// Lighten the color by reducing opacity
    func lighter(by percentage: CGFloat = 0.2) -> Color {
        return self.opacity(1 - percentage)
    }

    /// Darken the color by a percentage
    func darker(by percentage: CGFloat = 0.2) -> Color {
        let comp = self.colorComponents
        let darkerRed = max(0, comp.red * (1 - percentage))
        let darkerGreen = max(0, comp.green * (1 - percentage))
        let darkerBlue = max(0, comp.blue * (1 - percentage))
        return Color(red: darkerRed, green: darkerGreen, blue: darkerBlue, opacity: comp.alpha)
    }

    /// Mix this color with another color
    func mix(with color: Color, by percentage: CGFloat) -> Color {
        let selfComp = self.colorComponents
        let otherComp = color.colorComponents
        let newRed = selfComp.red * (1 - percentage) + otherComp.red * percentage
        let newGreen = selfComp.green * (1 - percentage) + otherComp.green * percentage
        let newBlue = selfComp.blue * (1 - percentage) + otherComp.blue * percentage
        let newAlpha = selfComp.alpha * (1 - percentage) + otherComp.alpha * percentage
        return Color(red: newRed, green: newGreen, blue: newBlue, opacity: newAlpha)
    }
}

// MARK: - Decimal Extension

extension Decimal {
    func abs() -> Decimal {
        return self < 0 ? -self : self
    }
}

// Custom abs function for Decimal
func abs(_ value: Decimal) -> Decimal {
    return value < 0 ? -value : value
}

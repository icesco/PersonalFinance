//
//  PlatformCompat.swift
//  Personal Finance
//
//  Cross-platform compatibility layer for iOS/macOS
//

import SwiftUI

// MARK: - macOS Color Compatibility

#if os(macOS)
import AppKit

extension NSColor {
    /// Maps iOS `UIColor.systemBackground` to macOS equivalent
    static var systemBackground: NSColor {
        .windowBackgroundColor
    }

    /// Maps iOS `UIColor.systemGroupedBackground` to macOS equivalent
    static var systemGroupedBackground: NSColor {
        .windowBackgroundColor
    }

    /// Maps iOS `UIColor.systemGray4` to macOS equivalent
    static var systemGray4: NSColor {
        .systemGray.withAlphaComponent(0.5)
    }

    /// Maps iOS `UIColor.systemGray5` to macOS equivalent
    static var systemGray5: NSColor {
        .systemGray.withAlphaComponent(0.35)
    }

    /// Maps iOS `UIColor.systemGray6` to macOS equivalent
    static var systemGray6: NSColor {
        .systemGray.withAlphaComponent(0.2)
    }

    /// Maps iOS `UIColor.secondarySystemBackground` to macOS equivalent
    static var secondarySystemBackground: NSColor {
        .controlBackgroundColor
    }

    /// Maps iOS `UIColor.secondarySystemGroupedBackground` to macOS equivalent
    static var secondarySystemGroupedBackground: NSColor {
        .controlBackgroundColor
    }

    /// Maps iOS `UIColor.tertiarySystemFill` to macOS equivalent
    static var tertiarySystemFill: NSColor {
        .quaternaryLabelColor
    }

    /// Maps iOS `UIColor.label` to macOS equivalent
    static var label: NSColor {
        .labelColor
    }
}
#endif

// MARK: - Platform Actions

enum PlatformActions {
    /// Opens the system settings/preferences app
    static func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:")!)
        #endif
    }
}

// MARK: - Cross-Platform ShareSheet

#if os(macOS)
import AppKit

struct ShareSheet: NSViewRepresentable {
    let items: [Any]

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Show the macOS sharing service picker anchored to a view
    static func show(items: [Any], from view: NSView) {
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}
#endif

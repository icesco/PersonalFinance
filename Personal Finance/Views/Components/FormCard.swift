//
//  FormCard.swift
//  Personal Finance
//
//  Building blocks of the card-style entry forms (quick entry, edit): rows with a tinted icon
//

import SwiftUI

/// A rounded surface grouping form rows, with an optional section title above it.
struct FormCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ForgiaPalette.mutedText)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0, content: content)
                .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        }
    }
}

/// One line of a `FormCard`: tinted icon, then whatever control the row holds.
struct FormRow<Content: View>: View {
    let icon: String
    var tint: Color = ForgiaPalette.canvas
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 14) {
            FormRowIcon(name: icon, tint: tint)
            content()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 62)
    }
}

struct FormRowIcon: View {
    let name: String
    let tint: Color

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(ForgiaPalette.accent)
            .frame(width: 38, height: 38)
            .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Caption over value, with a chevron: the label of a row that opens a picker.
struct FormSelectionLabel: View {
    let title: String
    let value: String
    var isPlaceholder = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(ForgiaPalette.mutedText)
                Text(value)
                    .font(.body)
                    .foregroundStyle(isPlaceholder ? ForgiaPalette.mutedText : Color.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ForgiaPalette.mutedText)
        }
        .contentShape(Rectangle())
    }
}

struct FormRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(ForgiaPalette.border)
            .frame(height: 1)
            .padding(.leading, 68)
            .padding(.trailing, 16)
    }
}

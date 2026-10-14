import SwiftUI
import FinanceCore

struct FormiColorOption: Identifiable {
    let name: String
    let hex: String
    var id: String { hex }
}

struct FormiColorPalette: Identifiable {
    let id: String
    let title: String
    let colors: [FormiColorOption]

    private static let categoryColors = CategoryPalette.swatches.map { FormiColorOption(name: $0.name, hex: $0.hex) }

    static let categories: [Self] = [
        .init(id: "natural", title: "Verdi e blu", colors: categoryColors.filter {
            [CategoryPalette.ottanio, CategoryPalette.salvia, CategoryPalette.oliva,
             CategoryPalette.petrolio, CategoryPalette.ardesia].contains($0.hex)
        }),
        .init(id: "warm", title: "Toni caldi", colors: categoryColors.filter {
            [CategoryPalette.ocra, CategoryPalette.albicocca, CategoryPalette.terracotta,
             CategoryPalette.rosaAntico, CategoryPalette.cuoio].contains($0.hex)
        }),
        .init(id: "soft", title: "Viola e neutri", colors: categoryColors.filter {
            [CategoryPalette.prugna, CategoryPalette.malva, CategoryPalette.indaco,
             CategoryPalette.tortora].contains($0.hex)
        })
    ]
}

struct FormiColorPicker: View {
    @Binding var selection: String
    var palettes: [FormiColorPalette] = FormiColorPalette.categories
    var previewIcon = "paintpalette"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedName: String {
        palettes.flatMap(\.colors).first { $0.hex.caseInsensitiveCompare(selection) == .orderedSame }?.name ?? "Colore attuale"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    FormCard {
                        HStack(spacing: 16) {
                            Image(systemName: previewIcon)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Color(hex: selection))
                                .frame(width: 56, height: 56)
                                .background(Color(hex: selection).opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Colore selezionato").font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                                Text(selectedName).font(.system(.title3, design: .serif, weight: .semibold))
                            }
                            Spacer(minLength: 0)
                        }.padding(18)
                    }
                    ForEach(palettes) { palette in
                        FormCard(title: palette.title) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 88 : 72), spacing: 12)], spacing: 16) {
                                ForEach(palette.colors) { swatch in
                                    let selected = swatch.hex.caseInsensitiveCompare(selection) == .orderedSame
                                    Button {
                                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { selection = swatch.hex }
                                    } label: {
                                        VStack(spacing: 6) {
                                            Circle().fill(Color(hex: swatch.hex))
                                                .frame(width: 52, height: 52)
                                                .overlay {
                                                    if selected {
                                                        Image(systemName: "checkmark").font(.body.weight(.bold)).foregroundStyle(.white)
                                                    }
                                                }
                                                .padding(6)
                                                .overlay { Circle().strokeBorder(selected ? ForgiaPalette.accent : .clear, lineWidth: 2) }
                                            Text(swatch.name).font(.caption).foregroundStyle(.primary)
                                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 88, alignment: .top)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(swatch.name)
                                    .accessibilityAddTraits(selected ? .isSelected : [])
                                    .accessibilityIdentifier("formi-color-\(swatch.name)")
                                }
                            }.padding(16)
                        }
                    }
                }.frame(maxWidth: 560).padding(20).frame(maxWidth: .infinity)
            }
            .themedBackground()
            .navigationTitle("Scegli colore")
            .toolbarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        }
        .tint(ForgiaPalette.accent)
        .modifier(FormiPickerPresentation())
    }
}

struct FormiIconPicker: View {
    @Binding var selection: String
    var icons: [String] = CategoryIconChoices.all
    var tint: Color = ForgiaPalette.accent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 12)], spacing: 12) {
                    ForEach(icons, id: \.self) { icon in
                        let selected = selection == icon
                        Button { selection = icon } label: {
                            Image(systemName: icon)
                                .font(.system(size: 23, weight: .medium))
                                .foregroundStyle(selected ? tint : Color.primary)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(selected ? tint.opacity(0.12) : ForgiaPalette.surface,
                                            in: RoundedRectangle(cornerRadius: 16))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(selected ? ForgiaPalette.accent : .clear, lineWidth: 2)
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(icon)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("formi-icon-\(icon)")
                    }
                }.frame(maxWidth: 560).padding(20).frame(maxWidth: .infinity)
            }
            .themedBackground()
            .navigationTitle("Scegli icona")
            .toolbarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        }
        .tint(ForgiaPalette.accent)
        .modifier(FormiPickerPresentation())
    }
}

struct FormiAppearanceFields: View {
    @Binding var icon: String
    @Binding var color: String
    @State private var picker: PickerKind?
    private enum PickerKind: String, Identifiable {
        case icon, color
        var id: String { rawValue }
    }
    private var colorName: String {
        CategoryPalette.swatches.first { $0.hex.caseInsensitiveCompare(color) == .orderedSame }?.name ?? "Colore attuale"
    }

    var body: some View {
        VStack(spacing: 0) {
            Button { picker = .icon } label: {
                FormRow(icon: icon, tint: Color(hex: color).opacity(0.14)) {
                    Text("Icona").foregroundStyle(.primary)
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(ForgiaPalette.mutedText)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("category-choose-icon")
            FormRowDivider()
            Button { picker = .color } label: {
                FormRow(icon: "paintpalette", tint: ForgiaPalette.sageSurface) {
                    Text("Colore").foregroundStyle(.primary)
                    Spacer(minLength: 12)
                    Circle().fill(Color(hex: color)).frame(width: 24, height: 24).accessibilityHidden(true)
                    Text(colorName).foregroundStyle(ForgiaPalette.mutedText)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(ForgiaPalette.mutedText)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("category-choose-color")
        }
        .sheet(item: $picker) { value in
            switch value {
            case .icon: FormiIconPicker(selection: $icon, tint: Color(hex: color))
            case .color: FormiColorPicker(selection: $color, previewIcon: icon)
            }
        }
    }
}

private struct FormiPickerPresentation: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.presentationBackground(ForgiaPalette.canvas).presentationDragIndicator(.visible)
        #else
        content.frame(minWidth: 420, idealWidth: 560, minHeight: 440, idealHeight: 640)
        #endif
    }
}

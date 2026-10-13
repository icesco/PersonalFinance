import SwiftUI

/// Dismisses the sheet in which Home shows a tab's root. Equal per section, so a new
/// closure on every parent update does not invalidate the screens that read it.
struct ClosePresentedSectionAction: Equatable {
    let section: AppTab
    let action: () -> Void
    func callAsFunction() { action() }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.section == rhs.section }
}

extension EnvironmentValues {
    /// Set while a tab's root is shown as a sheet from Home.
    @Entry var closePresentedSection: ClosePresentedSectionAction? = nil
}

/// The Home screen's top bar for modal screens: serif title on the leading edge and a glass
/// close button, while the screen's own toolbar actions keep their place.
private struct ModalChrome: ViewModifier {
    let title: String
    let closeLabel: String
    let close: (() -> Void)?
    var showsTitle = true

    func body(content: Content) -> some View {
        #if os(iOS)
        Group {
            if showsTitle {
                content.toolbar(removing: .title)
            } else {
                content
            }
        }
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                if showsTitle {
                ToolbarItem(placement: .topBarLeading) {
                    Text(title)
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityAddTraits(.isHeader)
                }
                .sharedBackgroundVisibility(.hidden)
                }
                if let close {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(closeLabel, systemImage: "xmark", action: close)
                    }
                }
            }
        #else
        content.toolbar {
            if let close {
                FinanceDismissToolbar { Button(closeLabel, action: close) }
            }
        }
        #endif
    }
}

/// Applies the modal chrome only when the root is presented as a sheet from Home,
/// leaving the same screen untouched when it lives in a tab or the sidebar.
private struct SectionSheetChrome: ViewModifier {
    let title: String
    var showsTitle = true
    @Environment(\.closePresentedSection) private var close

    func body(content: Content) -> some View {
        if let close {
            content.modifier(ModalChrome(title: title, closeLabel: "Chiudi", close: { close() }, showsTitle: showsTitle))
        } else {
            content
        }
    }
}

extension View {
    /// Home-style chrome for a screen presented modally; `closeLabel` stays the accessible name of the button.
    func modalChrome(_ title: String, closeLabel: String = "Chiudi", close: (() -> Void)?) -> some View {
        modifier(ModalChrome(title: title, closeLabel: closeLabel, close: close))
    }

    /// Home-style chrome for a tab root, active only when Home presents it as a sheet.
    func sectionSheetChrome(_ title: String, showsTitle: Bool = true) -> some View {
        modifier(SectionSheetChrome(title: title, showsTitle: showsTitle))
    }
}

import CoreGraphics

/// Horizontal metrics for the panel, in one place.
///
/// Each band used to carry its own number: group labels landed at 8pt, the header and quick
/// input at 14pt, and the todo rows at 26pt because the list's built-in margin stacked on top
/// of `listRowInsets`. Nothing lined up, so the rows looked inset from both panel edges while
/// the labels hugged the left one. Everything now hangs off `contentInset`, with the glyph
/// column and the text column shared by the list, the quick input and history.
enum PanelLayout {
    /// The panel's content rail: header title, group labels, glyphs, tab bar, toast.
    static let contentInset: CGFloat = 14

    /// Width of the leading glyph column (completion circle, plus button, history checkmark).
    static let glyphWidth: CGFloat = 16
    /// Gap between that glyph column and the text.
    static let glyphTextGap: CGFloat = 10
    /// Where item text starts, measured from the panel edge. Shared by rows and the quick input.
    static var textInset: CGFloat { contentInset + glyphWidth + glyphTextGap }

    /// A plain-style macOS `List` insets its content by itself and ignores
    /// `.contentMargins(.horizontal, 0)`; these are the amounts it applies (measured at 2× on
    /// macOS 26, stable since macOS 14). Row insets are derived from them so a row can be put
    /// exactly on `contentInset` instead of wherever the list happens to start.
    static let listLeadingMargin: CGFloat = 8
    static let listTrailingMargin: CGFloat = 9.5

    static var rowInsetLeading: CGFloat { contentInset - listLeadingMargin }
    static var rowInsetTrailing: CGFloat { contentInset - listTrailingMargin }

    /// How far the hover highlight bleeds past the text rail, so the pill reads as a band
    /// rather than a box drawn tight around the glyph.
    static let highlightBleed: CGFloat = 6

    /// Vertical padding inside a row. With the 1pt list row insets and a 12.5pt line this
    /// gives a 32pt pitch — the density the list had before the rails were unified, so
    /// aligning the columns did not also change how much fits on screen.
    static let rowVerticalPadding: CGFloat = 7

    /// Space above a group label. Deliberately larger than the label-to-row gap, so a group
    /// reads as belonging to the rows below it.
    static let sectionTopPadding: CGFloat = 14
    static let sectionBottomPadding: CGFloat = 3
}
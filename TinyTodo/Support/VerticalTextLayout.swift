import CoreGraphics

/// Vertical centring for a single line inside a fixed-height text container.
///
/// The placeholder and the typed text must share one baseline, so both are drawn by the same
/// `NSTextView` using this inset instead of being positioned by two different layout systems.
enum VerticalTextLayout {
    /// Returns the top inset that centres a line of `lineHeight` inside `containerHeight`.
    static func insetY(containerHeight: CGFloat, lineHeight: CGFloat) -> CGFloat {
        guard containerHeight > 0, lineHeight > 0 else { return 0 }
        return max(0, ((containerHeight - lineHeight) / 2).rounded())
    }
}

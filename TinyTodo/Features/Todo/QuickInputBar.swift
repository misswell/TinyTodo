import SwiftUI

struct QuickInputBar: View {
    @Binding var text: String
    var focusToken: Int
    var onSubmit: (String) -> Void
    var onSubmitLines: ([String]) -> Void
    var onEscape: () -> Void

    static let placeholder = "添加一个待办，按 Enter 保存…"
    static let fieldHeight: CGFloat = QuickInputField.singleLineHeight

    @State private var fieldHeight: CGFloat = QuickInputField.singleLineHeight

    var body: some View {
        // Top-aligned so the icon stays beside the first line when the field wraps.
        HStack(alignment: .top, spacing: PanelLayout.glyphTextGap) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(Color.accentColor.opacity(0.85))
                .frame(width: PanelLayout.glyphWidth, height: QuickInputField.lineHeight, alignment: .center)
                .padding(.top, 2)

            QuickInputField(
                text: $text,
                focusToken: focusToken,
                placeholder: Self.placeholder,
                onHeightChange: { height in
                    let delta = height - fieldHeight
                    withAnimation(.easeOut(duration: 0.12)) {
                        fieldHeight = height
                    }
                    // Grow the panel by the same amount so the list keeps its room instead of
                    // pushing the tab bar out of the window.
                    if abs(delta) > 0.5 {
                        QuickInputHeightRelay.post(delta: delta)
                    }
                },
                onSubmit: onSubmit,
                onPasteLines: onSubmitLines,
                onEscape: onEscape
            )
            .frame(maxWidth: .infinity, minHeight: fieldHeight, maxHeight: fieldHeight)
            .accessibilityIdentifier("quick.input")
        }
        .padding(.horizontal, PanelLayout.contentInset)
        .padding(.top, 8)
        .padding(.bottom, 9)
        .background(Color.primary.opacity(0.035))
    }
}

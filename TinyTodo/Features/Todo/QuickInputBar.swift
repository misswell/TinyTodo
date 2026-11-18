import SwiftUI

struct QuickInputBar: View {
    @Binding var text: String
    var focusToken: Int
    var onSubmit: (String) -> Void
    var onSubmitLines: ([String]) -> Void
    var onEscape: () -> Void

    static let placeholder = "添加一个待办，按 Enter 保存…"
    static let fieldHeight: CGFloat = 22

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(Color.accentColor.opacity(0.85))

            QuickInputField(
                text: $text,
                focusToken: focusToken,
                placeholder: Self.placeholder,
                onSubmit: onSubmit,
                onPasteLines: onSubmitLines,
                onEscape: onEscape
            )
            .frame(maxWidth: .infinity, minHeight: Self.fieldHeight, maxHeight: Self.fieldHeight)
            .accessibilityIdentifier("quick.input")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.035))
    }
}

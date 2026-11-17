import SwiftUI

struct QuickInputBar: View {
    @Binding var text: String
    var focusToken: Int
    var onSubmit: (String) -> Void
    var onSubmitLines: ([String]) -> Void
    var onEscape: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(Color.accentColor.opacity(0.85))

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("添加一个待办，按 Enter 保存…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
                QuickInputField(
                    text: $text,
                    focusToken: focusToken,
                    onSubmit: onSubmit,
                    onPasteLines: onSubmitLines,
                    onEscape: onEscape
                )
                .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20)
                .accessibilityIdentifier("quick.input")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.035))
    }
}

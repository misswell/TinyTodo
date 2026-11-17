import SwiftUI

struct HistoryDateGroupView: View {
    let section: HistoryDaySection
    @Environment(HistoryViewModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(section.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(section.count) 项")
                    .font(.system(size: 9.5).monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 2)

            ForEach(section.items) { item in
                HistoryRowView(item: item)
            }
        }
    }
}

struct HistoryRowView: View {
    let item: TodoItem
    @Environment(HistoryViewModel.self) private var model
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.accentColor.opacity(0.65))

            Text(item.title)
                .font(.system(size: 12))
                .strikethrough(true, color: .secondary.opacity(0.7))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)

            if let completedAt = item.completedAt {
                Text(Self.timeString(completedAt))
                    .font(.system(size: 9.5).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.045) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("恢复到待办") { model.restore(item) }
            Button("复制文字") { model.copyTitle(item) }
            Divider()
            Button("删除记录", role: .destructive) { model.delete(item) }
        }
        .accessibilityIdentifier("history.row")
        .accessibilityLabel(item.title)
    }

    static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = .autoupdatingCurrent
        return formatter.string(from: date)
    }
}

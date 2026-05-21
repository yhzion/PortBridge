import SwiftUI

struct AllServersSectionHeader: View {
    let count: Int
    let allExpanded: Bool
    let onToggleAll: () -> Void

    var body: some View {
        HStack {
            Text(verbatim: "모든 서버 · \(count)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
            Spacer()
            Button(allExpanded ? "모두 접기" : "모두 펼치기", action: onToggleAll)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.caption)
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .help(allExpanded ? "모두 접기 (⌘⇧E)" : "모두 펼치기 (⌘⇧E)")
                .accessibilityLabel(allExpanded ? "모든 서버 접기" : "모든 서버 펼치기")
        }
    }
}

#Preview("Expanded · 3 servers") {
    AllServersSectionHeader(count: 3, allExpanded: true, onToggleAll: {})
        .padding()
        .frame(width: 360)
}

#Preview("Collapsed · 0 servers") {
    AllServersSectionHeader(count: 0, allExpanded: false, onToggleAll: {})
        .padding()
        .frame(width: 360)
}

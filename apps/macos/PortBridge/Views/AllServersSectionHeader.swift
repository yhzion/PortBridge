import SwiftUI

struct AllServersSectionHeader: View {
    let count: Int
    let allExpanded: Bool
    let onToggleAll: () -> Void

    var body: some View {
        HStack {
            Text(String(localized: "allServers.title", defaultValue: "모든 서버 · \(count)"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
            Spacer()
            Button(
                allExpanded ? String(localized: "allServers.collapseAll", defaultValue: "모두 접기") : String(
                    localized: "allServers.expandAll",
                    defaultValue: "모두 펼치기"
                ),
                action: onToggleAll
            )
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .font(.caption)
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .help(allExpanded ? String(localized: "allServers.collapseAll.help", defaultValue: "모두 접기 (⌘⇧E)") : String(
                localized: "allServers.expandAll.help",
                defaultValue: "모두 펼치기 (⌘⇧E)"
            ))
            .accessibilityLabel(allExpanded
                ? String(localized: "allServers.collapseAll.a11y", defaultValue: "모든 서버 접기")
                : String(localized: "allServers.expandAll.a11y", defaultValue: "모든 서버 펼치기"))
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

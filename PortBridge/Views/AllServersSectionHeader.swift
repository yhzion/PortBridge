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
                .foregroundStyle(.primary)
            Spacer()
            Button(allExpanded ? "모두 접기" : "모두 펼치기", action: onToggleAll)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}

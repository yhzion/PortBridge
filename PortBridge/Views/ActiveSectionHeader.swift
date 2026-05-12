import SwiftUI

struct ActiveSectionHeader: View {
    let count: Int
    let onStopAll: () -> Void

    var body: some View {
        HStack {
            Text(verbatim: "포워딩 중 · \(count)")
            Spacer()
            Button("모두 끄기", action: onStopAll)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}

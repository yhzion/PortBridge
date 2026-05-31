import SwiftUI

struct ActiveSectionHeader: View {
    let count: Int
    let onStopAll: () -> Void

    private var stopAccessibility: String {
        String(localized: "active.dismissAll", defaultValue: "활성 포워딩 \(count)개 모두 끄기")
    }

    var body: some View {
        HStack {
            Text(String(localized: "active.title", defaultValue: "포워딩 중 · \(count)"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
            Spacer()
            Button(String(localized: "active.dismissAll.label", defaultValue: "모두 끄기"), action: onStopAll)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.caption)
                .accessibilityLabel(stopAccessibility)
        }
    }
}

#Preview("2 active forwardings") {
    ActiveSectionHeader(count: 2, onStopAll: {})
        .padding()
        .frame(width: 360)
}

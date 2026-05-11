import SwiftUI

struct ForwardingRowView: View {
    let port: RemotePort
    let forwarding: Forwarding?
    let onToggle: () -> Void

    private var statusIcon: String {
        switch forwarding?.state {
        case .active: return "🟢"
        case .starting: return "🟡"
        case .error: return "🔴"
        case .idle, .none: return "⚪️"
        }
    }

    var body: some View {
        HStack {
            Text(statusIcon)
            VStack(alignment: .leading) {
                Text("\(port.port)")
                    .font(.system(.body, design: .monospaced))
                Text("\(port.address) · \(port.processName ?? "-")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if case .error(let msg) = forwarding?.state {
                Text(msg.prefix(80))
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Toggle("", isOn: Binding(
                get: { forwarding?.state == .active || forwarding?.state == .starting },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

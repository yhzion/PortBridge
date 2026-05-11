import SwiftUI

struct ForwardingRowView: View {
    let port: RemotePort
    let forwarding: Forwarding?
    let onToggle: () -> Void

    private var addressLabel: String {
        switch port.address {
        case "0.0.0.0", "::": return "모든 인터페이스에서 수신"
        case "127.0.0.1", "::1": return "로컬에서만 수신"
        default: return "수신 주소 \(port.address)"
        }
    }

    private var stateLabel: String? {
        switch forwarding?.state {
        case .starting:
            return "연결 중…"
        case .active:
            if let local = forwarding?.localPort {
                return "내 PC의 localhost:\(local) → 리모트 \(port.port) 로 포워딩 중"
            }
            return "포워딩 중"
        case .error:
            return "포워딩 실패"
        case .idle, .none:
            return nil
        }
    }

    private var isErrorState: Bool {
        if case .error = forwarding?.state { return true }
        return false
    }

    private var statusSymbol: (name: String, color: Color) {
        switch forwarding?.state {
        case .active:        return ("circle.fill", .green)
        case .starting:      return ("circle.dotted", .orange)
        case .error:         return ("exclamationmark.triangle.fill", .red)
        case .idle, .none:   return ("circle", .secondary)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: statusSymbol.name)
                .foregroundStyle(statusSymbol.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: "포트 " + String(port.port))
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                    if let proc = port.processName {
                        Text(verbatim: proc)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }
                Text(stateLabel ?? addressLabel)
                    .font(.caption)
                    .foregroundStyle(isErrorState ? .red : .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if case .error(let msg) = forwarding?.state {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .help(String(msg))
            }

            Toggle("", isOn: Binding(
                get: { forwarding?.state == .active || forwarding?.state == .starting },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .help(forwarding?.state == .active ? "포워딩 끄기" : "포워딩 켜기")
        }
        .padding(.vertical, 4)
    }
}

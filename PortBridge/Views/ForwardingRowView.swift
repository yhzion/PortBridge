import SwiftUI
import AppKit

struct ForwardingRowView: View {
    let port: RemotePort
    let forwarding: Forwarding?
    let onToggle: () -> Void

    private var isStarting: Bool {
        forwarding?.state == .starting
    }

    private var isErrorState: Bool {
        if case .error = forwarding?.state { return true }
        return false
    }

    private var statusSymbol: (name: String, color: Color) {
        switch forwarding?.state {
        case .active:        return ("circle.fill", .green)
        case .error:         return ("exclamationmark.triangle.fill", .red)
        case .starting, .idle, .none: return ("circle", .secondary)
        }
    }

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
            return "포워딩 연결 중…"
        case .active:
            if let local = forwarding?.localPort {
                return "내 PC의 localhost:\(local) → 리모트 \(port.port) 로 포워딩 중"
            }
            return "포워딩 중"
        case .error:
            return "포워딩 실패 — 클릭해 다시 시도"
        case .idle, .none:
            return nil
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            statusIndicator
                .frame(width: 18, height: 18)

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

            if forwarding?.state == .active, let local = forwarding?.localPort {
                OpenInBrowserButton(localPort: local)
            }

            if case .error(let msg) = forwarding?.state {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .help(String(msg))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isStarting else { return }
            onToggle()
        }
        .help(forwarding?.state == .active ? "클릭해 포워딩 끄기" : "클릭해 포워딩 켜기")
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if isStarting {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: statusSymbol.name)
                .foregroundStyle(statusSymbol.color)
        }
    }
}

private struct OpenInBrowserButton: View {
    let localPort: Int
    @State private var isHovering = false
    @State private var isPressed = false

    private var url: URL? { URL(string: "http://localhost:\(localPort)") }

    var body: some View {
        Button {
            if let url { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.right.square")
                    .imageScale(.medium)
                Text("열기")
                    .font(.caption)
            }
            .foregroundStyle(.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(backgroundOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(isHovering ? 0.35 : 0.18), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.08), value: isPressed)
        .help("기본 브라우저로 http://localhost:\(localPort) 열기")
        .accessibilityLabel("브라우저에서 localhost 포트 \(localPort) 열기")
    }

    private var backgroundOpacity: Double {
        if isPressed { return 0.25 }
        if isHovering { return 0.15 }
        return 0.06
    }
}

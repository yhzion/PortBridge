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

    private var addressMeaning: String {
        switch port.address {
        case "0.0.0.0", "::": return "모든 인터페이스"
        case "127.0.0.1", "::1": return "로컬 전용"
        default: return port.address
        }
    }

    private var stateLabel: String? {
        let server = forwarding?.serverDisplayName
        let serverPrefix = server.map { "\($0) · " } ?? ""
        switch forwarding?.state {
        case .starting:
            return "\(serverPrefix)포워딩 연결 중…"
        case .active:
            if let local = forwarding?.localPort {
                return "\(serverPrefix):\(local) → 리모트 :\(port.port) 포워딩 중"
            }
            return "\(serverPrefix)포워딩 중"
        case .error:
            return "\(serverPrefix)포워딩 실패 — 클릭해 다시 시도"
        case .idle, .none:
            return nil
        }
    }

    @State private var isRowHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            statusIndicator
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                primaryLine
                secondaryLine
            }

            Spacer(minLength: 4)

            if forwarding?.state == .active, let local = forwarding?.localPort, isRowHovering {
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
        .onHover { isRowHovering = $0 }
        .onTapGesture {
            guard !isStarting else { return }
            onToggle()
        }
        .help(forwarding?.state == .active ? "클릭해 포워딩 끄기" : "클릭해 포워딩 켜기")
    }

    @ViewBuilder
    private var primaryLine: some View {
        if let proc = port.processName, !proc.isEmpty {
            Text(verbatim: proc)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text("열린 포트")
                .font(.headline)
                .fontWeight(.regular)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var secondaryLine: some View {
        if let label = stateLabel {
            Text(label)
                .font(.caption)
                .foregroundStyle(isErrorState ? .red : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            HStack(spacing: 6) {
                Text(verbatim: ":\(port.port)")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(addressMeaning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
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
                    .imageScale(.small)
                Text("브라우저에서 열기")
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
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.easeOut(duration: 0.08), value: isHovering)
        .animation(.easeOut(duration: 0.08), value: isPressed)
        .help("기본 브라우저로 http://localhost:\(localPort) 열기")
    }

    private var backgroundOpacity: Double {
        if isPressed { return 0.25 }
        if isHovering { return 0.15 }
        return 0.06
    }
}

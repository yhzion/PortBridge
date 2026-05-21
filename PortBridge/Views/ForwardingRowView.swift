import SwiftUI
import AppKit

struct ForwardingRowView: View {
    let port: RemotePort
    let forwarding: Forwarding?
    let serverDisplayName: String?
    let onToggle: () -> Void
    let isFavorite: Bool
    let onFavoriteToggle: () -> Void

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

    private var isActive: Bool {
        forwarding?.state == .active
    }

    private var showPortColumn: Bool {
        switch forwarding?.state {
        case .active, .error, .idle, .none: return true
        default: return false
        }
    }

    private var stateSubtitle: String? {
        let serverPrefix = serverDisplayName.map { "\($0) · " } ?? ""
        switch forwarding?.state {
        case .starting:
            return "\(serverPrefix)포워딩 연결 중…"
        case .active:
            if let local = forwarding?.localPort {
                return "→ :\(local) 포워딩 중"
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
            Button(action: onFavoriteToggle) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? Color.accentColor : Color.secondary)
                    .imageScale(.medium)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "즐겨찾기 해제" : "즐겨찾기 추가")
            .help(isFavorite ? "즐겨찾기에서 제거" : "즐겨찾기에 추가")

            statusIndicator
                .frame(width: 18, height: 18)

            if showPortColumn {
                Text(verbatim: ":\(port.port)")
                    .font(.system(.body, design: .monospaced).bold())
                    .monospacedDigit()
                    .foregroundStyle(isErrorState ? .red : isActive ? .green : .primary)
                    .frame(minWidth: 48, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(rightPrimary)
                    .font(.caption)
                    .foregroundStyle(rightPrimaryColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let secondary = rightSecondary {
                    Text(secondary)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if isActive, let local = forwarding?.localPort, isRowHovering {
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(forwarding?.state == .active ? "이중 탭하여 포워딩 끄기" : "이중 탭하여 포워딩 켜기")
        .accessibilityAddTraits(.isButton)
    }

    private var rightPrimary: String {
        if let stateSubtitle { return stateSubtitle }
        return port.scopeLabel
    }

    private var rightPrimaryColor: Color {
        if isErrorState { return .red }
        if isActive { return .green }
        return .secondary
    }

    private var rightSecondary: String? {
        guard stateSubtitle == nil, let name = port.processName, !name.isEmpty else { return nil }
        return name
    }

    private var accessibilityLabel: String {
        if let stateSubtitle {
            let server = serverDisplayName.map { "\($0) · " } ?? ""
            return ":\(port.port) \(server)\(stateSubtitle)"
        }
        return port.displayLine
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
    private var helpText: String { "기본 브라우저로 http://localhost:\(localPort) 열기" }

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
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isHovering ? Color.PB.accentStrokeHover : Color.PB.accentStrokeSubtle, lineWidth: 1)
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
        .help(helpText)
    }

    private var backgroundFill: Color {
        if isPressed { return Color.PB.accentBgPressed }
        if isHovering { return Color.PB.accentBgHover }
        return Color.PB.accentBgIdle
    }
}

#Preview("Idle · 비활성 포트") {
    ForwardingRowView(
        port: RemotePort(port: 8080, address: "0.0.0.0", processName: "nginx"),
        forwarding: nil,
        serverDisplayName: nil,
        onToggle: {},
        isFavorite: false,
        onFavoriteToggle: {}
    )
    .padding()
    .frame(width: 420)
}

#Preview("Starting") {
    ForwardingRowView(
        port: RemotePort(port: 5432, address: "127.0.0.1", processName: "postgres"),
        forwarding: Forwarding(serverId: UUID(), remotePort: 5432, localPort: 5432, state: .starting),
        serverDisplayName: "db-01",
        onToggle: {},
        isFavorite: false,
        onFavoriteToggle: {}
    )
    .padding()
    .frame(width: 420)
}

#Preview("Active") {
    ForwardingRowView(
        port: RemotePort(port: 6443, address: "0.0.0.0", processName: nil),
        forwarding: Forwarding(serverId: UUID(), remotePort: 6443, localPort: 6443, state: .active),
        serverDisplayName: "k8s-master",
        onToggle: {},
        isFavorite: true,
        onFavoriteToggle: {}
    )
    .padding()
    .frame(width: 420)
}

#Preview("Error") {
    ForwardingRowView(
        port: RemotePort(port: 3389, address: "0.0.0.0", processName: "rdp"),
        forwarding: Forwarding(serverId: UUID(), remotePort: 3389, localPort: 3389, state: .error("connection refused")),
        serverDisplayName: "win-vm",
        onToggle: {},
        isFavorite: false,
        onFavoriteToggle: {}
    )
    .padding()
    .frame(width: 420)
}

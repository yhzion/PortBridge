import AppKit
import SwiftUI

struct ForwardingRowView: View {
    let display: ForwardingDisplay
    let onToggle: () -> Void
    let isFavorite: Bool
    let onFavoriteToggle: () -> Void

    private var isStarting: Bool {
        display.status == .starting
    }

    private var isActive: Bool {
        display.status == .active
    }

    private var isErrorState: Bool {
        display.status == .error
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
            .accessibilityLabel(isFavorite
                ? String(localized: "forwarding.row.favorite.a11yRemove", defaultValue: "즐겨찾기 해제")
                : String(localized: "forwarding.row.favorite.a11yAdd", defaultValue: "즐겨찾기 추가"))
            .help(isFavorite
                ? String(localized: "forwarding.row.favorite.helpRemove", defaultValue: "즐겨찾기에서 제거")
                : String(localized: "forwarding.row.favorite.helpAdd", defaultValue: "즐겨찾기에 추가"))

            Button(action: onToggle) {
                HStack(alignment: .center, spacing: 10) {
                    statusIndicator
                        .frame(width: 18, height: 18)

                    HStack(spacing: 0) {
                        Text(display.host)
                            .truncationMode(.middle)
                            .lineLimit(1)
                            .layoutPriority(1)
                        Text(display.suffix)
                            .lineLimit(1)
                            .layoutPriority(2)
                    }
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isStarting)
            .help(isActive
                ? String(localized: "forwarding.row.toggle.helpStop", defaultValue: "클릭해 포워딩 끄기")
                : String(localized: "forwarding.row.toggle.helpStart", defaultValue: "클릭해 포워딩 켜기"))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(display.accessibilityText)
            .accessibilityHint(isActive
                ? String(localized: "forwarding.row.toggle.a11yHintStop", defaultValue: "이중 탭하여 포워딩 끄기")
                : String(localized: "forwarding.row.toggle.a11yHintStart", defaultValue: "이중 탭하여 포워딩 켜기"))

            if isActive, let local = display.localPort {
                OpenInBrowserButton(localPort: local)
            }

            if isErrorState, let message = display.errorMessage {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .help(message)
            }
        }
        .padding(.vertical, PBLayout.Space.s1)
        .onHover { isRowHovering = $0 }
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

    private var statusSymbol: (name: String, color: Color) {
        switch display.status {
        case .active: return ("circle.fill", .green)
        case .error: return ("exclamationmark.triangle.fill", .red)
        case .starting, .inactive: return ("circle", .secondary)
        }
    }
}

private struct OpenInBrowserButton: View {
    let localPort: Int
    @State private var isHovering = false
    @State private var isPressed = false

    private var url: URL? {
        URL(string: "http://localhost:\(localPort)")
    }

    private var helpText: String {
        String(localized: "forwarding.row.openInBrowser.help", defaultValue: "기본 브라우저로 http://localhost:\(localPort) 열기")
    }

    var body: some View {
        Button {
            if let url { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: PBLayout.Space.s1) {
                Image(systemName: "arrow.up.right.square")
                    .imageScale(.small)
                Text(String(localized: "forwarding.row.openInBrowser.label", defaultValue: "브라우저에서 열기"))
                    .font(.caption)
            }
            .foregroundStyle(.tint)
            .padding(.horizontal, PBLayout.Space.s2)
            .padding(.vertical, PBLayout.Space.s1)
            .background(
                RoundedRectangle(cornerRadius: PBLayout.Radius.sm, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PBLayout.Radius.sm, style: .continuous)
                    .strokeBorder(isHovering ? Color.PB.accentStrokeHover : Color.PB.accentStrokeSubtle, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: PBLayout.Radius.sm, style: .continuous))
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

#Preview("Inactive · 비활성 포트") {
    ForwardingRowView(
        display: .inactive(host: "myserver (1.2.3.4)", remotePort: 8080, processName: "nginx"),
        onToggle: {},
        isFavorite: false,
        onFavoriteToggle: {}
    )
    .padding()
    .frame(width: 420)
}

#Preview("Starting") {
    ForwardingRowView(
        display: .starting(host: "db-01 (10.0.0.1)", remotePort: 5432, processName: "postgres"),
        onToggle: {},
        isFavorite: false,
        onFavoriteToggle: {}
    )
    .padding()
    .frame(width: 420)
}

#Preview("Active") {
    ForwardingRowView(
        display: .active(host: "k8s-master (10.0.0.2)", remotePort: 6443, localPort: 6443, processName: nil),
        onToggle: {},
        isFavorite: true,
        onFavoriteToggle: {}
    )
    .padding()
    .frame(width: 420)
}

#Preview("Error") {
    ForwardingRowView(
        display: .error(host: "win-vm (10.0.0.3)", remotePort: 3389, message: "connection refused", processName: "rdp"),
        onToggle: {},
        isFavorite: false,
        onFavoriteToggle: {}
    )
    .padding()
    .frame(width: 420)
}

// PortBridge/Views/ServerSectionView.swift
import SwiftUI
import AppKit

struct ServerSectionView: View {
    let section: ServerSectionViewModel
    let activeForwardings: [Forwarding]
    let matches: (RemotePort) -> Bool
    let onToggle: (RemotePort) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var activeCount: Int {
        activeForwardings.filter { $0.serverId == section.server.id }.count
    }

    private var inactivePorts: [RemotePort] {
        let activeNums = Set(
            activeForwardings
                .filter { $0.serverId == section.server.id }
                .map { $0.remotePort }
        )
        return section.ports.filter { !activeNums.contains($0.port) && matches($0) }
    }

    var body: some View {
        sectionHeader
        if section.isExpanded {
            sectionContent
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section.scanState {
        case .idle:
            Text("↻ 버튼을 눌러 포트를 스캔하세요")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)

        case .scanning:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("스캔 중…").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

        case .loaded where inactivePorts.isEmpty:
            Text("포워딩되지 않은 포트 없음")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)

        case .loaded:
            ForEach(inactivePorts) { port in
                ForwardingRowView(port: port, forwarding: nil, onToggle: { onToggle(port) })
            }

        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.vertical, 4)

        case .authFailed(let cmd):
            AuthFailedView(copyCommand: cmd) { Task { await section.scan() } }
        }
    }

    private var primaryLabel: String {
        section.server.name ?? section.server.host
    }

    private var secondaryLabel: String {
        let target = section.server.sshTarget
        return section.server.port == 22 ? target : "\(target):\(section.server.port)"
    }

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    section.toggleExpanded()
                }
            } label: {
                Image(systemName: section.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)

            ServerMonogram(server: section.server)

            VStack(alignment: .leading, spacing: 1) {
                Text(primaryLabel)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(secondaryLabel)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if activeCount > 0 {
                Text("\(activeCount)")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                    .help("이 서버에서 포워딩 중인 포트 수")
            }

            if case .scanning = section.scanState {
                ProgressView().controlSize(.small)
            } else {
                Button { Task { await section.scan() } } label: {
                    Image(systemName: "arrow.clockwise").font(.body).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("\(primaryLabel) 포트 재스캔")
            }

            Menu {
                Button("편집…", action: onEdit)
                Divider()
                Button("삭제", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis").font(.body).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20)
        }
        .padding(.vertical, 6)
    }
}

private struct ServerMonogram: View {
    let server: Server

    private var initial: String {
        let source = server.name ?? server.host
        guard let first = source.first else { return "?" }
        return String(first).uppercased()
    }

    /// Deterministic hue from host bytes — Swift's String.hashValue is randomized
    /// per process, so we use a stable UTF-8 byte sum instead.
    private var hue: Double {
        let sum = server.host.utf8.reduce(0) { $0 + Int($1) }
        return Double(sum % 360) / 360.0
    }

    var body: some View {
        let tint = Color(hue: hue, saturation: 0.55, brightness: 0.85)
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tint.opacity(0.18))
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(tint.opacity(0.40), lineWidth: 0.5)
            Text(initial)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(width: 24, height: 24)
    }
}

private struct AuthFailedView: View {
    let copyCommand: String
    let onRetry: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("SSH 키 인증 실패", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
            HStack(spacing: 8) {
                Text(verbatim: copyCommand)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button(copied ? "복사됨 ✓" : "복사") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(copyCommand, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        copied = false
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(copied ? Color.green : Color.accentColor)
            }
        }
        .padding(.vertical, 4)
    }
}

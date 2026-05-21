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
        if section.isExpanded && !isOffline {
            sectionContent
        }
    }

    private var isOffline: Bool {
        if case .offline = section.scanState { return true }
        return false
    }

    private var statusDot: ServerStatusDot {
        switch section.scanState {
        case .offline(let isRetrying): return .offline(pulse: isRetrying)
        case .toolMissing, .authFailed: return .warning
        case .loaded: return .online
        default: return .none
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

        case .offline:
            EmptyView()   // 안전망 — body는 isOffline 분기로 이미 미렌더되지만 switch exhaustiveness 위해 유지

        case .toolMissing:
            ToolInstallGuideView()

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

    private func toggleExpandedAnimated() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            section.toggleExpanded()
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            if !isOffline {
                Button(action: toggleExpandedAnimated) {
                    Image(systemName: section.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                        .transaction { $0.animation = nil }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.isExpanded ? "접기" : "펼치기")
            } else {
                // 12px 자리 비움 — 다른 행과 가로 정렬 유지
                Color.clear.frame(width: 12, height: 12)
            }

            ServerMonogram(server: section.server, status: statusDot, dimmed: isOffline)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(primaryLabel)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isOffline ? .secondary : .primary)
                    .lineLimit(1)
                Text(secondaryLabel)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if activeCount > 0 && !isOffline {
                Text("\(activeCount)")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.PB.accentBadgeBg, in: Capsule())
                    .help("이 서버에서 포워딩 중인 포트 수")
                    .accessibilityLabel("포워딩 중인 포트 \(activeCount)개")
            }

            if case .scanning = section.scanState {
                ProgressView().controlSize(.small)
            } else if !isOffline {
                Button { Task { await section.scan() } } label: {
                    Image(systemName: "arrow.clockwise").font(.body).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("\(primaryLabel) 포트 재스캔")
                .accessibilityLabel("\(primaryLabel) 포트 재스캔")
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
            .accessibilityLabel("\(primaryLabel) 더보기")
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { handleRowTap() }
    }

    private func handleRowTap() {
        if isOffline {
            Task { await section.scan() }
        } else {
            toggleExpandedAnimated()
        }
    }
}

enum ServerStatusDot: Equatable {
    case none
    case offline(pulse: Bool)
    case warning   // 노랑 — toolMissing / authFailed
    case online    // 녹색

    var fill: Color? {
        switch self {
        case .none: return nil
        case .offline: return .secondary.opacity(0.5)
        case .warning: return .orange
        case .online: return .green
        }
    }

    var pulses: Bool {
        if case .offline(true) = self { return true }
        return false
    }
}

private struct ServerMonogram: View {
    let server: Server
    var status: ServerStatusDot = .none
    var dimmed: Bool = false

    private var initial: String {
        let source = server.name ?? server.host
        guard let first = source.first else { return "?" }
        return String(first).uppercased()
    }

    private var hue: Double {
        var hash: UInt32 = 0x811c9dc5
        for byte in server.host.utf8 {
            hash ^= UInt32(byte)
            hash &*= 0x01000193
        }
        return Double(hash % 360) / 360.0
    }

    var body: some View {
        let tint = Color(
            hue: hue,
            saturation: Color.PB.Monogram.saturation,
            brightness: Color.PB.Monogram.brightness
        )
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(Color.PB.Monogram.fillOpacity))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(tint.opacity(Color.PB.Monogram.strokeOpacity), lineWidth: 0.5)
                Text(initial)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
            }
            .frame(width: 24, height: 24)
            .opacity(dimmed ? 0.55 : 1.0)

            if let fill = status.fill {
                StatusDot(fill: fill, pulses: status.pulses)
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: 24, height: 24)
    }
}

private struct StatusDot: View {
    let fill: Color
    let pulses: Bool
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: 8, height: 8)
            .overlay(
                Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
            )
            .opacity(pulses ? (pulse ? 1.0 : 0.4) : 1.0)
            .scaleEffect(pulses ? (pulse ? 1.0 : 0.9) : 1.0)
            .onAppear {
                guard pulses else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
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

                Spacer(minLength: 0)

                Button(action: copy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(copied ? Color.green : Color.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .help(copied ? "복사됨" : "복사")
                .accessibilityLabel(copied ? "복사됨" : "명령 복사")
            }
        }
        .padding(.vertical, 4)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyCommand, forType: .string)
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { copied = false }
        }
    }
}

private struct ToolInstallGuideView: View {
    private let commands: [(distro: String, command: String)] = [
        ("Debian / Ubuntu", "sudo apt install iproute2 lsof"),
        ("RHEL / CentOS",   "sudo yum install iproute lsof"),
        ("Alpine",          "apk add iproute2 lsof"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("원격 서버에 ss 또는 lsof가 필요합니다", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)

            Text("포트 목록을 조회하려면 둘 중 하나가 설치되어 있어야 합니다.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(commands, id: \.distro) { item in
                    InstallCommandRow(distro: item.distro, command: item.command)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct InstallCommandRow: View {
    let distro: String
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(distro)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(command)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                .textSelection(.enabled)

            Spacer(minLength: 0)

            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(copied ? Color.green : Color.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(copied ? "복사됨" : "복사")
            .accessibilityLabel(copied ? "복사됨" : "\(distro) 명령 복사")
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { copied = false }
        }
    }
}

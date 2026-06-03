// PortBridge/Views/ServerSectionView.swift
import AppKit
import SwiftUI

struct ServerSectionView: View {
    let section: ServerSectionViewModel
    let activeForwardings: [Forwarding]
    let matches: (RemotePort) -> Bool
    let onToggle: (RemotePort) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let isFavorite: (RemotePort) -> Bool
    let onFavoriteToggle: (RemotePort) -> Void

    private var activeCount: Int {
        activeForwardings.filter { $0.serverId == section.server.id }.count
    }

    private var activeCountAccessibility: String {
        String(localized: "server.section.activeCount.accessibility", defaultValue: "포워딩 중인 포트 \(activeCount)개")
    }

    private var inactivePorts: [RemotePort] {
        let activeNums = Set(
            activeForwardings
                .filter { $0.serverId == section.server.id }
                .map { $0.remotePort }
        )
        return section.ports.filter { !activeNums.contains($0.port) && matches($0) }
    }

    /// 포트 행의 List 정체성은 서버 단위로 유일해야 한다. `RemotePort.id`는 "address:port"뿐이라
    /// 여러 서버가 같은 포트를 같은 주소로 노출하면(예: 둘 다 0.0.0.0:5173) 한 List 안에서 id가
    /// 충돌해 SwiftUI가 두 행을 같은 정체성으로 보고 탭/뷰를 엉뚱한 서버 행에 재사용한다.
    /// 서버 id를 접두로 붙여 전역 유일하게 만든다.
    private struct IdentifiedPort: Identifiable {
        let id: String
        let port: RemotePort
    }

    private var inactivePortRows: [IdentifiedPort] {
        inactivePorts.map { IdentifiedPort(id: Self.rowID(serverID: section.server.id, port: $0), port: $0) }
    }

    /// 포트 행의 서버-유일 정체성. 회귀 방지를 위해 순수 함수로 분리(테스트 대상).
    static func rowID(serverID: UUID, port: RemotePort) -> String {
        "\(serverID.uuidString):\(port.id)"
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
            Text(String(localized: "server.section.idle.hint", defaultValue: "↻ 버튼을 눌러 포트를 스캔하세요"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, PBLayout.Space.s1)

        case .scanning:
            HStack(spacing: PBLayout.Space.s2) {
                ProgressView().controlSize(.small)
                Text(String(localized: "server.section.scanning.label", defaultValue: "스캔 중…")).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, PBLayout.Space.s1)

        case .loaded where inactivePorts.isEmpty:
            Text(String(localized: "server.section.empty.noInactivePorts", defaultValue: "포워딩되지 않은 포트 없음"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, PBLayout.Space.s1)

        case .loaded:
            ForEach(inactivePortRows) { row in
                let port = row.port
                ForwardingRowView(
                    display: .inactive(
                        host: section.server.displayName,
                        remotePort: port.port,
                        processName: port.processName
                    ),
                    onToggle: { onToggle(port) },
                    isFavorite: isFavorite(port),
                    onFavoriteToggle: { onFavoriteToggle(port) }
                )
            }

        case .offline:
            EmptyView() // 안전망 — body는 isOffline 분기로 이미 미렌더되지만 switch exhaustiveness 위해 유지

        case .toolMissing:
            ToolInstallGuideView()

        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.vertical, PBLayout.Space.s1)

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
        HStack(spacing: PBLayout.Space.s2) {
            Button(action: handleRowTap) {
                HStack(spacing: PBLayout.Space.s2) {
                    if !isOffline {
                        Image(systemName: section.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                            .transaction { $0.animation = nil }
                            .accessibilityHidden(true)
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
                        Text(verbatim: "\(activeCount)")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.PB.accentBadgeBg, in: Capsule())
                            .help(String(localized: "server.section.activeCount.help", defaultValue: "이 서버에서 포워딩 중인 포트 수"))
                            .accessibilityLabel(activeCountAccessibility)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(primaryLabel) \(secondaryLabel)")
            .accessibilityValue(isOffline
                ? String(localized: "server.section.state.offline", defaultValue: "오프라인")
                : (section.isExpanded
                    ? String(localized: "server.section.state.expanded", defaultValue: "펼침")
                    : String(localized: "server.section.state.collapsed", defaultValue: "접힘")))
            .accessibilityHint(isOffline
                ? String(localized: "server.section.hint.rescan", defaultValue: "이중 탭하여 재스캔")
                : String(
                    localized: "server.section.hint.toggle",
                    defaultValue: "이중 탭하여 \(section.isExpanded ? String(localized: "common.collapse", defaultValue: "접기") : String(localized: "common.expand", defaultValue: "펼치기"))"
                ))

            if case .scanning = section.scanState {
                ProgressView().controlSize(.small)
            } else if !isOffline {
                Button { Task { await section.scan() } } label: {
                    Image(systemName: "arrow.clockwise").font(.body).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "server.section.rescan.help", defaultValue: "\(primaryLabel) 포트 재스캔"))
                .accessibilityLabel(String(localized: "server.section.rescan.accessibility", defaultValue: "\(primaryLabel) 포트 재스캔"))
            }

            Menu {
                Button(String(localized: "server.section.menu.edit", defaultValue: "편집…"), action: onEdit)
                Divider()
                Button(String(localized: "server.section.menu.delete", defaultValue: "삭제"), role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis").font(.body).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20)
            .accessibilityLabel(String(localized: "server.section.menu.accessibility", defaultValue: "\(primaryLabel) 더보기"))
        }
        .padding(.vertical, 6)
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
    case warning // 노랑 — toolMissing / authFailed
    case online // 녹색

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
                RoundedRectangle(cornerRadius: PBLayout.Radius.sm, style: .continuous)
                    .fill(tint.opacity(Color.PB.Monogram.fillOpacity))
                RoundedRectangle(cornerRadius: PBLayout.Radius.sm, style: .continuous)
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
            .onAppear { startPulseIfNeeded() }
            .onChange(of: pulses) { _, newValue in
                if newValue {
                    startPulseIfNeeded()
                } else {
                    withAnimation(.default) { pulse = false }
                }
            }
    }

    private func startPulseIfNeeded() {
        guard pulses else { return }
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}

private struct AuthFailedView: View {
    let copyCommand: String
    let onRetry: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: PBLayout.Space.s2) {
            Label(
                String(localized: "server.section.authFailed.title", defaultValue: "SSH 키 인증 실패"),
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            HStack(spacing: PBLayout.Space.s2) {
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
                .help(copied ? String(localized: "common.copied", defaultValue: "복사됨") : String(
                    localized: "common.copy",
                    defaultValue: "복사"
                ))
                .accessibilityLabel(copied ? String(localized: "common.copied", defaultValue: "복사됨") : String(
                    localized: "server.section.authFailed.copyCommand.accessibility",
                    defaultValue: "명령 복사"
                ))
            }
        }
        .padding(.vertical, PBLayout.Space.s1)
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
        ("RHEL / CentOS", "sudo yum install iproute lsof"),
        ("Alpine", "apk add iproute2 lsof")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: PBLayout.Space.s2) {
            Label(
                String(localized: "server.section.toolMissing.title", defaultValue: "원격 서버에 ss 또는 lsof가 필요합니다"),
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.orange)

            Text(String(localized: "server.section.toolMissing.description", defaultValue: "포트 목록을 조회하려면 둘 중 하나가 설치되어 있어야 합니다."))
                .font(.caption2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: PBLayout.Space.s1) {
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
        HStack(spacing: PBLayout.Space.s2) {
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
            .help(copied ? String(localized: "common.copied", defaultValue: "복사됨") : String(localized: "common.copy", defaultValue: "복사"))
            .accessibilityLabel(copied
                ? String(localized: "common.copied", defaultValue: "복사됨")
                : String(localized: "server.section.toolMissing.copyCommand.accessibility", defaultValue: "\(distro) 명령 복사"))
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

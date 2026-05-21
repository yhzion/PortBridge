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

        case .offline:
            EmptyView()

        case .toolMissing:
            EmptyView()

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
            Button(action: toggleExpandedAnimated) {
                Image(systemName: section.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(section.isExpanded ? "접기" : "펼치기")

            ServerMonogram(server: section.server)
                .accessibilityHidden(true)

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
                    .background(Color.PB.accentBadgeBg, in: Capsule())
                    .help("이 서버에서 포워딩 중인 포트 수")
                    .accessibilityLabel("포워딩 중인 포트 \(activeCount)개")
            }

            if case .scanning = section.scanState {
                ProgressView().controlSize(.small)
            } else {
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
        .onTapGesture(perform: toggleExpandedAnimated)
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

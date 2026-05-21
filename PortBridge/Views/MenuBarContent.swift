import SwiftUI
import AppKit

struct MenuBarContent: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var prefs = viewModel.preferences

        Group {
            favoritesSection

            if !viewModel.nonFavoriteActive.isEmpty {
                Divider()
                activeSection
            }

            if !viewModel.errors.isEmpty {
                Divider()
                errorSummary
            }

            Divider()

            Button("Open Main Window") { activateMainWindow() }
                .keyboardShortcut("o", modifiers: [.command])

            Toggle("Launch at Login", isOn: $prefs.launchAtLogin)
            Toggle("Show in Dock", isOn: $prefs.showInDock)

            Divider()

            Button("Quit PortBridge") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: [.command])
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var favoritesSection: some View {
        let rows = viewModel.favoriteRows
        Text("Favorites").font(.caption).foregroundStyle(.secondary)
        if rows.isEmpty {
            Text("메인 창에서 ★를 눌러 즐겨찾기를 추가하세요")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
        } else {
            ForEach(rows) { row in
                Button(action: { toggle(row) }) {
                    favoriteLabel(row: row)
                }
            }
        }
    }

    @ViewBuilder
    private var activeSection: some View {
        Text("Active").font(.caption).foregroundStyle(.secondary)
        ForEach(viewModel.nonFavoriteActive) { fw in
            Button(action: { stopForwarding(fw) }) {
                Text(":\(fw.remotePort)").monospaced()
            }
        }
    }

    @ViewBuilder
    private var errorSummary: some View {
        let count = viewModel.errors.count
        Button(action: { activateMainWindow() }) {
            Label("\(count) error\(count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
        }
    }

    // MARK: - Labels

    private func favoriteLabel(row: FavoriteRow) -> some View {
        let host = row.serverDisplayName
        let portText = ":\(row.remotePort)"
        let proc = row.processName.map { " \($0)" } ?? ""
        let dot = isActive(state: row.state) ? "● " : "○ "
        return Text("\(dot)\(host)\(portText)\(proc)")
            .monospaced()
    }

    private func isActive(state: Forwarding.State) -> Bool {
        switch state {
        case .active, .starting: return true
        case .idle, .error: return false
        }
    }

    // MARK: - Actions

    private func toggle(_ row: FavoriteRow) {
        Task {
            let port = RemotePort(port: row.remotePort, address: "0.0.0.0", processName: row.processName)
            await viewModel.toggleForwarding(serverId: row.id.serverId, for: port)
        }
    }

    private func stopForwarding(_ fw: Forwarding) {
        Task {
            let port = RemotePort(port: fw.remotePort, address: "0.0.0.0", processName: nil)
            await viewModel.toggleForwarding(serverId: fw.serverId, for: port)
        }
    }

    private func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}

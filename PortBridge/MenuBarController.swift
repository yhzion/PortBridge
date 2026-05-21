import AppKit
import Observation
import SwiftUI

/// 메뉴바 아이콘 + 클릭 분기 관리자.
///
/// - 좌클릭: 표준 NSMenu 표시 (즐겨찾기 / Active / Errors / 환경설정 / Quit)
/// - 우클릭: 즐겨찾기 일괄 토글 (Amphetamine 패턴)
///
/// 아이콘은 isAnyFavoriteActive 파생 상태가 바뀔 때마다 자동 갱신됩니다.
extension Notification.Name {
    /// 메뉴바 또는 외부 소스에서 메인 윈도우를 열어달라고 요청할 때 게시.
    /// ContentView가 .onReceive로 받아 openWindow(id: "main")을 호출합니다.
    static let openPortBridgeMainWindow = Notification.Name("PortBridge.openMainWindow")
}

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let viewModel: AppViewModel
    private var statusItem: NSStatusItem?

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    /// 앱 시작 시 한 번 호출. NSStatusBar에 아이템 추가, 클릭 핸들러 배선, 상태 관측 시작.
    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.image = MenuBarIconRenderer.image(active: viewModel.isAnyFavoriteActive)
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        observeIconState()
    }

    // MARK: - Click routing

    @objc private func handleClick(_ sender: Any?) {
        let type = NSApp.currentEvent?.type
        switch type {
        case .rightMouseUp:
            Task { await viewModel.toggleAllFavorites() }
        case .leftMouseUp:
            presentMenu()
        default:
            presentMenu()
        }
    }

    private func presentMenu() {
        guard let item = statusItem, let button = item.button else { return }
        let menu = buildMenu()
        item.menu = menu
        button.performClick(nil)
        // 메뉴를 다시 해제해 두지 않으면 다음 클릭에서 NSStatusItem이 자체 메뉴 표시 모드로 동작해
        // sendAction(on:)이 무시되어 우클릭 분기가 깨집니다.
        item.menu = nil
    }

    // MARK: - Menu construction

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        // Update available (only when a non-skipped newer release exists)
        if let release = viewModel.updates.availableUpdate {
            let tag = release.tagName
            let item = NSMenuItem(
                title: "Update available — \(tag)",
                action: #selector(openReleasePage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = release.htmlURL
            item.image = NSImage(
                systemSymbolName: "arrow.down.circle.fill",
                accessibilityDescription: nil
            )

            let submenu = NSMenu()
            let skip = NSMenuItem(
                title: "Skip This Version",
                action: #selector(skipCurrentRelease),
                keyEquivalent: ""
            )
            skip.target = self
            submenu.addItem(skip)

            let notes = NSMenuItem(
                title: "Show Release Notes…",
                action: #selector(openReleasePage(_:)),
                keyEquivalent: ""
            )
            notes.target = self
            notes.representedObject = release.htmlURL
            submenu.addItem(notes)

            item.submenu = submenu
            menu.addItem(item)
            menu.addItem(.separator())
        }

        // Favorites
        let favHeader = NSMenuItem(title: "Favorites", action: nil, keyEquivalent: "")
        favHeader.isEnabled = false
        menu.addItem(favHeader)

        let rows = viewModel.favoriteRows
        if rows.isEmpty {
            let hint = NSMenuItem(
                title: "메인 창에서 ★를 눌러 즐겨찾기를 추가하세요",
                action: nil,
                keyEquivalent: ""
            )
            hint.isEnabled = false
            menu.addItem(hint)
        } else {
            for row in rows {
                let item = NSMenuItem(
                    title: favoriteTitle(for: row),
                    action: #selector(toggleFavoriteRow(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = row
                item.state = isActiveState(row.state) ? .on : .off
                menu.addItem(item)
            }
        }

        // Active (non-favorite)
        let actives = viewModel.nonFavoriteActive
        if !actives.isEmpty {
            menu.addItem(.separator())
            let activeHeader = NSMenuItem(title: "Active", action: nil, keyEquivalent: "")
            activeHeader.isEnabled = false
            menu.addItem(activeHeader)
            for fw in actives {
                let item = NSMenuItem(
                    title: ":\(fw.remotePort)",
                    action: #selector(stopActiveForwarding(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = fw
                item.state = .on
                menu.addItem(item)
            }
        }

        // Errors
        if !viewModel.errors.isEmpty {
            menu.addItem(.separator())
            let count = viewModel.errors.count
            let title = "\(count) error\(count == 1 ? "" : "s")"
            let item = NSMenuItem(title: title, action: #selector(openMainWindow), keyEquivalent: "")
            item.target = self
            item.image = NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: nil
            )
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let openItem = NSMenuItem(
            title: "Open Main Window",
            action: #selector(openMainWindow),
            keyEquivalent: "o"
        )
        openItem.target = self
        menu.addItem(openItem)

        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = viewModel.preferences.launchAtLogin ? .on : .off
        menu.addItem(launchItem)

        let dockItem = NSMenuItem(
            title: "Show in Dock",
            action: #selector(toggleShowInDock),
            keyEquivalent: ""
        )
        dockItem.target = self
        dockItem.state = viewModel.preferences.showInDock ? .on : .off
        menu.addItem(dockItem)

        let autoCheckItem = NSMenuItem(
            title: "Check for Updates Automatically",
            action: #selector(toggleAutomaticUpdateCheck),
            keyEquivalent: ""
        )
        autoCheckItem.target = self
        autoCheckItem.state = viewModel.preferences.automaticUpdateCheckEnabled ? .on : .off
        menu.addItem(autoCheckItem)

        let checkNowItem: NSMenuItem
        if case .failed = viewModel.updates.phase {
            checkNowItem = NSMenuItem(
                title: "Check failed — try again",
                action: #selector(checkForUpdatesNow),
                keyEquivalent: ""
            )
        } else if case .checking = viewModel.updates.phase {
            checkNowItem = NSMenuItem(title: "Checking…", action: nil, keyEquivalent: "")
            checkNowItem.isEnabled = false
        } else {
            checkNowItem = NSMenuItem(
                title: "Check for Updates Now…",
                action: #selector(checkForUpdatesNow),
                keyEquivalent: ""
            )
        }
        checkNowItem.target = self
        menu.addItem(checkNowItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit PortBridge",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func favoriteTitle(for row: FavoriteRow) -> String {
        let dot = isActiveState(row.state) ? "● " : "○ "
        let proc = row.processName.map { " \($0)" } ?? ""
        return "\(dot)\(row.serverDisplayName):\(row.remotePort)\(proc)"
    }

    private func isActiveState(_ state: Forwarding.State) -> Bool {
        switch state {
        case .active, .starting: return true
        case .idle, .error: return false
        }
    }

    // MARK: - Menu actions

    @objc private func toggleFavoriteRow(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? FavoriteRow else { return }
        Task {
            let port = RemotePort(
                port: row.remotePort,
                address: "0.0.0.0",
                processName: row.processName
            )
            await viewModel.toggleForwarding(serverId: row.id.serverId, for: port)
        }
    }

    @objc private func stopActiveForwarding(_ sender: NSMenuItem) {
        guard let fw = sender.representedObject as? Forwarding else { return }
        Task {
            let port = RemotePort(port: fw.remotePort, address: "0.0.0.0", processName: nil)
            await viewModel.toggleForwarding(serverId: fw.serverId, for: port)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        viewModel.preferences.launchAtLogin.toggle()
    }

    @objc private func toggleShowInDock() {
        viewModel.preferences.showInDock.toggle()
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let win = NSApp.windows.first(where: { $0.canBecomeMain }) {
            win.makeKeyAndOrderFront(nil)
        } else {
            NotificationCenter.default.post(name: .openPortBridgeMainWindow, object: nil)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openReleasePage(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func skipCurrentRelease() {
        viewModel.updates.skipCurrent()
    }

    @objc private func toggleAutomaticUpdateCheck() {
        viewModel.preferences.automaticUpdateCheckEnabled.toggle()
    }

    @objc private func checkForUpdatesNow() {
        Task { @MainActor in
            await viewModel.updates.checkNow()
        }
    }

    // MARK: - Icon observation

    /// Observation 프레임워크는 한 번 발화하면 종료되므로 onChange 안에서 재구독합니다.
    private func observeIconState() {
        withObservationTracking { [weak self] in
            _ = self?.viewModel.isAnyFavoriteActive
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshIcon()
                self?.observeIconState()
            }
        }
    }

    private func refreshIcon() {
        let active = viewModel.isAnyFavoriteActive
        statusItem?.button?.image = MenuBarIconRenderer.image(active: active)
    }
}

import AppKit
import Observation
import SwiftUI

/// 메뉴바 아이콘 + 메뉴 관리자.
///
/// 좌클릭·우클릭 모두 표준 NSMenu 표시 (즐겨찾기 / Active / Errors / 환경설정 / Quit).
/// 즐겨찾기 일괄 토글은 메뉴 항목으로 제공됩니다 — 우클릭 즉시 토글(구 Amphetamine 패턴)은
/// 발견 불가능하고 확인·피드백 없이 활성 터널을 끊는 문제로 제거됨.
///
/// 아이콘은 isAnyFavoriteActive 파생 상태가 바뀔 때마다 자동 갱신됩니다.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let viewModel: AppViewModel
    private var statusItem: NSStatusItem?
    private var badgeLayer: CALayer?

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
        updateBadge(visible: viewModel.updates.availableUpdate != nil)
    }

    // MARK: - Click routing

    @objc private func handleClick(_ sender: Any?) {
        presentMenu()
    }

    private func presentMenu() {
        guard let item = statusItem, let button = item.button else { return }
        let menu = buildMenu()
        item.menu = menu
        button.performClick(nil)
        // 메뉴를 다시 해제해 두지 않으면 다음 클릭에서 NSStatusItem이 자체 메뉴 표시 모드로 동작해
        // sendAction(on:)이 무시되어 매 클릭마다 메뉴를 새로 구성하는 동작이 깨집니다.
        item.menu = nil
    }

    // MARK: - Menu construction

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        // Installed version (always visible).
        let versionString = Bundle.main.currentVersion?.string ?? "unknown"
        let versionItem = NSMenuItem(
            title: "PortBridge \(versionString)",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())

        // Favorites
        let favHeader = NSMenuItem(title: L10n.MenuBar.favorites, action: nil, keyEquivalent: "")
        favHeader.isEnabled = false
        menu.addItem(favHeader)

        let rows = viewModel.favoriteRows
        if rows.isEmpty {
            let hint = NSMenuItem(
                title: L10n.MenuBar.emptyFavoritesHint,
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

            // 구 우클릭 즉시 토글을 대체하는 가시적 일괄 토글.
            let activeCount = rows.filter { isActiveState($0.state) }.count
            let batchItem = NSMenuItem(
                title: L10n.MenuBar.batchToggleTitle(activeCount: activeCount, total: rows.count),
                action: #selector(toggleAllFavorites),
                keyEquivalent: ""
            )
            batchItem.target = self
            menu.addItem(batchItem)
        }

        // Active (non-favorite)
        let actives = viewModel.nonFavoriteActive
        if !actives.isEmpty {
            menu.addItem(.separator())
            let activeHeader = NSMenuItem(title: L10n.MenuBar.active, action: nil, keyEquivalent: "")
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
            let item = NSMenuItem(
                title: L10n.MenuBar.errorCount(count),
                action: #selector(openMainWindow),
                keyEquivalent: ""
            )
            item.target = self
            item.image = NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: nil
            )
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let openItem = NSMenuItem(
            title: L10n.MenuBar.openMainWindow,
            action: #selector(openMainWindow),
            keyEquivalent: "o"
        )
        openItem.target = self
        menu.addItem(openItem)

        let launchItem = NSMenuItem(
            title: L10n.MenuBar.launchAtLogin,
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = viewModel.preferences.launchAtLogin ? .on : .off
        menu.addItem(launchItem)

        let dockItem = NSMenuItem(
            title: L10n.MenuBar.showInDock,
            action: #selector(toggleShowInDock),
            keyEquivalent: ""
        )
        dockItem.target = self
        dockItem.state = viewModel.preferences.showInDock ? .on : .off
        menu.addItem(dockItem)

        let autoCheckItem = NSMenuItem(
            title: L10n.MenuBar.checkUpdatesAutomatically,
            action: #selector(toggleAutomaticUpdateCheck),
            keyEquivalent: ""
        )
        autoCheckItem.target = self
        autoCheckItem.state = viewModel.preferences.automaticUpdateCheckEnabled ? .on : .off
        menu.addItem(autoCheckItem)

        let checkNowItem: NSMenuItem
        if case .checking = viewModel.updates.phase {
            checkNowItem = NSMenuItem(title: L10n.MenuBar.checking, action: nil, keyEquivalent: "")
            checkNowItem.isEnabled = false
        } else {
            checkNowItem = NSMenuItem(
                title: L10n.MenuBar.checkUpdatesNow,
                action: #selector(checkForUpdatesNow),
                keyEquivalent: ""
            )
        }
        checkNowItem.target = self
        menu.addItem(checkNowItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.MenuBar.quit,
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

    @objc private func toggleAllFavorites() {
        Task { await viewModel.toggleAllFavorites() }
    }

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
        (NSApp.delegate as? AppDelegate)?.showMainWindow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func toggleAutomaticUpdateCheck() {
        viewModel.preferences.automaticUpdateCheckEnabled.toggle()
    }

    @objc private func checkForUpdatesNow() {
        Task { @MainActor in
            await viewModel.updates.checkNow(manual: true)
        }
    }

    // MARK: - Icon observation

    /// Observation 프레임워크는 한 번 발화하면 종료되므로 onChange 안에서 재구독합니다.
    private func observeIconState() {
        withObservationTracking { [weak self] in
            _ = self?.viewModel.isAnyFavoriteActive
            _ = self?.viewModel.updates.availableUpdate
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                refreshIcon()
                updateBadge(visible: viewModel.updates.availableUpdate != nil)
                observeIconState()
            }
        }
    }

    private func refreshIcon() {
        let active = viewModel.isAnyFavoriteActive
        statusItem?.button?.image = MenuBarIconRenderer.image(active: active)
    }

    private func updateBadge(visible: Bool) {
        guard let button = statusItem?.button else { return }
        if visible {
            if badgeLayer == nil {
                button.wantsLayer = true
                let layer = CALayer()
                layer.backgroundColor = NSColor.systemBlue.cgColor
                layer.cornerRadius = 2
                button.layer?.addSublayer(layer)
                badgeLayer = layer
            }
            layoutBadge()
        } else {
            badgeLayer?.removeFromSuperlayer()
            badgeLayer = nil
        }
    }

    private func layoutBadge() {
        guard let button = statusItem?.button, let layer = badgeLayer else { return }
        let size: CGFloat = 4
        let inset: CGFloat = 1
        let x = button.bounds.maxX - size - inset
        let y = button.bounds.maxY - size - inset
        layer.frame = CGRect(x: x, y: y, width: size, height: size)
    }
}

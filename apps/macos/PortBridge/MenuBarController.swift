import AppKit
import Observation
import SwiftUI

/// 메뉴바 아이콘 + 클릭 분기 관리자.
///
/// - 좌클릭: 표준 NSMenu 표시 (즐겨찾기 / Active / Errors / 환경설정 / Quit)
/// - 우클릭: 빠른 일괄 토글 (Amphetamine 패턴) — 연결 중이면 전부 해제, 모두 꺼졌으면 즐겨찾기만 연결
///
/// 아이콘은 isAnyForwardingActive 파생 상태가 바뀔 때마다 자동 갱신됩니다.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let viewModel: AppViewModel
    private let onOpenMainWindow: () -> Void
    private var statusItem: NSStatusItem?
    private var badgeLayer: CALayer?

    /// 메뉴를 펼칠 때마다 즐겨찾기의 온라인 여부를 갱신하기 위한 스캔 스로틀.
    /// 메뉴 표시는 동기지만 스캔은 async SSH(도달 불가 시 ~10초)이므로, 한 번 열 때
    /// 보이는 것은 *직전* 스캔 결과이고 이번 스캔은 다음에 열 때 반영된다. throttle은
    /// 연속해서 메뉴를 여닫을 때 전 서버를 반복 re-SSH하지 않도록 코얼레싱한다.
    private var lastFavoritesScan: Date?
    private static let menuScanThrottle: TimeInterval = 15

    init(viewModel: AppViewModel, onOpenMainWindow: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onOpenMainWindow = onOpenMainWindow
        super.init()
    }

    /// 앱 시작 시 한 번 호출. NSStatusBar에 아이템 추가, 클릭 핸들러 배선, 상태 관측 시작.
    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.image = MenuBarIconRenderer.image(active: viewModel.isAnyForwardingActive)
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        observeIconState()
        updateBadge(visible: viewModel.updates.availableUpdate != nil)
    }

    // MARK: - Click routing

    @objc private func handleClick(_ sender: Any?) {
        let type = NSApp.currentEvent?.type
        switch type {
        case .rightMouseUp:
            Task { await viewModel.toggleAll() }
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

    // MARK: - NSMenuDelegate

    /// 메뉴가 열릴 때마다 즐겨찾기 서버의 온라인 여부를 갱신한다. 메인 창을 열어야만
    /// 스캔되던 한계를 메우는 메뉴바 소유 스캔 트리거다. 스로틀로 연속 오픈 시 전 서버
    /// 반복 re-SSH를 막는다. 이미 펼쳐진 NSMenu는 정적 스냅샷이라 이번 스캔 결과는
    /// 다음에 열 때 반영된다(메뉴는 클릭마다 `buildMenu()`로 새로 그려짐).
    func menuWillOpen(_ menu: NSMenu) {
        let now = Date()
        guard Self.shouldScan(now: now, last: lastFavoritesScan, throttle: Self.menuScanThrottle) else {
            return
        }
        lastFavoritesScan = now
        Task { @MainActor in await viewModel.scanAll() }
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
        let favHeader = NSMenuItem(title: "Favorites", action: nil, keyEquivalent: "")
        favHeader.isEnabled = false
        menu.addItem(favHeader)

        let rows = viewModel.favoriteRows
        if rows.isEmpty {
            let hint = NSMenuItem(
                title: String(
                    localized: "menu.favorites.empty",
                    defaultValue: "메인 창에서 ★를 눌러 즐겨찾기를 추가하세요"
                ),
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
                item.state = isConnected(row) ? .on : .off
                if isDimmed(row) {
                    // 온라인이 확정되지 않았고 신뢰 가능한 연결도 아닌 서버는 흐리게 —
                    // 클릭은 가능하게 유지(사용자가 stale 터널을 끄거나 재연결할 수 있도록).
                    item.attributedTitle = NSAttributedString(
                        string: favoriteTitle(for: row),
                        attributes: [.foregroundColor: NSColor.secondaryLabelColor]
                    )
                }
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
        if case .checking = viewModel.updates.phase {
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
        let dot = isConnected(row) ? "● " : "○ "
        let proc = row.processName.map { " \($0)" } ?? ""
        return "\(dot)\(row.serverDisplayName):\(row.remotePort)\(proc)"
    }

    /// 메뉴에 ● 연결됨으로 보일지 판정. 오프라인 서버는 (ConnectTimeout 미설정 탓에 stale/가짜
    /// `.active`가 될 수 있어) 절대 연결됨으로 표시하지 않는다 — 메인 창의 오프라인 처리와 일관.
    private func isConnected(_ row: FavoriteRow) -> Bool {
        !row.isOffline && isActiveState(row.state)
    }

    /// 행을 흐리게(미확인/도달 불가) 표시할지 판정. 온라인이 확정(`isOnlineConfirmed`)되지
    /// 않았고 신뢰 가능한 연결(`isConnected`)도 아닐 때만 흐리게 한다 — 즉 살아있는 터널이나
    /// 스캔으로 도달 확인된 서버는 또렷하게 두고, `.idle`/`.scanning`/`.offline`/`.error` 등
    /// 미확인 상태만 흐려진다. 숨기지 않으므로 사용자는 흐린 행도 클릭할 수 있다.
    private func isDimmed(_ row: FavoriteRow) -> Bool {
        Self.shouldDim(isOnlineConfirmed: row.isOnlineConfirmed, isConnected: isConnected(row))
    }

    /// 흐림 판정의 순수 로직(테스트용으로 분리). `MenuBarController.swift`의 진실 표를 잠근다.
    static func shouldDim(isOnlineConfirmed: Bool, isConnected: Bool) -> Bool {
        !isOnlineConfirmed && !isConnected
    }

    /// 메뉴를 펼칠 때 스캔을 다시 돌릴지 판정. `last`가 없으면(첫 오픈) 항상 스캔,
    /// 그 외엔 마지막 스캔으로부터 `throttle`초가 지났을 때만 스캔한다.
    static func shouldScan(now: Date, last: Date?, throttle: TimeInterval) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= throttle
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
        // NSStatusItem 메뉴는 .eventTracking 런루프 모드로 추적됩니다. 그 모드에서는
        // 윈도우 표시/활성화 호출이 삼켜지므로(DispatchQueue.main.async도 common modes라
        // 트래킹 중 실행될 수 있음), .default 모드에서만 실행되도록 예약해 메뉴 트래킹이
        // 끝난 뒤 showMainWindow()가 실행되게 합니다.
        RunLoop.current.perform(inModes: [.default]) { [weak self] in
            self?.onOpenMainWindow()
        }
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
            _ = self?.viewModel.isAnyForwardingActive
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
        let active = viewModel.isAnyForwardingActive
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

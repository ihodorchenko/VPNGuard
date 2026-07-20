//
//  MenuBuilder.swift
//  VPNGuard
//
//  Builds the menu bar context menu for VPNGuard.
//

import AppKit

/// Constructs and updates the status bar menu items.
@MainActor
final class MenuBuilder {

    let vpnItem = NSMenuItem()
    let protectionItem = NSMenuItem()
    let blockedItem = NSMenuItem()

    private weak var target: AnyObject?

    init(target: AnyObject) {
        self.target = target
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        vpnItem.title = "VPN: Checking..."
        protectionItem.title = "Protection: ..."
        blockedItem.title = "Blocked: 0"

        menu.addItem(vpnItem)
        menu.addItem(protectionItem)
        menu.addItem(blockedItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(makeItem(
            title: "Enable Protection",
            action: #selector(MenuActions.enableProtection),
            keyEquivalent: ""
        ))

        menu.addItem(makeItem(
            title: "Disable Protection",
            action: #selector(MenuActions.disableProtection),
            keyEquivalent: ""
        ))

        menu.addItem(makeItem(
            title: "Refresh IPs",
            action: #selector(MenuActions.refreshIPs),
            keyEquivalent: "r"
        ))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(makeItem(
            title: "Settings…",
            action: #selector(MenuActions.openSettings),
            keyEquivalent: ","
        ))

        menu.addItem(makeItem(
            title: "Open Logs",
            action: #selector(MenuActions.openLogs),
            keyEquivalent: "l"
        ))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(makeItem(
            title: "Quit",
            action: #selector(MenuActions.quit),
            keyEquivalent: "q"
        ))

        return menu
    }

    func update(
        vpnState: VPNState,
        protectionEnabled: Bool,
        isBlocking: Bool,
        blockedCount: Int,
        protectedIPCount: Int
    ) {
        switch vpnState {
        case .checking:
            vpnItem.title = "VPN: Checking..."
        case .connected:
            vpnItem.title = "VPN: Connected"
        case .disconnected:
            vpnItem.title = "VPN: Disconnected"
        }

        if !protectionEnabled {
            protectionItem.title = "Protection: Disabled"
        } else if isBlocking {
            protectionItem.title = "Protection: BLOCKING"
        } else {
            protectionItem.title = "Protection: Enabled"
        }

        blockedItem.title = "Blocked: \(blockedCount) (\(protectedIPCount) IPs)"
    }

    // MARK: - Private

    private func makeItem(
        title: String,
        action: Selector,
        keyEquivalent: String
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: keyEquivalent
        )
        item.target = target
        return item
    }
}

/// Selector target protocol for menu actions.
@objc
protocol MenuActions {
    func enableProtection()
    func disableProtection()
    func refreshIPs()
    func openSettings()
    func openLogs()
    func quit()
}

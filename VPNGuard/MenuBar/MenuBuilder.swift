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
    let toggleProtectionItem = NSMenuItem()

    private weak var target: AnyObject?

    init(target: AnyObject) {
        self.target = target
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        vpnItem.title = "VPN: Checking..."
        vpnItem.isEnabled = false
        protectionItem.title = "Protection: ..."
        protectionItem.isEnabled = false
        blockedItem.title = "Blocked: 0"
        blockedItem.isEnabled = false

        menu.addItem(vpnItem)
        menu.addItem(protectionItem)
        menu.addItem(blockedItem)

        menu.addItem(NSMenuItem.separator())

        toggleProtectionItem.target = target
        menu.addItem(toggleProtectionItem)

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
            title: "Help…",
            action: #selector(MenuActions.openHelp),
            keyEquivalent: "?"
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
            toggleProtectionItem.title = "Enable Protection"
            toggleProtectionItem.action = #selector(MenuActions.enableProtection)
        } else {
            if isBlocking {
                protectionItem.title = "Protection: BLOCKING"
            } else {
                protectionItem.title = "Protection: Enabled"
            }
            toggleProtectionItem.title = "Disable Protection"
            toggleProtectionItem.action = #selector(MenuActions.disableProtection)
        }

        blockedItem.title = "Blocked: \(blockedCount) host(s) (\(protectedIPCount) IPs)"
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
    func openHelp()
    func openLogs()
    func quit()
}

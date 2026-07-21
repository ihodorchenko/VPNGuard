//
//  StatusBarController.swift
//  VPNGuard
//
//  Menu bar icon and menu controller for VPNGuard.
//

import AppKit
import Combine

final class StatusBarController: NSObject, MenuActions {

    private let statusItem: NSStatusItem
    private var menuBuilder: MenuBuilder!

    private let engine: ProtectionEngine
    private let monitor: VPNMonitor

    private var cancellables = Set<AnyCancellable>()

    init(
        engine: ProtectionEngine,
        monitor: VPNMonitor
    ) {
        self.engine = engine
        self.monitor = monitor

        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        super.init()

        menuBuilder = MenuBuilder(target: self)
        statusItem.menu = menuBuilder.buildMenu()

        bind()
        updateUI()
    }

    // MARK: - Bindings

    private func bind() {
        engine.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateUI() }
            .store(in: &cancellables)

        engine.$protectionEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateUI() }
            .store(in: &cancellables)

        engine.$isBlocking
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateUI() }
            .store(in: &cancellables)

        ConnectionRegistry.shared.$blockedCount
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateUI() }
            .store(in: &cancellables)

        ConnectionRegistry.shared.$protectedIPCount
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateUI() }
            .store(in: &cancellables)
    }

    private func updateUI() {
        menuBuilder.update(
            vpnState: engine.state,
            protectionEnabled: engine.protectionEnabled,
            isBlocking: engine.isBlocking,
            blockedCount: ConnectionRegistry.shared.blockedCount,
            protectedIPCount: ConnectionRegistry.shared.protectedIPCount
        )
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }

        // Protection off → orange (kill switch idle, hosts are reachable)
        guard engine.protectionEnabled else {
            button.title = "🟠 VG"
            return
        }

        // Protection on → color reflects VPN / block status
        switch engine.state {
        case .checking:
            button.title = "🟡 VG"
        case .connected:
            button.title = "🟢 VG"
        case .disconnected:
            button.title = "🔴 VG"
        }
    }

    // MARK: - MenuActions

    @objc func enableProtection() {
        Task { await engine.setProtectionEnabled(true) }
    }

    @objc func disableProtection() {
        Task { await engine.setProtectionEnabled(false) }
    }

    @objc func refreshIPs() {
        Task { await engine.refreshIPsAndRules() }
    }

    @objc func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openHelp() {
        HelpWindowController.shared.show(engine: engine)
    }

    @objc func openLogs() {
        Logger.shared.revealLogsInFinder()
    }

    @objc func quit() {
        monitor.stop()
        Rules.shared.stopPeriodicRefresh()
        NSApplication.shared.terminate(nil)
    }
}

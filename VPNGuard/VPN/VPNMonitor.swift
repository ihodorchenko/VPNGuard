//
//  VPNMonitor.swift
//  VPNGuard
//
//  Periodically checks VPN routing for all protected hosts.
//

import Foundation

/// Monitors VPN connectivity by checking route interfaces for protected hosts.
@MainActor
final class VPNMonitor {

    private let engine: ProtectionEngine
    private var timer: Timer?
    private var isChecking = false

    init(engine: ProtectionEngine) {
        self.engine = engine
    }

    func start() {
        Task { await performCheck() }

        timer = Timer.scheduledTimer(
            withTimeInterval: Constants.vpnCheckInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.performCheck()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    private func performCheck() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let hosts = Rules.shared.protectedHosts
        guard !hosts.isEmpty else {
            await engine.handleVPNDisconnected()
            return
        }

        var allViaVPN = true

        for host in hosts {
            let viaVPN = RouteChecker.shared.isVPNRoute(for: host)
            if !viaVPN {
                allViaVPN = false
                Logger.shared.debug("Route not via VPN", details: ["Host": host])
                break
            }
        }

        if allViaVPN {
            await engine.handleVPNConnected()
        } else {
            await engine.handleVPNDisconnected()
        }
    }
}

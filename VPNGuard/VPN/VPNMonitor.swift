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
        timer?.invalidate()
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

    /// Clears the in-flight guard so checks resume after the machine wakes
    /// (a check started before sleep may never have returned).
    func reset() {
        isChecking = false
    }

    // MARK: - Private

    private func performCheck() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let hosts = Rules.shared.protectedHosts

        // Check hosts concurrently: a stalled `route` call must not delay the
        // remaining hosts by the full command timeout each.
        let checks = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for host in hosts {
                group.addTask {
                    await RouteChecker.shared.isVPNRouteAsync(for: host)
                }
            }

            var results: [Bool] = []
            results.reserveCapacity(hosts.count)
            for await result in group {
                results.append(result)
            }
            return results
        }

        // Engine is edge-triggered: repeated same-status calls are no-ops.
        switch VPNRouteAggregator.aggregate(checks: checks) {
        case .connected:
            await engine.handleVPNConnected()
        case .disconnected:
            await engine.handleVPNDisconnected()
        }
    }
}

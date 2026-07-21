//
//  ProtectionEngine.swift
//  VPNGuard
//
//  Central engine coordinating VPN state and PF kill switch activation.
//  PF rules are applied only on real state edges — steady polls are no-ops.
//

import Foundation
import Combine

/// Orchestrates kill switch logic based on VPN connectivity state.
@MainActor
final class ProtectionEngine: ObservableObject {

    @Published private(set) var state: VPNState = .checking
    @Published private(set) var protectionEnabled: Bool = true
    @Published private(set) var isBlocking = false

    private let pfManager = PFManager.shared
    private var isTransitioning = false

    init() {
        protectionEnabled = UserDefaults.standard.object(
            forKey: Constants.DefaultsKey.protectionEnabled
        ) as? Bool ?? true
    }

    var isProtected: Bool {
        state == .connected
    }

    // MARK: - State Transitions (edge-triggered)

    /// VPN routes confirmed. Clears PF blocks only when needed.
    func handleVPNConnected() async {
        // Steady state: already connected and not blocking → nothing to do.
        if state == .connected && !isBlocking {
            return
        }

        // Recovery: connected but blocks still active (e.g. previous flush failed).
        if state == .connected && isBlocking {
            if protectionEnabled {
                await disableBlocking()
            }
            return
        }

        // Edge: checking/disconnected → connected
        state = .connected
        Logger.shared.info("VPN Connected")

        if protectionEnabled {
            await disableBlocking()
        }
    }

    /// VPN routes lost. Enables PF blocks only when needed.
    func handleVPNDisconnected() async {
        // Steady state: already disconnected and blocking → nothing to do.
        if state == .disconnected && isBlocking {
            return
        }

        // Recovery: disconnected but blocks somehow cleared.
        if state == .disconnected && !isBlocking {
            if protectionEnabled {
                await enableBlocking()
            }
            return
        }

        // Edge: checking/connected → disconnected
        state = .disconnected
        Logger.shared.security("VPN unavailable — activating kill switch")

        if protectionEnabled {
            await enableBlocking()
        }
    }

    // MARK: - Manual Controls

    func setProtectionEnabled(_ enabled: Bool) async {
        guard enabled != protectionEnabled else { return }

        protectionEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Constants.DefaultsKey.protectionEnabled)

        if enabled {
            if state == .disconnected {
                await enableBlocking()
            }
            // If VPN is connected, leave traffic open — nothing to apply.
        } else {
            await disableBlocking()
        }

        Logger.shared.info(enabled ? "Protection enabled" : "Protection disabled")
    }

    func refreshIPsAndRules() async {
        let ips = await Rules.shared.refresh()
        // Only push new IPs to PF while actively blocking.
        guard isBlocking else { return }
        await pfManager.refreshRules(ips: ips)
    }

    /// Clears PF block rules when the application is quitting.
    func cleanupOnShutdown() async {
        isTransitioning = false
        await pfManager.disableBlock()
        isBlocking = pfManager.blockingActive
        ConnectionRegistry.shared.resetBlockedCount()
        Logger.shared.info("Shutdown cleanup — PF rules cleared")
    }

    // MARK: - Blocking (guards against redundant XPC/pfctl)

    private func enableBlocking() async {
        guard !isTransitioning else { return }
        // Already blocking according to both local and helper state — skip.
        if isBlocking && pfManager.blockingActive { return }

        isTransitioning = true
        defer { isTransitioning = false }

        if Rules.shared.protectedIPs.isEmpty {
            _ = await Rules.shared.refresh()
        }

        await pfManager.enableBlock(ips: Rules.shared.protectedIPs)
        isBlocking = pfManager.blockingActive

        if isBlocking {
            for host in Rules.shared.protectedHosts {
                ConnectionRegistry.shared.recordBlocked(
                    host: host,
                    reason: "VPN unavailable"
                )
            }
        }
    }

    private func disableBlocking() async {
        guard !isTransitioning else { return }
        // Already clear — skip XPC round-trip.
        if !isBlocking && !pfManager.blockingActive { return }

        isTransitioning = true
        defer { isTransitioning = false }

        await pfManager.disableBlock()
        isBlocking = pfManager.blockingActive

        if !isBlocking {
            ConnectionRegistry.shared.resetBlockedCount()
            Logger.shared.info("Kill switch cleared — traffic allowed")
        }
    }
}

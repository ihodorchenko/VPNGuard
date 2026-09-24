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
    private var cancellables = Set<AnyCancellable>()
    /// Last IP set pushed into PF while blocking — avoids redundant pfctl/XPC.
    private var appliedIPs: Set<String> = []

    init() {
        let defaults = UserDefaults.standard
        let autoStart = defaults.object(
            forKey: Constants.DefaultsKey.autoStart
        ) as? Bool ?? true
        let remembered = defaults.object(
            forKey: Constants.DefaultsKey.protectionEnabled
        ) as? Bool ?? true

        // "Auto start protection" off means the kill switch boots disabled and
        // must be enabled manually from the menu.
        protectionEnabled = autoStart && remembered

        observeProtectedIPs()
    }

    /// While blocking, IPs resolved by the periodic DNS refresh must reach PF —
    /// otherwise rotated CDN addresses stay reachable (kill switch bypass).
    private func observeProtectedIPs() {
        Rules.shared.$protectedIPs
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] ips in
                guard let self else { return }
                Task { @MainActor in
                    await self.pushIPsIfNeeded(ips)
                }
            }
            .store(in: &cancellables)
    }

    var isProtected: Bool {
        state == .connected
    }

    // MARK: - State Transitions (edge-triggered)

    /// VPN routes confirmed. Clears PF blocks only when needed.
    func handleVPNConnected() async {
        await applyVPNState(connected: true)
    }

    /// VPN routes lost. Enables PF blocks only when needed.
    func handleVPNDisconnected() async {
        await applyVPNState(connected: false)
    }

    /// Evaluates the pure protection policy: updates the published state on a
    /// real edge and performs at most one blocking transition. Repeated polls
    /// with an unchanged state are no-ops.
    private func applyVPNState(connected: Bool) async {
        let decision = ProtectionPolicy.decide(
            vpnConnected: connected,
            isBlocking: isBlocking,
            protectionEnabled: protectionEnabled
        )

        if decision.state != state {
            state = decision.state
            if connected {
                Logger.shared.info("VPN Connected")
            } else {
                Logger.shared.security("VPN unavailable — activating kill switch")
            }
        }

        switch decision.action {
        case .enable:
            await enableBlocking()
        case .disable:
            await disableBlocking()
        case .none:
            break
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
        _ = await Rules.shared.refresh()
        // Only pushes while actively blocking, and only if the set changed.
        await pushIPsIfNeeded(Rules.shared.protectedIPs)
    }

    /// Re-syncs the local blocking flag with the privileged helper after wake
    /// and clears the transition guard. The helper is the source of truth for
    /// whether PF rules are actually loaded, so this prevents the engine from
    /// believing it is blocking when it is not (or vice versa).
    func resyncAfterWake() async {
        isTransitioning = false
        isBlocking = await pfManager.resyncBlockingState()
        appliedIPs = isBlocking ? Rules.shared.protectedIPs : []
        Logger.shared.info("Resynced blocking state after wake", details: [
            "Blocking": isBlocking ? "true" : "false"
        ])
    }

    /// Clears PF block rules when the application is quitting.
    func cleanupOnShutdown() async {
        isTransitioning = false
        await pfManager.disableBlock()
        isBlocking = pfManager.blockingActive
        appliedIPs = []
        ConnectionRegistry.shared.resetBlockedCount()
        Logger.shared.info("Shutdown cleanup — PF rules cleared")
    }

    /// Pushes the current IP set into PF when blocking is active and the set
    /// changed. No-op otherwise, so steady polls cost nothing.
    private func pushIPsIfNeeded(_ ips: Set<String>) async {
        guard isBlocking, !isTransitioning, !ips.isEmpty else { return }
        guard ips != appliedIPs else { return }

        await pfManager.refreshRules(ips: ips)
        appliedIPs = ips
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

        let ips = Rules.shared.protectedIPs
        // Never report "blocking" without any target IPs — that would be a silent
        // fail-open. Report failure and let the next poll retry once DNS recovers.
        guard !ips.isEmpty else {
            Logger.shared.error(
                "Kill switch could not activate — no protected IPs resolved",
                details: ["Hint": "DNS resolution failed; retrying on next poll"]
            )
            isBlocking = false
            return
        }

        await pfManager.enableBlock(ips: ips)
        isBlocking = pfManager.blockingActive
        appliedIPs = isBlocking ? ips : []

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
            appliedIPs = []
            ConnectionRegistry.shared.resetBlockedCount()
            Logger.shared.info("Kill switch cleared — traffic allowed")
        }
    }
}

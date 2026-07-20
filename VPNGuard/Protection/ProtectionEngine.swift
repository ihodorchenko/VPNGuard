//
//  ProtectionEngine.swift
//  VPNGuard
//
//  Central engine coordinating VPN state and PF kill switch activation.
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

    // MARK: - State Transitions

    /// Called by VPNMonitor when VPN routes are verified.
    func handleVPNConnected() async {
        let wasConnected = (state == .connected)
        let shouldClearBlocks = isBlocking || state == .disconnected

        if !wasConnected {
            state = .connected
            Logger.shared.info("VPN Connected")
        }

        // Always clear PF rules when VPN is up and we still have blocks loaded.
        // (Previously skipped when an intermediate .checking state masked .disconnected.)
        if protectionEnabled && shouldClearBlocks {
            await disableBlocking()
        }
    }

    /// Called by VPNMonitor when VPN routes are lost.
    func handleVPNDisconnected() async {
        let wasDisconnected = (state == .disconnected)

        if !wasDisconnected {
            state = .disconnected
            Logger.shared.security("VPN unavailable — activating kill switch")
        }

        // Apply (or re-apply) blocks whenever protection is on and VPN is down.
        if protectionEnabled && (!isBlocking || !wasDisconnected) {
            await enableBlocking()
        }
    }

    // MARK: - Manual Controls

    func setProtectionEnabled(_ enabled: Bool) async {
        protectionEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Constants.DefaultsKey.protectionEnabled)

        if enabled && state == .disconnected {
            await enableBlocking()
        } else if !enabled {
            await disableBlocking()
        }

        Logger.shared.info(enabled ? "Protection enabled" : "Protection disabled")
    }

    func refreshIPsAndRules() async {
        let ips = await Rules.shared.refresh()
        if isBlocking {
            await pfManager.refreshRules(ips: ips)
        }
    }

    // MARK: - Blocking

    private func enableBlocking() async {
        guard !isTransitioning else { return }
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

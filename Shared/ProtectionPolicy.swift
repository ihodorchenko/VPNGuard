//
//  ProtectionPolicy.swift
//  VPNGuard
//
//  Pure, edge-triggered decision logic for the kill switch: given the current
//  VPN state and blocking flag, decide the next state and whether PF blocking
//  must be enabled or disabled. Kept side-effect free so it can be unit-tested.
//

import Foundation

/// What the engine should do about PF blocking after a state evaluation.
nonisolated enum BlockingAction: Equatable {
    case none
    case enable
    case disable
}

/// The outcome of evaluating a VPN state change.
nonisolated struct ProtectionDecision: Equatable {
    let state: VPNState
    let action: BlockingAction
}

nonisolated enum ProtectionPolicy {

    /// Decides the next VPN state and blocking action.
    ///
    /// Blocking is desired only when VPN routes are gone *and* protection is
    /// enabled. The comparison against the current `isBlocking` flag makes the
    /// transition edge-triggered: steady-state polls produce `.none`.
    static func decide(
        vpnConnected: Bool,
        isBlocking: Bool,
        protectionEnabled: Bool
    ) -> ProtectionDecision {
        let state: VPNState = vpnConnected ? .connected : .disconnected
        let shouldBlock = protectionEnabled && !vpnConnected

        let action: BlockingAction
        if shouldBlock && !isBlocking {
            action = .enable
        } else if !shouldBlock && isBlocking {
            action = .disable
        } else {
            action = .none
        }

        return ProtectionDecision(state: state, action: action)
    }
}

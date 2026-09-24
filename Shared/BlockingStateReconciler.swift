//
//  BlockingStateReconciler.swift
//  VPNGuard
//
//  Pure decision for re-syncing the local blocking flag with the privileged
//  helper. Kept side-effect free so the rule can be unit-tested.
//

import Foundation

nonisolated enum BlockingStateReconciler {

    /// The helper is the source of truth for whether PF rules are actually
    /// loaded, but only when the status query succeeded. On failure the local
    /// value is kept (best-effort reconciliation).
    static func reconcile(
        success: Bool,
        helperBlockingActive: Bool,
        current: Bool
    ) -> Bool {
        success ? helperBlockingActive : current
    }
}

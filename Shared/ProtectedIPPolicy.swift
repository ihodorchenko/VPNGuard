//
//  ProtectedIPPolicy.swift
//  VPNGuard
//
//  Pure decision logic for how a DNS refresh affects the protected IP set.
//  Kept side-effect free (no Logger, no UserDefaults) so the fail-open guard
//  can be unit-tested directly.
//

import Foundation

/// Outcome of applying a freshly resolved IP set to the currently protected IPs.
enum ProtectedIPDecision: Equatable {
    /// No protected hosts configured — nothing to protect.
    case noHosts
    /// Fresh resolution succeeded; replace the set with these IPs.
    case updated(Set<String>)
    /// Resolution failed but a previous set exists — keep it instead of
    /// publishing an empty set, which would silently disable the kill switch.
    case keptLastKnown(Set<String>)
    /// Resolution failed and there is no history — the set stays empty.
    case unresolved
}

enum ProtectedIPPolicy {

    /// Decides what the protected IP set should become after a refresh.
    ///
    /// - Parameters:
    ///   - hosts: currently configured protected hosts.
    ///   - resolved: IPs returned by this refresh (union across hosts).
    ///   - previous: the set that was active before this refresh.
    static func decide(
        hosts: [String],
        resolved: Set<String>,
        previous: Set<String>
    ) -> ProtectedIPDecision {
        guard !hosts.isEmpty else { return .noHosts }

        if resolved.isEmpty {
            return previous.isEmpty ? .unresolved : .keptLastKnown(previous)
        }

        return .updated(resolved)
    }
}

//
//  VPNRouteAggregator.swift
//  VPNGuard
//
//  Pure aggregation of per-host VPN route checks. Kept side-effect free so the
//  "every protected host must route through the VPN" rule can be unit-tested.
//

import Foundation

/// Whether traffic to the protected hosts is currently routed through the VPN.
enum VPNRouteAggregation: Equatable {
    case connected
    case disconnected
}

enum VPNRouteAggregator {

    /// Aggregates the per-host route checks performed by the monitor.
    ///
    /// The connection is considered up only when there is at least one host and
    /// every check passed. An empty check list means no protected hosts are
    /// configured, which the monitor treats as "not connected".
    static func aggregate(checks: [Bool]) -> VPNRouteAggregation {
        guard !checks.isEmpty, checks.allSatisfy({ $0 }) else {
            return .disconnected
        }
        return .connected
    }
}

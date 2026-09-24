//
//  Rules.swift
//  VPNGuard
//
//  Manages protected hosts and their resolved IP addresses.
//

import Foundation
import Combine

/// Rule engine holding protected hosts and resolved IPs.
@MainActor
final class Rules: ObservableObject {

    static let shared = Rules()

    @Published private(set) var protectedIPs: Set<String> = []
    @Published private(set) var protectedHosts: [String]

    private var refreshTimer: Timer?

    private init() {
        if let saved = UserDefaults.standard.stringArray(
            forKey: Constants.DefaultsKey.protectedHosts
        ), !saved.isEmpty {
            protectedHosts = saved
        } else {
            protectedHosts = Constants.defaultProtectedHosts
        }
    }

    // MARK: - Host Management

    func isProtectedHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        return protectedHosts.contains { protected in
            normalized == protected.lowercased()
                || normalized.hasSuffix(".\(protected.lowercased())")
        }
    }

    func updateHosts(_ hosts: [String]) {
        protectedHosts = hosts
        UserDefaults.standard.set(hosts, forKey: Constants.DefaultsKey.protectedHosts)
        Task { await refresh() }
    }

    // MARK: - DNS Refresh

    func startPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: Constants.dnsRefreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    func stopPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Resolves all protected hosts and updates the IP set.
    @discardableResult
    func refresh() async -> Set<String> {
        var resolved = Set<String>()

        for host in protectedHosts {
            let ips = await DNSResolver.shared.resolve(host: host)
            resolved.formUnion(ips)
            Logger.shared.debug("Resolved host", details: [
                "Host": host,
                "IPs": ips.joined(separator: ", ")
            ])
        }

        let decision = ProtectedIPPolicy.decide(
            hosts: protectedHosts,
            resolved: resolved,
            previous: protectedIPs
        )

        switch decision {
        case .noHosts:
            protectedIPs = []
            ConnectionRegistry.shared.setProtectedIPCount(0)
            Logger.shared.info("No protected hosts configured")

        case .updated(let ips):
            protectedIPs = ips
            ConnectionRegistry.shared.setProtectedIPCount(ips.count)
            Logger.shared.info("Protected IPs updated", details: [
                "Count": "\(ips.count)",
                "Hosts": protectedHosts.joined(separator: ", ")
            ])

        // Resolution failed for every host (e.g. the VPN just dropped and DNS is
        // unreachable). Keep the last known-good IPs instead of failing open.
        case .keptLastKnown(let ips):
            protectedIPs = ips
            ConnectionRegistry.shared.setProtectedIPCount(ips.count)
            Logger.shared.error("DNS refresh returned no IPs — keeping last known set", details: [
                "Hosts": protectedHosts.joined(separator: ", "),
                "KeptCount": "\(ips.count)"
            ])

        case .unresolved:
            protectedIPs = []
            ConnectionRegistry.shared.setProtectedIPCount(0)
            Logger.shared.error("DNS refresh returned no IPs", details: [
                "Hosts": protectedHosts.joined(separator: ", ")
            ])
        }

        return protectedIPs
    }
}

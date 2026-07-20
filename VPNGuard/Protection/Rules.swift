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
        var newIPs = Set<String>()

        for host in protectedHosts {
            let ips = await DNSResolver.shared.resolve(host: host)
            newIPs.formUnion(ips)
            Logger.shared.debug("Resolved host", details: [
                "Host": host,
                "IPs": ips.joined(separator: ", ")
            ])
        }

        protectedIPs = newIPs
        ConnectionRegistry.shared.setProtectedIPCount(newIPs.count)

        Logger.shared.info("Protected IPs updated", details: [
            "Count": "\(newIPs.count)",
            "Hosts": protectedHosts.joined(separator: ", ")
        ])

        return newIPs
    }
}

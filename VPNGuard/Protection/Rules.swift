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
        let saved = UserDefaults.standard.stringArray(
            forKey: Constants.DefaultsKey.protectedHosts
        ) ?? []
        let parsed = ProtectionHostParser.parse(saved)

        if parsed.hosts.isEmpty {
            protectedHosts = Constants.defaultProtectedHosts
        } else {
            protectedHosts = parsed.hosts
            // Migrate legacy values (URLs, mixed case) to the normalized form.
            if parsed.hosts != saved {
                UserDefaults.standard.set(
                    parsed.hosts,
                    forKey: Constants.DefaultsKey.protectedHosts
                )
            }
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

    func updateHosts(_ hosts: [String]) async -> Set<String> {
        protectedHosts = hosts
        UserDefaults.standard.set(hosts, forKey: Constants.DefaultsKey.protectedHosts)
        return await refresh()
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
        let hosts = protectedHosts

        // Resolve hosts concurrently: with several protected hosts, sequential
        // lookups would multiply the DNS timeout by the host count.
        await withTaskGroup(of: [String].self) { group in
            for host in hosts {
                group.addTask {
                    let ips = await DNSResolver.shared.resolve(host: host)
                    Logger.shared.debug("Resolved host", details: [
                        "Host": host,
                        "IPs": ips.joined(separator: ", ")
                    ])
                    return ips
                }
            }

            for await ips in group {
                resolved.formUnion(ips)
            }
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

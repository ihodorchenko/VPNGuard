//
//  PFRuleBuilder.swift
//  VPNGuard
//
//  Builds PF firewall rule sets for blocking protected host IPs.
//

import Foundation

/// Generates PF configuration content for the kill switch.
final class PFRuleBuilder: Sendable {

    static let shared = PFRuleBuilder()

    private init() {}

    /// Builds a complete PF rules file blocking TCP traffic to the given IPs.
    func buildRules(from ips: Set<String>) -> String {
        var lines: [String] = []
        lines.append("# VPNGuard Kill Switch Rules")
        lines.append("# Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")
        lines.append("set skip on lo0")
        lines.append("")

        for ip in ips.sorted() {
            if ip.contains(":") {
                // IPv6
                lines.append("block drop quick proto tcp to \(ip)")
                lines.append("block drop quick proto udp to \(ip) port 443")
            } else {
                // IPv4
                lines.append("block drop quick proto tcp to \(ip)")
                lines.append("block drop quick proto udp to \(ip) port 443")
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Builds an empty rules file (disables blocking).
    func buildEmptyRules() -> String {
        """
        # VPNGuard Kill Switch Rules (disabled)
        set skip on lo0

        """
    }
}

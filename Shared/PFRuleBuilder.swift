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

    /// Builds a complete PF rules file blocking TCP/UDP traffic to the given IPs.
    /// Note: no `set` directives — they are invalid inside nested anchors on macOS.
    func buildRules(from ips: Set<String>) -> String {
        var lines: [String] = []
        lines.append("# VPNGuard Kill Switch Rules")
        lines.append("# Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")

        for ip in ips.sorted() {
            lines.append("block drop quick proto tcp to \(ip)")
            lines.append("block drop quick proto udp to \(ip) port 443")
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Empty ruleset — loading this replaces any previous block rules.
    func buildEmptyRules() -> String {
        """
        # VPNGuard Kill Switch Rules (disabled)

        """
    }
}

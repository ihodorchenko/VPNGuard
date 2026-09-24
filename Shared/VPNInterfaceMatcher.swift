//
//  VPNInterfaceMatcher.swift
//  VPNGuard
//
//  Pure helpers for deciding whether a route's outgoing interface belongs to a
//  VPN. Kept free of app dependencies (no Logger, no UserDefaults) so the logic
//  can be unit-tested directly.
//

import Foundation

enum VPNInterfaceMatcher {

    /// Builds the list of interface prefixes that count as a VPN.
    ///
    /// An empty configured prefix falls back to the default instead of matching
    /// every interface, since `hasPrefix("")` is always true and would make the
    /// kill switch treat any route as a VPN route.
    static func interfacePrefixes(configured: String?, custom: String?) -> [String] {
        var prefixes = [String]()

        let trimmedCustom = custom?.trimmingCharacters(in: .whitespaces)
        if let trimmedCustom, !trimmedCustom.isEmpty {
            prefixes.append(trimmedCustom)
        }

        let configuredPrefix = (configured ?? Constants.defaultVPNInterfacePrefix)
            .trimmingCharacters(in: .whitespaces)
        let effectivePrefix = configuredPrefix.isEmpty
            ? Constants.defaultVPNInterfacePrefix
            : configuredPrefix

        if !prefixes.contains(effectivePrefix) {
            prefixes.append(effectivePrefix)
        }

        return prefixes
    }

    /// True if `interface` matches any of the given prefixes.
    static func interfaceMatches(_ interface: String, prefixes: [String]) -> Bool {
        for prefix in prefixes where !prefix.isEmpty {
            if interface.hasPrefix(prefix) || interface == prefix {
                return true
            }
        }
        return false
    }

    /// Parses `route -n get <host>` output and reports whether the outgoing
    /// interface matches a VPN prefix.
    static func routeUsesVPNInterface(in output: String, prefixes: [String]) -> Bool {
        for line in output.components(separatedBy: .newlines) {
            guard line.contains("interface:") else { continue }

            let interface = line
                .components(separatedBy: ":")
                .dropFirst()
                .joined(separator: ":")
                .trimmingCharacters(in: .whitespaces)

            if interfaceMatches(interface, prefixes: prefixes) {
                return true
            }
        }

        return false
    }
}

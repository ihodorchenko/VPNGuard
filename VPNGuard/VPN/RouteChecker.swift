//
//  RouteChecker.swift
//  VPNGuard
//
//  Checks whether traffic to a host routes through a VPN interface.
//

import Foundation

/// Executes `route -n get` and parses the outgoing interface.
final class RouteChecker: Sendable {

    static let shared = RouteChecker()

    private init() {}

    /// Returns true if the route to `host` uses a VPN interface (utun* or custom).
    func isVPNRoute(for host: String) -> Bool {
        guard let output = runRoute(host: host) else {
            return false
        }
        return parseInterface(from: output)
    }

    /// Reads VPN interface settings from UserDefaults.
    private var allowedInterfacePrefixes: [String] {
        var prefixes = [String]()

        let custom = UserDefaults.standard.string(
            forKey: Constants.DefaultsKey.customVPNInterface
        )?.trimmingCharacters(in: .whitespaces)

        if let custom, !custom.isEmpty {
            prefixes.append(custom)
        }

        let defaultPrefix = UserDefaults.standard.string(
            forKey: Constants.DefaultsKey.vpnInterfacePrefix
        ) ?? Constants.defaultVPNInterfacePrefix

        if !prefixes.contains(defaultPrefix) {
            prefixes.append(defaultPrefix)
        }

        // Common VPN interfaces: WireGuard, Tunnelblick, ProtonVPN, Mullvad
        let knownVPNPrefixes = ["utun", "ppp", "tap", "tun"]
        for known in knownVPNPrefixes where !prefixes.contains(where: { known.hasPrefix($0) || $0.hasPrefix(known) }) {
            if known == "utun" && !prefixes.contains(defaultPrefix) {
                continue
            }
        }

        return prefixes
    }

    // MARK: - Private

    private func runRoute(host: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", host]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            Logger.shared.error("route command failed", details: [
                "Host": host,
                "Error": error.localizedDescription
            ])
            return nil
        }

        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private func parseInterface(from text: String) -> Bool {
        let prefixes = allowedInterfacePrefixes

        for line in text.components(separatedBy: .newlines) {
            guard line.contains("interface:") else { continue }

            let iface = line
                .components(separatedBy: ":")
                .dropFirst()
                .joined(separator: ":")
                .trimmingCharacters(in: .whitespaces)

            for prefix in prefixes {
                if iface.hasPrefix(prefix) || iface == prefix {
                    return true
                }
            }
        }

        return false
    }
}

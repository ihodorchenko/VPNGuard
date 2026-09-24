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

    /// Async variant that runs the `route` process off the main thread so the
    /// menu bar UI stays responsive while a check is in flight.
    func isVPNRouteAsync(for host: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.isVPNRoute(for: host))
            }
        }
    }

    /// Reads VPN interface settings from UserDefaults.
    private var allowedInterfacePrefixes: [String] {
        VPNInterfaceMatcher.interfacePrefixes(
            configured: UserDefaults.standard.string(
                forKey: Constants.DefaultsKey.vpnInterfacePrefix
            ),
            custom: UserDefaults.standard.string(
                forKey: Constants.DefaultsKey.customVPNInterface
            )
        )
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
        VPNInterfaceMatcher.routeUsesVPNInterface(
            in: text,
            prefixes: allowedInterfacePrefixes
        )
    }
}

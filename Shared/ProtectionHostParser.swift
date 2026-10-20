//
//  ProtectionHostParser.swift
//  VPNGuard
//
//  Normalizes and validates user-supplied protected hosts. Kept in Shared so
//  the parsing rules are unit-testable and reusable by future config sources.
//

import Darwin
import Foundation

nonisolated struct ProtectionHostParseResult: Equatable, Sendable {
    let hosts: [String]
    let invalid: [String]
}

nonisolated enum ProtectionHostParser {

    /// Parses one-host-per-line input, dropping blanks, comments, duplicates,
    /// and entries that are not valid hostnames or IP addresses.
    static func parse(_ rawEntries: [String]) -> ProtectionHostParseResult {
        var hosts: [String] = []
        var invalid: [String] = []
        var seen = Set<String>()

        for raw in rawEntries {
            let entry = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entry.isEmpty, !entry.hasPrefix("#") else { continue }

            guard let host = normalize(entry) else {
                invalid.append(entry)
                continue
            }
            guard seen.insert(host).inserted else { continue }
            guard hosts.count < Constants.maxProtectedHosts else {
                invalid.append(entry)
                continue
            }
            hosts.append(host)
        }

        return ProtectionHostParseResult(hosts: hosts, invalid: invalid)
    }

    /// Accepts `example.com`, `https://example.com/path`, `example.com:443`,
    /// IPv4, and bracketed/unbracketed IPv6. Returns nil for anything else.
    static func normalize(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }

        // Inline comments and URL fragments.
        if let hash = value.firstIndex(of: "#") {
            value = String(value[..<hash])
        }

        let hadScheme = value.range(of: "://") != nil
        if let scheme = value.range(of: "://") {
            value = String(value[scheme.upperBound...])
        }

        // Paths and query strings are not meaningful for host resolution.
        if let delimiter = value.firstIndex(where: { $0 == "/" || $0 == "?" }) {
            let candidate = String(value[..<delimiter])
            // `10.0.0.0/8` is a CIDR, which this host-based pipeline cannot use.
            if !hadScheme, isIPAddress(candidate) {
                return nil
            }
            value = candidate
        }

        value = value.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("[") {
            guard let closing = value.firstIndex(of: "]") else { return nil }
            let literal = String(value[value.index(after: value.startIndex)..<closing])
            let suffix = value[value.index(after: closing)...]

            if !suffix.isEmpty {
                guard suffix.first == ":" else { return nil }
                guard isValidPort(String(suffix.dropFirst())) else { return nil }
            }

            guard isIPAddress(literal) else { return nil }
            return literal
        }

        let colonCount = value.filter { $0 == ":" }.count

        if colonCount == 1, let colon = value.firstIndex(of: ":") {
            let host = String(value[..<colon])
            let port = String(value[value.index(after: colon)...])
            guard isValidPort(port) else { return nil }
            value = host
        } else if colonCount > 1 {
            // Bare IPv6 literal — a port requires brackets, so treat as-is.
            return isIPAddress(value) ? value : nil
        }

        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !value.isEmpty else { return nil }

        if isIPAddress(value) { return value }
        return isValidHostname(value) ? value : nil
    }

    private static func isValidPort(_ value: String) -> Bool {
        guard !value.isEmpty, value.allSatisfy(\.isNumber), let port = Int(value) else {
            return false
        }
        return (1...65535).contains(port)
    }

    private static func isValidHostname(_ value: String) -> Bool {
        guard value.count <= 253 else { return false }

        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty else { return false }

        for label in labels {
            guard !label.isEmpty, label.count <= 63 else { return false }
            guard label.first != "-", label.last != "-" else { return false }
            guard label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
                return false
            }
        }

        return true
    }

    private static func isIPAddress(_ value: String) -> Bool {
        var ipv4 = in_addr()
        if inet_pton(AF_INET, value, &ipv4) == 1 {
            return true
        }

        var ipv6 = in6_addr()
        return inet_pton(AF_INET6, value, &ipv6) == 1
    }
}

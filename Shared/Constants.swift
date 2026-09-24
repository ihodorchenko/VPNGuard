//
//  Constants.swift
//  VPNGuard
//
//  Application-wide constants for bundle IDs, paths, and defaults.
//

import Foundation

enum Constants {

    // MARK: - Bundle Identifiers

    static let appBundleID = "by.home.VPNGuard"
    static let helperBundleID = "by.home.VPNGuard.helper"
    static let helperLabel = "by.home.VPNGuard.helper"

    // MARK: - Paths

    /// PF rules file written by the privileged helper.
    static let pfConfigPath = "/var/run/vpnguard/pf.conf"

    /// PF anchor name — nested under com.apple/* (declared in /etc/pf.conf).
    static let pfAnchorName = "com.apple/vpnguard"

    /// Directory for application logs.
    static let logsDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Logs/VPNGuard", isDirectory: true)
    }()

    // MARK: - UserDefaults Keys

    enum DefaultsKey {
        static let vpnInterfacePrefix = "vpnInterfacePrefix"
        static let customVPNInterface = "customVPNInterface"
        static let protectedHosts = "protectedHosts"
        static let autoStart = "autoStart"
        static let protectionEnabled = "protectionEnabled"
    }

    // MARK: - Defaults

    static let defaultProtectedHosts = [
        "claude.ai",
        "api.anthropic.com"
    ]

    static let defaultVPNInterfacePrefix = "utun"

    /// Interval between VPN route checks (seconds).
    static let vpnCheckInterval: TimeInterval = 2.0

    /// Interval between DNS refresh cycles (seconds).
    static let dnsRefreshInterval: TimeInterval = 300.0

    // MARK: - Timeouts

    /// Hard timeout for subprocess calls (`route`, `pfctl`, `launchctl`).
    static let commandTimeout: TimeInterval = 5.0

    /// How long to wait for DNS resolution before giving up (returns no IPs).
    static let dnsTimeout: TimeInterval = 5.0

    /// How long to wait for an XPC reply before treating it as failed.
    static let xpcReplyTimeout: TimeInterval = 8.0

    // MARK: - Logging Limits

    /// Max size of a single daily log file before it is truncated.
    static let maxLogFileBytes: UInt64 = 2 * 1024 * 1024 // 2 MB

    /// How many days of log files to keep.
    static let maxLogRetentionDays: Int = 7

    /// Soft cap on total size of the log directory.
    static let maxLogDirectoryBytes: UInt64 = 10 * 1024 * 1024 // 10 MB

    /// XPC connection Mach service name for the privileged helper.
    static let helperMachServiceName = "by.home.VPNGuard.helper"
}

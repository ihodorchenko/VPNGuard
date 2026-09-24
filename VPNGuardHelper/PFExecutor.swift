//
//  PFExecutor.swift
//  VPNGuardHelper
//
//  Executes pfctl commands as root to manage the VPNGuard PF anchor.
//
//  On modern macOS, /etc/pf.conf declares `anchor "com.apple/*"`.
//  We load rules into `com.apple/vpnguard` without modifying /etc/pf.conf.
//

import Foundation
import os.log

enum PFExecutorError: LocalizedError {
    case commandFailed(String, Int32, String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let cmd, let code, let output):
            return "pfctl failed (\(code)): \(cmd)\n\(output)"
        case .writeFailed(let path):
            return "Failed to write PF config to \(path)"
        }
    }
}

/// Runs pfctl and manages PF configuration files.
final class PFExecutor {

    private let configPath = Constants.pfConfigPath
    private let anchorName = Constants.pfAnchorName
    private let log = OSLog(subsystem: Constants.helperBundleID, category: "PFExecutor")
    private var pfEnabledByUs = false
    private var pfToken: String?

    // MARK: - Bootstrap

    /// Creates runtime dir, enables PF, and loads an empty anchor ruleset.
    func bootstrapAnchor() throws {
        try ensureRuntimeDirectory()
        try writeConfig(content: PFRuleBuilder.shared.buildEmptyRules())
        try enablePF()
        try loadAnchorRules()
        logInfo("PF anchor \(anchorName) bootstrapped")
    }

    func ensureRuntimeDirectory() throws {
        let runDir = "/var/run/vpnguard"
        try FileManager.default.createDirectory(
            atPath: runDir,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Config

    func writeConfig(content: String) throws {
        do {
            try ensureRuntimeDirectory()
            try content.write(toFile: configPath, atomically: true, encoding: .utf8)
        } catch {
            throw PFExecutorError.writeFailed(configPath)
        }
    }

    // MARK: - PF Control

    /// Loads rules into the com.apple/vpnguard anchor.
    func loadAnchorRules() throws {
        try runPFCTL(["-a", anchorName, "-f", configPath])
    }

    func flushAnchor() throws {
        // Hard-flush all rules in the anchor, then load an empty file.
        _ = try? runPFCTL(["-a", anchorName, "-F", "all"])
        try writeConfig(content: PFRuleBuilder.shared.buildEmptyRules())
        try runPFCTL(["-a", anchorName, "-f", configPath])
        logInfo("PF anchor \(anchorName) flushed")
    }

    /// Enables PF using reference-counted -E (required on modern macOS).
    func enablePF() throws {
        guard !pfEnabledByUs else { return }
        // -E returns 0 on success; may return non-zero if already enabled by us
        let output = try runPFCTL(["-E"])
        pfEnabledByUs = true
        pfToken = PFTokenParser.parseReferenceToken(from: output)
        logInfo("PF enabled: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    /// Releases the PF enable reference taken by `enablePF`, restoring the
    /// system's prior PF state. Best-effort: failures are logged, not thrown.
    func releasePF() {
        guard pfEnabledByUs else { return }
        defer {
            pfEnabledByUs = false
            pfToken = nil
        }

        guard let token = pfToken else {
            logInfo("PF release skipped — no reference token was captured")
            return
        }

        do {
            _ = try runPFCTL(["-X", token])
            logInfo("PF enable reference released (token \(token))")
        } catch {
            logError("Failed to release PF reference: \(error.localizedDescription)")
        }
    }

    /// Kills existing TCP/UDP states to blocked IPs, tearing down active connections.
    func killStates(for ips: [String]) throws {
        for ip in ips {
            _ = try? runPFCTL(["-k", ip])
        }
    }

    // MARK: - Diagnostics

    func anchorIsRegistered() -> Bool {
        anchorHasRules() || anchorAppearsInList()
    }

    private func anchorHasRules() -> Bool {
        guard let output = try? runPFCTL(["-a", anchorName, "-s", "rules"]) else {
            return false
        }
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func anchorAppearsInList() -> Bool {
        guard let output = try? runPFCTL(["-s", "Anchors"]) else {
            return false
        }
        return output.contains("vpnguard")
    }

    // MARK: - Process

    @discardableResult
    private func runPFCTL(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/pfctl")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let exitCode = process.terminationStatus

        if exitCode != 0 {
            logError("pfctl \(arguments.joined(separator: " ")) exit \(exitCode): \(output)")
            throw PFExecutorError.commandFailed(
                "pfctl \(arguments.joined(separator: " "))",
                exitCode,
                output.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return output
    }

    private func logInfo(_ message: String) {
        os_log("%{public}@", log: log, type: .info, message)
    }

    private func logError(_ message: String) {
        os_log("%{public}@", log: log, type: .error, message)
    }
}

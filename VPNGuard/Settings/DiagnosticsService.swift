//
//  DiagnosticsService.swift
//  VPNGuard
//
//  Runs connectivity and PF rule checks for the Help panel.
//

import Foundation

struct DiagnosticsSnapshot: Sendable {
    let vpnState: String
    let protectionEnabled: Bool
    let appBlocking: Bool
    let helperInstalled: Bool
    let pfConfigPreview: String
    let pfRulesOutput: String
    let pfRulesReadable: Bool
    let claudeReachable: Bool
    let claudeDetail: String
    let apiReachable: Bool
    let apiDetail: String
    let helperRunning: Bool
    let helperDetail: String
    let checkedAt: Date
}

nonisolated enum DiagnosticsService {

    static func run(
        vpnState: String,
        protectionEnabled: Bool,
        appBlocking: Bool,
        helperInstalled: Bool
    ) async -> DiagnosticsSnapshot {
        async let claude = checkHTTP(url: URL(string: "https://claude.ai")!)
        async let api = checkHTTP(url: URL(string: "https://api.anthropic.com")!)
        async let pfRules = readPFRules()
        async let helper = checkHelperProcess()

        let claudeResult = await claude
        let apiResult = await api
        let pfResult = await pfRules
        let helperResult = await helper

        return DiagnosticsSnapshot(
            vpnState: vpnState,
            protectionEnabled: protectionEnabled,
            appBlocking: appBlocking,
            helperInstalled: helperInstalled,
            pfConfigPreview: readPFConfigPreview(),
            pfRulesOutput: pfResult.output,
            pfRulesReadable: pfResult.readable,
            claudeReachable: claudeResult.reachable,
            claudeDetail: claudeResult.detail,
            apiReachable: apiResult.reachable,
            apiDetail: apiResult.detail,
            helperRunning: helperResult.running,
            helperDetail: helperResult.detail,
            checkedAt: Date()
        )
    }

    // MARK: - HTTP

    private static func checkHTTP(url: URL) async -> (reachable: Bool, detail: String) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                // Any HTTP response means the connection reached the server.
                return (true, "HTTP \(http.statusCode)")
            }
            return (true, "Response received")
        } catch let error as URLError where error.code == .timedOut {
            return (false, "Timeout — connection blocked or network unavailable")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - PF

    private static func readPFConfigPreview() -> String {
        guard let text = try? String(
            contentsOfFile: Constants.pfConfigPath,
            encoding: .utf8
        ) else {
            return "(file not found or not readable)"
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("# VPNGuard disabled") {
            return "(empty — no block rules in config file)"
        }

        let lines = trimmed.components(separatedBy: .newlines)
        let preview = lines.prefix(6).joined(separator: "\n")
        if lines.count > 6 {
            return preview + "\n… (\(lines.count) lines total)"
        }
        return preview
    }

    private static func readPFRules() async -> (output: String, readable: Bool) {
        let result = ProcessRunner.run(
            executable: "/sbin/pfctl",
            arguments: ["-a", Constants.pfAnchorName, "-s", "rules"],
            timeout: Constants.commandTimeout
        )

        guard result.launched else {
            return ("pfctl could not be launched", false)
        }
        if result.timedOut {
            return ("pfctl timed out after \(Int(Constants.commandTimeout))s", false)
        }

        let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)

        if result.exitCode == 0 {
            if text.isEmpty {
                return ("(no rules in anchor — traffic not blocked by PF)", true)
            }
            return (text, true)
        }

        if text.lowercased().contains("permission") || text.lowercased().contains("denied") {
            return ("Requires sudo — use Terminal command from Help section below.", false)
        }

        return (text.isEmpty ? "pfctl failed (exit \(result.exitCode))" : text, false)
    }

    // MARK: - Helper

    private static func checkHelperProcess() async -> (running: Bool, detail: String) {
        let result = ProcessRunner.run(
            executable: "/bin/launchctl",
            arguments: ["list"],
            timeout: Constants.commandTimeout
        )

        guard result.launched else {
            return (false, "launchctl could not be launched")
        }
        if result.timedOut {
            return (false, "launchctl timed out")
        }

        let label = Constants.helperLabel

        for line in result.output.components(separatedBy: .newlines) {
            if line.contains(label) {
                let parts = line.split(whereSeparator: \.isWhitespace)
                if parts.count >= 3, parts[1] == "0" {
                    return (true, "Running (PID \(parts[0]))")
                }
                return (false, "Registered but not running: \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

        return (false, "Not found in launchctl list")
    }
}

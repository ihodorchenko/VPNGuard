//
//  Logger.swift
//  VPNGuard
//
//  File-based logger writing to ~/Library/Logs/VPNGuard/
//

import AppKit
import Foundation
import os.log

enum LogLevel: String, Sendable {
    case info = "INFO"
    case security = "SECURITY"
    case error = "ERROR"
    case debug = "DEBUG"
}

/// Thread-safe file logger with structured multi-line output.
final class Logger: @unchecked Sendable {

    static let shared = Logger()

    private let queue = DispatchQueue(label: "by.home.VPNGuard.logger")
    private let osLog = OSLog(subsystem: Constants.appBundleID, category: "VPNGuard")
    private let dateFormatter: DateFormatter

    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        ensureLogDirectory()
    }

    // MARK: - Public API

    func info(_ message: String, details: [String: String] = [:]) {
        write(level: .info, message: message, details: details)
    }

    func security(_ message: String, details: [String: String] = [:]) {
        write(level: .security, message: message, details: details)
    }

    func error(_ message: String, details: [String: String] = [:]) {
        write(level: .error, message: message, details: details)
    }

    func debug(_ message: String, details: [String: String] = [:]) {
        #if DEBUG
        write(level: .debug, message: message, details: details)
        #endif
    }

    /// Opens the log directory in Finder.
    func revealLogsInFinder() {
        NSWorkspace.shared.open(Constants.logsDirectory)
    }

    // MARK: - Private

    private func ensureLogDirectory() {
        try? FileManager.default.createDirectory(
            at: Constants.logsDirectory,
            withIntermediateDirectories: true
        )
    }

    private func logFileURL(for date: Date) -> URL {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        let day = dayFormatter.string(from: date)
        return Constants.logsDirectory.appendingPathComponent("\(day).log")
    }

    private func write(level: LogLevel, message: String, details: [String: String]) {
        queue.async { [self] in
            let timestamp = dateFormatter.string(from: Date())
            var lines = [
                timestamp,
                "",
                level.rawValue,
                "",
                message
            ]

            for (key, value) in details.sorted(by: { $0.key < $1.key }) {
                lines.append("")
                lines.append("\(key):")
                lines.append(value)
            }

            lines.append("")
            lines.append("")

            let entry = lines.joined(separator: "\n")
            let url = logFileURL(for: Date())

            if let data = entry.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: url.path) {
                    if let handle = try? FileHandle(forWritingTo: url) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: url)
                }
            }

            os_log("%{public}@", log: osLog, type: level == .error ? .error : .info, message)
        }
    }
}

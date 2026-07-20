//
//  Logger.swift
//  VPNGuard
//
//  File-based logger writing to ~/Library/Logs/VPNGuard/
//  Enforces per-file size, retention days, and total directory size caps.
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

/// Thread-safe file logger with structured multi-line output and size limits.
final class Logger: @unchecked Sendable {

    static let shared = Logger()

    private let queue = DispatchQueue(label: "by.home.VPNGuard.logger")
    private let osLog = OSLog(subsystem: Constants.appBundleID, category: "VPNGuard")
    private let dateFormatter: DateFormatter
    private let dayFormatter: DateFormatter
    private var lastPruneAt: Date = .distantPast

    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")

        ensureLogDirectory()
        queue.async { [self] in
            pruneLogsIfNeeded(force: true)
        }
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
        let day = dayFormatter.string(from: date)
        return Constants.logsDirectory.appendingPathComponent("\(day).log")
    }

    private func write(level: LogLevel, message: String, details: [String: String]) {
        queue.async { [self] in
            pruneLogsIfNeeded(force: false)

            let now = Date()
            let timestamp = dateFormatter.string(from: now)
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
            let url = logFileURL(for: now)

            guard let data = entry.data(using: .utf8) else { return }

            enforceFileSizeLimit(at: url, appending: data.count)
            append(data, to: url)

            os_log("%{public}@", log: osLog, type: level == .error ? .error : .info, message)
        }
    }

    private func append(_ data: Data, to url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// If the daily file would exceed the cap, keep only the trailing half.
    private func enforceFileSizeLimit(at url: URL, appending incoming: Int) {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64 else { return }

        let projected = size + UInt64(incoming)
        guard projected > Constants.maxLogFileBytes else { return }

        // Keep the newest ~half of the file so recent context survives.
        let keepBytes = Constants.maxLogFileBytes / 2
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            try? fm.removeItem(at: url)
            return
        }

        let fileSize = handle.seekToEndOfFile()
        let offset = fileSize > keepBytes ? fileSize - keepBytes : 0
        try? handle.seek(toOffset: offset)
        var retained = handle.readDataToEndOfFile()
        try? handle.close()

        // Drop a partial first line if we mid-cut the file.
        if offset > 0, let nl = retained.firstIndex(of: UInt8(ascii: "\n")) {
            retained = retained[retained.index(after: nl)...]
            retained = Data(retained)
        }

        let marker = Data(
            "\n--- log truncated (\(byteString(Constants.maxLogFileBytes)) limit) ---\n\n"
                .utf8
        )
        try? (marker + retained).write(to: url, options: .atomic)
    }

    /// Deletes old day files and enforces the directory size cap.
    private func pruneLogsIfNeeded(force: Bool) {
        let now = Date()
        // Prune at most once per hour unless forced (startup).
        if !force, now.timeIntervalSince(lastPruneAt) < 3600 { return }
        lastPruneAt = now

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: Constants.logsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -Constants.maxLogRetentionDays,
            to: now
        ) ?? now

        var survivors: [(url: URL, date: Date, size: UInt64)] = []

        for url in files where url.pathExtension == "log" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modified = values?.contentModificationDate ?? .distantPast
            let size = UInt64(values?.fileSize ?? 0)

            if modified < cutoff {
                try? fm.removeItem(at: url)
                continue
            }
            survivors.append((url, modified, size))
        }

        // Oldest first — delete until under the directory cap.
        survivors.sort { $0.date < $1.date }
        var total = survivors.reduce(UInt64(0)) { $0 + $1.size }

        while total > Constants.maxLogDirectoryBytes, let oldest = survivors.first {
            try? fm.removeItem(at: oldest.url)
            total -= oldest.size
            survivors.removeFirst()
        }
    }

    private func byteString(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.0f MB", mb)
    }
}

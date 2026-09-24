//
//  Timeout.swift
//  VPNGuard
//
//  Race an async operation against a deadline. Kept in Shared so it can be
//  unit-tested.
//

import Foundation

nonisolated enum Timeout {

    /// Returns the operation's result, or `nil` if it did not finish within
    /// `seconds`. The operation keeps running in the background afterwards —
    /// acceptable for tasks that cannot be cancelled (e.g. `getaddrinfo`), and
    /// far better than blocking the caller forever.
    static func race<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async -> T
    ) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let once = ResumeOnce()

            Task {
                let value = await operation()
                once.run { continuation.resume(returning: value) }
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                once.run { continuation.resume(returning: nil) }
            }
        }
    }
}

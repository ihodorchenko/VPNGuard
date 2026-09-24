//
//  ResumeOnce.swift
//  VPNGuard
//
//  A thread-safe one-shot latch, used to guarantee a continuation is resumed
//  exactly once when racing an operation against a timeout.
//

import Foundation

nonisolated final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    /// Runs `body` only for the first caller; later calls are no-ops.
    func run(_ body: () -> Void) {
        lock.lock()
        if done {
            lock.unlock()
            return
        }
        done = true
        lock.unlock()
        body()
    }
}

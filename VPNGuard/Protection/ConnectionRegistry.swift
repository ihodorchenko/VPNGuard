//
//  ConnectionRegistry.swift
//  VPNGuard
//
//  Tracks blocked connection attempts and protected IP count.
//

import Foundation
import Combine

/// Registry of blocked connections for menu bar display.
@MainActor
final class ConnectionRegistry: ObservableObject {

    static let shared = ConnectionRegistry()

    @Published private(set) var blockedCount: Int = 0
    @Published private(set) var protectedIPCount: Int = 0

    private init() {}

    func setProtectedIPCount(_ count: Int) {
        protectedIPCount = count
    }

    func recordBlocked(host: String, reason: String) {
        blockedCount += 1
        Logger.shared.security("Blocked connection", details: [
            "Host": host,
            "Reason": reason
        ])
    }

    func resetBlockedCount() {
        blockedCount = 0
    }
}

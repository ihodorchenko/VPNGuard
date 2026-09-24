//
//  ProtectionPolicyTests.swift
//  VPNGuardCoreTests
//

import XCTest
@testable import VPNGuardCore

final class ProtectionPolicyTests: XCTestCase {

    func testConnectedSteadyStateDoesNothing() {
        XCTAssertEqual(
            ProtectionPolicy.decide(
                vpnConnected: true,
                isBlocking: false,
                protectionEnabled: true
            ),
            ProtectionDecision(state: .connected, action: .none)
        )
    }

    /// Recovery: VPN came back but blocks are still active (e.g. a previous
    /// flush failed) — the policy must actively disable them.
    func testConnectedWithStaleBlockingDisables() {
        XCTAssertEqual(
            ProtectionPolicy.decide(
                vpnConnected: true,
                isBlocking: true,
                protectionEnabled: true
            ),
            ProtectionDecision(state: .connected, action: .disable)
        )
    }

    func testDisconnectedEdgeEnablesBlocking() {
        XCTAssertEqual(
            ProtectionPolicy.decide(
                vpnConnected: false,
                isBlocking: false,
                protectionEnabled: true
            ),
            ProtectionDecision(state: .disconnected, action: .enable)
        )
    }

    func testDisconnectedSteadyStateDoesNothing() {
        XCTAssertEqual(
            ProtectionPolicy.decide(
                vpnConnected: false,
                isBlocking: true,
                protectionEnabled: true
            ),
            ProtectionDecision(state: .disconnected, action: .none)
        )
    }

    func testProtectionDisabledNeverStartsBlocking() {
        XCTAssertEqual(
            ProtectionPolicy.decide(
                vpnConnected: false,
                isBlocking: false,
                protectionEnabled: false
            ),
            ProtectionDecision(state: .disconnected, action: .none)
        )
    }

    func testProtectionDisabledClearsStaleBlocking() {
        XCTAssertEqual(
            ProtectionPolicy.decide(
                vpnConnected: false,
                isBlocking: true,
                protectionEnabled: false
            ),
            ProtectionDecision(state: .disconnected, action: .disable)
        )
    }
}

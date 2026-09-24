//
//  ProtectedIPPolicyTests.swift
//  VPNGuardCoreTests
//

import XCTest
@testable import VPNGuardCore

final class ProtectedIPPolicyTests: XCTestCase {

    func testNoHostsConfiguredYieldsNoHosts() {
        XCTAssertEqual(
            ProtectedIPPolicy.decide(
                hosts: [],
                resolved: ["203.0.113.5"],
                previous: ["198.51.100.1"]
            ),
            .noHosts
        )
    }

    func testFreshResolutionReplacesPreviousSet() {
        XCTAssertEqual(
            ProtectedIPPolicy.decide(
                hosts: ["example.com"],
                resolved: ["203.0.113.5", "203.0.113.6"],
                previous: ["198.51.100.1"]
            ),
            .updated(["203.0.113.5", "203.0.113.6"])
        )
    }

    /// Regression: resolution failed but a previous set exists — keep it. An
    /// empty set would silently disable the kill switch (fail-open).
    func testResolutionFailureKeepsLastKnownSet() {
        XCTAssertEqual(
            ProtectedIPPolicy.decide(
                hosts: ["example.com"],
                resolved: [],
                previous: ["203.0.113.5"]
            ),
            .keptLastKnown(["203.0.113.5"])
        )
    }

    func testResolutionFailureWithoutHistoryIsUnresolved() {
        XCTAssertEqual(
            ProtectedIPPolicy.decide(
                hosts: ["example.com"],
                resolved: [],
                previous: []
            ),
            .unresolved
        )
    }

    func testNoHostsTakesPrecedenceOverResolved() {
        // Even if something was resolved, an empty host list means no protection.
        XCTAssertEqual(
            ProtectedIPPolicy.decide(hosts: [], resolved: [], previous: ["203.0.113.5"]),
            .noHosts
        )
    }
}

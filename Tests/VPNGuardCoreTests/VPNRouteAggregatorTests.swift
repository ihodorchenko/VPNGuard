//
//  VPNRouteAggregatorTests.swift
//  VPNGuardCoreTests
//

import XCTest
@testable import VPNGuardCore

final class VPNRouteAggregatorTests: XCTestCase {

    /// No protected hosts configured — the monitor treats this as "not connected".
    func testNoChecksIsDisconnected() {
        XCTAssertEqual(VPNRouteAggregator.aggregate(checks: []), .disconnected)
    }

    func testSingleTrueIsConnected() {
        XCTAssertEqual(VPNRouteAggregator.aggregate(checks: [true]), .connected)
    }

    func testSingleFalseIsDisconnected() {
        XCTAssertEqual(VPNRouteAggregator.aggregate(checks: [false]), .disconnected)
    }

    func testAllTrueIsConnected() {
        XCTAssertEqual(VPNRouteAggregator.aggregate(checks: [true, true, true]), .connected)
    }

    /// Every protected host must route through the VPN — one miss is enough.
    func testAnyFalseIsDisconnected() {
        XCTAssertEqual(VPNRouteAggregator.aggregate(checks: [true, false, true]), .disconnected)
        XCTAssertEqual(VPNRouteAggregator.aggregate(checks: [false, true, true]), .disconnected)
        XCTAssertEqual(VPNRouteAggregator.aggregate(checks: [true, true, false]), .disconnected)
    }
}

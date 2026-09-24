//
//  VPNInterfaceMatcherTests.swift
//  VPNGuardCoreTests
//

import XCTest
@testable import VPNGuardCore

final class VPNInterfaceMatcherTests: XCTestCase {

    // MARK: - Prefix construction

    func testNilConfiguredUsesDefaultPrefix() {
        XCTAssertEqual(
            VPNInterfaceMatcher.interfacePrefixes(configured: nil, custom: nil),
            ["utun"]
        )
    }

    /// Regression: an empty configured prefix must fall back to the default
    /// rather than matching every interface (silent fail-open).
    func testEmptyConfiguredPrefixFallsBackToDefault() {
        XCTAssertEqual(
            VPNInterfaceMatcher.interfacePrefixes(configured: "", custom: nil),
            ["utun"]
        )
        XCTAssertEqual(
            VPNInterfaceMatcher.interfacePrefixes(configured: "   ", custom: nil),
            ["utun"]
        )
    }

    func testCustomInterfaceIsIncluded() {
        XCTAssertEqual(
            VPNInterfaceMatcher.interfacePrefixes(configured: "utun", custom: "wg0"),
            ["wg0", "utun"]
        )
    }

    func testDuplicatePrefixesAreDeduplicated() {
        XCTAssertEqual(
            VPNInterfaceMatcher.interfacePrefixes(configured: "wg0", custom: "wg0"),
            ["wg0"]
        )
    }

    func testPrefixesAreTrimmed() {
        XCTAssertEqual(
            VPNInterfaceMatcher.interfacePrefixes(configured: "  utun  ", custom: nil),
            ["utun"]
        )
    }

    // MARK: - Matching

    func testInterfaceMatching() {
        XCTAssertTrue(VPNInterfaceMatcher.interfaceMatches("utun3", prefixes: ["utun"]))
        XCTAssertTrue(VPNInterfaceMatcher.interfaceMatches("utun", prefixes: ["utun"]))
        XCTAssertFalse(VPNInterfaceMatcher.interfaceMatches("en0", prefixes: ["utun"]))
    }

    /// Defensive: a stray empty prefix must never match every interface.
    func testEmptyPrefixNeverMatches() {
        XCTAssertFalse(VPNInterfaceMatcher.interfaceMatches("en0", prefixes: [""]))
    }

    // MARK: - Route output parsing

    private let vpnRoute = """
    route to: 104.18.0.1
    destination: 104.18.0.1
      gateway: 192.168.1.1
      interface: utun3
    """

    private let plainRoute = """
    route to: 93.184.216.34
    destination: 93.184.216.34
      gateway: 192.168.1.1
      interface: en0
    """

    func testVPNRouteDetected() {
        XCTAssertTrue(
            VPNInterfaceMatcher.routeUsesVPNInterface(in: vpnRoute, prefixes: ["utun"])
        )
    }

    func testPlainRouteNotDetected() {
        XCTAssertFalse(
            VPNInterfaceMatcher.routeUsesVPNInterface(in: plainRoute, prefixes: ["utun"])
        )
    }

    func testCustomPrefixRouteDetected() {
        let route = plainRoute.replacingOccurrences(of: "en0", with: "wg0")
        XCTAssertTrue(
            VPNInterfaceMatcher.routeUsesVPNInterface(in: route, prefixes: ["wg0"])
        )
    }

    func testOutputWithoutInterfaceLineIsNotVPN() {
        XCTAssertFalse(
            VPNInterfaceMatcher.routeUsesVPNInterface(
                in: "route: writing to routing socket: not in table",
                prefixes: ["utun"]
            )
        )
    }
}

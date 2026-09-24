//
//  PFRuleBuilderTests.swift
//  VPNGuardCoreTests
//

import XCTest
@testable import VPNGuardCore

final class PFRuleBuilderTests: XCTestCase {

    /// An empty IP set produces no `block` rules. Loading such a file is a
    /// no-op, which is exactly why the helper must refuse to report it as
    /// active blocking (fail-open guard).
    func testEmptyIPSetProducesNoBlockRules() {
        let rules = PFRuleBuilder.shared.buildRules(from: [])
        XCTAssertFalse(rules.contains("block"))
    }

    func testEachIPGetsTCPAndUDP443Rules() {
        let rules = PFRuleBuilder.shared.buildRules(from: ["203.0.113.5"])
        XCTAssertTrue(rules.contains("block drop quick proto tcp to 203.0.113.5"))
        XCTAssertTrue(rules.contains("block drop quick proto udp to 203.0.113.5 port 443"))
    }

    func testRulesAreDeterministicallySorted() {
        let rules = PFRuleBuilder.shared.buildRules(
            from: ["203.0.113.9", "203.0.113.5", "198.51.100.1"]
        )

        let tcpLines = rules
            .components(separatedBy: .newlines)
            .filter { $0.hasPrefix("block drop quick proto tcp") }

        XCTAssertEqual(tcpLines, [
            "block drop quick proto tcp to 198.51.100.1",
            "block drop quick proto tcp to 203.0.113.5",
            "block drop quick proto tcp to 203.0.113.9"
        ])
    }

    func testEmptyRulesAreMarkedDisabled() {
        let rules = PFRuleBuilder.shared.buildEmptyRules()
        XCTAssertTrue(rules.contains("disabled"))
        XCTAssertFalse(rules.contains("block drop"))
    }
}

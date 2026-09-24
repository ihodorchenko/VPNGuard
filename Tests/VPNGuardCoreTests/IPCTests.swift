//
//  IPCTests.swift
//  VPNGuardCoreTests
//

import XCTest
@testable import VPNGuardCore

final class IPCTests: XCTestCase {

    /// These integers are the XPC wire contract with an already-installed
    /// helper — changing them silently would break communication with a
    /// blessed helper that expects the old values.
    func testHelperCommandRawValuesAreStable() {
        XCTAssertEqual(HelperCommand.enableBlock.rawValue, 1)
        XCTAssertEqual(HelperCommand.disableBlock.rawValue, 2)
        XCTAssertEqual(HelperCommand.refreshRules.rawValue, 3)
        XCTAssertEqual(HelperCommand.getStatus.rawValue, 4)
        XCTAssertEqual(HelperCommand.setupAnchor.rawValue, 5)
    }

    func testUnknownHelperCommandRawValueIsNil() {
        XCTAssertNil(HelperCommand(rawValue: 99))
    }

    func testDefaultProtectedHosts() {
        XCTAssertEqual(
            Constants.defaultProtectedHosts,
            ["claude.ai", "api.anthropic.com"]
        )
    }
}

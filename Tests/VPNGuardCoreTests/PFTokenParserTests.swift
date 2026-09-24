//
//  PFTokenParserTests.swift
//  VPNGuardCoreTests
//

import XCTest
@testable import VPNGuardCore

final class PFTokenParserTests: XCTestCase {

    func testParsesTokenFromTypicalOutput() {
        let output = """
        pf enabled
        token : 1680000000
        """
        XCTAssertEqual(PFTokenParser.parseReferenceToken(from: output), "1680000000")
    }

    func testParsesTokenWithoutSpaceBeforeColon() {
        XCTAssertEqual(PFTokenParser.parseReferenceToken(from: "token: 42"), "42")
    }

    func testParsesTokenWithTabsAndExtraSpaces() {
        XCTAssertEqual(PFTokenParser.parseReferenceToken(from: "token \t:   99  "), "99")
    }

    func testReturnsNilWhenThereIsNoToken() {
        XCTAssertNil(PFTokenParser.parseReferenceToken(from: "pf enabled"))
    }

    /// A "token" line without a value must not be mistaken for a real token.
    func testReturnsNilWhenTokenValueIsMissing() {
        XCTAssertNil(PFTokenParser.parseReferenceToken(from: "token :"))
    }
}

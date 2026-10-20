//
//  ProtectionHostParserTests.swift
//  VPNGuardCoreTests
//

import XCTest
@testable import VPNGuardCore

final class ProtectionHostParserTests: XCTestCase {

    // MARK: - Normalization

    func testHostsAreTrimmedLowercasedAndDeduplicated() {
        let result = ProtectionHostParser.parse([
            "  Example.COM ",
            "example.com",
            "api.example.com."
        ])

        XCTAssertEqual(result.hosts, ["example.com", "api.example.com"])
        XCTAssertTrue(result.invalid.isEmpty)
    }

    func testBlankLinesAndCommentsAreIgnored() {
        let result = ProtectionHostParser.parse([
            "",
            "   ",
            "# comment",
            "example.com # inline comment"
        ])

        XCTAssertEqual(result.hosts, ["example.com"])
        XCTAssertTrue(result.invalid.isEmpty)
    }

    func testURLSchemePathQueryAndPortAreStripped() {
        XCTAssertEqual(
            ProtectionHostParser.normalize("https://API.Example.com:443/v1/models?x=1"),
            "api.example.com"
        )
        XCTAssertEqual(
            ProtectionHostParser.normalize("http://example.com/path"),
            "example.com"
        )
        XCTAssertEqual(
            ProtectionHostParser.normalize("example.com/path"),
            "example.com"
        )
        XCTAssertEqual(
            ProtectionHostParser.normalize("example.com:8443"),
            "example.com"
        )
    }

    func testCIDRIsRejectedBecauseHostsAreResolvedToSingleIPs() {
        XCTAssertNil(ProtectionHostParser.normalize("10.0.0.0/8"))
        XCTAssertNil(ProtectionHostParser.normalize("2001:db8::/32"))
    }

    // MARK: - IP addresses

    func testIPv4AndIPv6AreAccepted() {
        XCTAssertEqual(ProtectionHostParser.normalize("192.168.1.10"), "192.168.1.10")
        XCTAssertEqual(ProtectionHostParser.normalize("192.168.1.10:443"), "192.168.1.10")
        XCTAssertEqual(ProtectionHostParser.normalize("2001:db8::1"), "2001:db8::1")
        XCTAssertEqual(ProtectionHostParser.normalize("[2001:db8::1]:443"), "2001:db8::1")
    }

    // MARK: - Invalid entries

    func testInvalidEntriesAreReported() {
        let result = ProtectionHostParser.parse([
            "bad_host",
            "-bad.com",
            "bad-.com",
            "exa mple.com",
            "exa..mple.com",
            "http://",
            "example.com:notaport",
            "example.com:0"
        ])

        XCTAssertTrue(result.hosts.isEmpty)
        XCTAssertEqual(result.invalid.count, 8)
    }

    func testHostCountIsCapped() {
        let entries = (1...(Constants.maxProtectedHosts + 2)).map {
            "host\($0).example.com"
        }
        let result = ProtectionHostParser.parse(entries)

        XCTAssertEqual(result.hosts.count, Constants.maxProtectedHosts)
        XCTAssertEqual(result.invalid.count, 2)
    }
}

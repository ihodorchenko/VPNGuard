//
//  TimeoutTests.swift
//  VPNGuardCoreTests
//

import XCTest
@testable import VPNGuardCore

final class TimeoutTests: XCTestCase {

    func testReturnsFastResult() async {
        let value = await Timeout.race(seconds: 5) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testReturnsNilWhenOperationIsTooSlow() async {
        let start = Date()
        let value = await Timeout.race(seconds: 0.2) { () -> Int in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            return 1
        }
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertNil(value)
        XCTAssertLessThan(elapsed, 3)
    }
}

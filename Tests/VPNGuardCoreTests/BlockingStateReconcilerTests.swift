//
//  BlockingStateReconcilerTests.swift
//  VPNGuardCoreTests
//

import XCTest
@testable import VPNGuardCore

final class BlockingStateReconcilerTests: XCTestCase {

    /// On a successful status query the helper's flag wins — this is what stops
    /// the engine from believing it is blocking when PF rules were lost.
    func testAdoptsHelperStateOnSuccess() {
        XCTAssertTrue(
            BlockingStateReconciler.reconcile(
                success: true,
                helperBlockingActive: true,
                current: false
            )
        )
        XCTAssertFalse(
            BlockingStateReconciler.reconcile(
                success: true,
                helperBlockingActive: false,
                current: true
            )
        )
    }

    /// On failure the local value is kept (best-effort reconciliation).
    func testKeepsLocalStateOnFailure() {
        XCTAssertTrue(
            BlockingStateReconciler.reconcile(
                success: false,
                helperBlockingActive: false,
                current: true
            )
        )
        XCTAssertFalse(
            BlockingStateReconciler.reconcile(
                success: false,
                helperBlockingActive: true,
                current: false
            )
        )
    }

    func testNoChangeWhenStatesAgree() {
        XCTAssertTrue(
            BlockingStateReconciler.reconcile(
                success: true,
                helperBlockingActive: true,
                current: true
            )
        )
        XCTAssertFalse(
            BlockingStateReconciler.reconcile(
                success: true,
                helperBlockingActive: false,
                current: false
            )
        )
    }
}

//
//  IPCProtocol.swift
//  VPNGuard
//
//  XPC protocol shared between the main app and VPNGuardHelper.
//  Reply uses only ObjC-compatible primitives — no custom NSObject encoding.
//

import Foundation

/// Commands sent from the main app to the privileged helper.
nonisolated enum HelperCommand: Int, Sendable {
    case enableBlock = 1
    case disableBlock = 2
    case refreshRules = 3
    case getStatus = 4
    case setupAnchor = 5
}

/// In-process response model (not sent over XPC as an object).
nonisolated struct HelperResponse: Sendable {
    let success: Bool
    let message: String
    let blockingActive: Bool
}

/// Protocol implemented by VPNGuardHelper (root).
/// Reply signature uses Bool/String only — XPC-safe without NSSecureCoding.
@objc(VPNGuardHelperProtocol)
protocol VPNGuardHelperProtocol {
    func executeCommand(
        _ command: Int,
        ips: [String],
        pfConfigContent: String,
        withReply reply: @escaping (_ success: Bool, _ message: String, _ blockingActive: Bool) -> Void
    )
}

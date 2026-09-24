//
//  HelperDelegate.swift
//  VPNGuardHelper
//
//  NSXPCListener delegate accepting connections from the main app.
//

import Foundation

final class HelperDelegate: NSObject, NSXPCListenerDelegate {

    /// Single tool shared across connections so PF state (enable reference,
    /// loaded rules, blocking flag) stays process-wide and consistent.
    private let tool = HelperTool()

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: VPNGuardHelperProtocol.self)
        newConnection.exportedObject = tool
        newConnection.resume()
        return true
    }
}

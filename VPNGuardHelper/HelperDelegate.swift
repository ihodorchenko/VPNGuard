//
//  HelperDelegate.swift
//  VPNGuardHelper
//
//  NSXPCListener delegate accepting connections from the main app.
//

import Foundation

final class HelperDelegate: NSObject, NSXPCListenerDelegate {

    private var activeTools = [ObjectIdentifier: HelperTool]()

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        let tool = HelperTool()
        activeTools[ObjectIdentifier(newConnection)] = tool

        newConnection.exportedInterface = NSXPCInterface(with: VPNGuardHelperProtocol.self)
        newConnection.exportedObject = tool

        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            guard let self, let newConnection else { return }
            self.activeTools.removeValue(forKey: ObjectIdentifier(newConnection))
        }

        newConnection.resume()
        return true
    }
}

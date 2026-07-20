//
//  main.swift
//  VPNGuardHelper
//
//  Entry point for the privileged helper tool.
//

import Foundation

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: Constants.helperMachServiceName)
listener.delegate = delegate
listener.resume()

RunLoop.main.run()

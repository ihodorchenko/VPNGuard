//
//  VPNGuardApp.swift
//  VPNGuard
//
//  Menu bar only application entry point.
//

import SwiftUI

@main
struct VPNGuardApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

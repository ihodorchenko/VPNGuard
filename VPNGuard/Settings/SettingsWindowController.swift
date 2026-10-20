//
//  SettingsWindowController.swift
//  VPNGuard
//
//  Fallback Settings window for macOS 14–15, where the SwiftUI
//  `NSHostingSceneRepresentation` API is unavailable.
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {

    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "VPNGuard Settings"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 460, height: 560))
            window.center()
            self.window = window
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

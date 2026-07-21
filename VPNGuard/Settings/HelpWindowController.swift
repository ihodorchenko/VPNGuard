//
//  HelpWindowController.swift
//  VPNGuard
//
//  Presents the Help / diagnostics window.
//

import AppKit
import SwiftUI

@MainActor
final class HelpWindowController {

    static let shared = HelpWindowController()

    private var window: NSWindow?

    private init() {}

    func show(engine: ProtectionEngine) {
        if window == nil {
            let hosting = NSHostingController(rootView: HelpView(engine: engine))
            let window = NSWindow(contentViewController: hosting)
            window.title = "VPNGuard — Помощь"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 520, height: 560))
            window.center()
            self.window = window
        } else if let hosting = window?.contentViewController as? NSHostingController<HelpView> {
            hosting.rootView = HelpView(engine: engine)
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

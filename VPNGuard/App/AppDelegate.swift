//
//  AppDelegate.swift
//  VPNGuard
//
//  Application lifecycle and component wiring.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController!
    private var vpnMonitor: VPNMonitor!
    private var protectionEngine: ProtectionEngine!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        Logger.shared.info("VPNGuard starting")

        protectionEngine = ProtectionEngine()
        vpnMonitor = VPNMonitor(engine: protectionEngine)
        statusBarController = StatusBarController(
            engine: protectionEngine,
            monitor: vpnMonitor
        )

        Task { @MainActor in
            await bootstrap()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        vpnMonitor.stop()
        Rules.shared.stopPeriodicRefresh()
        Logger.shared.info("VPNGuard terminated")
    }

    // MARK: - Bootstrap

    @MainActor
    private func bootstrap() async {
        // Resolve protected host IPs
        await Rules.shared.refresh()
        Rules.shared.startPeriodicRefresh()

        // Install privileged helper and connect XPC
        let installed = await PFManager.shared.installHelper()
        if !installed {
            Logger.shared.error(
                "Privileged helper not installed — PF blocking unavailable",
                details: ["Hint": "Run from Xcode with Developer ID signing"]
            )
        } else {
            PFManager.shared.connectToHelper()
            await PFManager.shared.setupAnchor()
        }

        // Start VPN monitoring
        vpnMonitor.start()

        Logger.shared.info("VPNGuard ready")
    }
}

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

        registerSleepWakeObservers()

        Task { @MainActor in
            await bootstrap()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        vpnMonitor.stop()
        Rules.shared.stopPeriodicRefresh()
        clearBlockingRulesOnExit()
        Logger.shared.info("VPNGuard terminated")
    }

    /// Waits briefly for PF cleanup so block rules do not outlive the app.
    private func clearBlockingRulesOnExit() {
        let runCleanup = { [self] in
            var completed = false
            Task { @MainActor in
                await protectionEngine.cleanupOnShutdown()
                PFManager.shared.shutdown()
                completed = true
            }

            let deadline = Date().addingTimeInterval(5)
            while !completed && Date() < deadline {
                RunLoop.current.run(
                    mode: .default,
                    before: Date().addingTimeInterval(0.05)
                )
            }

            if !completed {
                Logger.shared.error(
                    "Shutdown cleanup timed out — PF rules may still be active",
                    details: ["Hint": "Use Help → manual removal commands"]
                )
            }
        }

        if Thread.isMainThread {
            runCleanup()
        } else {
            DispatchQueue.main.sync(execute: runCleanup)
        }
    }

    // MARK: - Sleep / Wake

    /// The app kept no notion of system sleep, so a check or XPC round-trip
    /// interrupted by sleep could leave it permanently stuck. Resume cleanly.
    private func registerSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func systemWillSleep() {
        Logger.shared.info("System will sleep — pausing checks")
        vpnMonitor.stop()
    }

    @objc private func systemDidWake() {
        Logger.shared.info("System woke — resuming checks")
        vpnMonitor.reset()
        protectionEngine.resetAfterWake()
        // The XPC connection may be stale after wake.
        PFManager.shared.connectToHelper()
        vpnMonitor.start()
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

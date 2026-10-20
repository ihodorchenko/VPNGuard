//
//  AppDelegate.swift
//  VPNGuard
//
//  Application lifecycle and component wiring.
//

import AppKit
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)

        // `NSApplication.delegate` is weak; keep the delegate alive for the
        // entire run loop.
        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    private var statusBarController: StatusBarController!
    private var vpnMonitor: VPNMonitor!
    private var protectionEngine: ProtectionEngine!

    /// macOS 26+ hosts the Settings scene itself so it can be opened
    /// programmatically through the SwiftUI `openSettings` action.
    private var settingsScene: AnyObject?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard #available(macOS 26.0, *) else { return }

        let host = SettingsSceneHost()
        NSApplication.shared.addSceneRepresentation(host.representation)
        settingsScene = host
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        Task { @MainActor in
            // The XPC connection may be stale after wake.
            PFManager.shared.connectToHelper()
            // Trust the helper about whether PF rules are actually loaded before
            // the next check decides anything.
            await protectionEngine.resyncAfterWake()
            vpnMonitor.start()
        }
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

    // MARK: - Settings

    /// Opens the SwiftUI Settings window. macOS 26+ uses the SwiftUI
    /// `openSettings` action (the action behind `SettingsLink`); older systems
    /// use a plain AppKit window hosting the same view.
    func showSettings() {
        if #available(macOS 26.0, *), let host = settingsScene as? SettingsSceneHost {
            host.open()
        } else {
            SettingsWindowController.shared.show()
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Hosts the SwiftUI Settings scene for apps that present their menu with
/// AppKit. `openSettings` is the action behind `SettingsLink`.
@available(macOS 26.0, *)
@MainActor
private final class SettingsSceneHost {

    let representation = NSHostingSceneRepresentation {
        Settings {
            SettingsView()
        }
    }

    func open() {
        representation.environment.openSettings()
    }
}

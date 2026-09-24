//
//  PFManager.swift
//  VPNGuard
//
//  Client-side manager that communicates with VPNGuardHelper for PF operations.
//

import Combine
import Foundation
import ServiceManagement

/// Manages PF firewall state via the privileged helper over XPC.
@MainActor
final class PFManager: NSObject, ObservableObject {

    static let shared = PFManager()

    @Published private(set) var helperInstalled = false
    @Published private(set) var blockingActive = false
    @Published private(set) var lastError: String?

    private var connection: NSXPCConnection?
    private var reconnectTask: Task<Void, Never>?

    private override init() {
        super.init()
    }

    // MARK: - Helper Installation

    /// Registers the privileged daemon via `SMAppService` (macOS 13+).
    ///
    /// The daemon executable is bundled at `Contents/MacOS` and described by a
    /// property list in `Contents/Library/LaunchDaemons`; the system validates
    /// the code signatures instead of requiring an inline AuthorizationRef.
    func installHelper() async -> Bool {
        let service = SMAppService.daemon(plistName: Constants.helperPlistName)

        switch service.status {
        case .enabled:
            Logger.shared.info("Privileged helper already enabled")
            helperInstalled = true
            connectToHelper()
            return true

        case .requiresApproval:
            lastError = "Helper requires approval in System Settings → General → Login Items"
            Logger.shared.error("Helper registration requires user approval", details: [
                "Reason": lastError ?? ""
            ])
            helperInstalled = false
            return false

        case .notRegistered, .notFound:
            do {
                try service.register()
            } catch {
                lastError = error.localizedDescription
                Logger.shared.error("Helper registration failed", details: [
                    "Reason": error.localizedDescription
                ])
                helperInstalled = false
                return false
            }

            helperInstalled = true
            Logger.shared.info("Privileged helper registered via SMAppService")
            connectToHelper()
            return true

        @unknown default:
            lastError = "Unknown helper status"
            helperInstalled = false
            return false
        }
    }

    // MARK: - XPC Connection

    func connectToHelper() {
        reconnectTask?.cancel()
        connection?.invalidate()

        let conn = NSXPCConnection(
            machServiceName: Constants.helperMachServiceName,
            options: .privileged
        )

        conn.remoteObjectInterface = NSXPCInterface(with: VPNGuardHelperProtocol.self)

        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.scheduleReconnect()
            }
        }

        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.scheduleReconnect()
            }
        }

        conn.resume()
        connection = conn
        helperInstalled = true
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            connectToHelper()
        }
    }

    // MARK: - Firewall Commands

    func setupAnchor() async {
        let config = PFRuleBuilder.shared.buildEmptyRules()
        let response = await sendCommand(.setupAnchor, ips: [], config: config)
        if response.success {
            Logger.shared.info("PF anchor installed", details: ["Message": response.message])
        } else {
            lastError = response.message
            Logger.shared.error("PF anchor setup failed", details: ["Reason": response.message])
        }
    }

    func enableBlock(ips: Set<String>) async {
        let config = PFRuleBuilder.shared.buildRules(from: ips)
        let response = await sendCommand(.enableBlock, ips: Array(ips), config: config)
        blockingActive = response.blockingActive
        if response.success {
            Logger.shared.security("Blocking enabled", details: [
                "IPCount": "\(ips.count)"
            ])
        } else {
            lastError = response.message
            Logger.shared.error("Failed to enable blocking", details: [
                "Reason": response.message
            ])
        }
    }

    func disableBlock() async {
        let config = PFRuleBuilder.shared.buildEmptyRules()
        let response = await sendCommand(.disableBlock, ips: [], config: config)
        blockingActive = response.blockingActive
        if response.success {
            Logger.shared.info("Blocking disabled")
        } else {
            lastError = response.message
            Logger.shared.error("Failed to disable blocking", details: [
                "Reason": response.message
            ])
        }
    }

    func refreshRules(ips: Set<String>) async {
        let config = PFRuleBuilder.shared.buildRules(from: ips)
        let response = await sendCommand(.refreshRules, ips: Array(ips), config: config)
        blockingActive = response.blockingActive
        if response.success {
            Logger.shared.info("PF rules refreshed", details: [
                "IPCount": "\(ips.count)"
            ])
        } else {
            lastError = response.message
        }
    }

    /// Asks the privileged helper for its own view of the anchor and blocking
    /// flag over XPC. Unlike the sudo-based checks, this needs no admin rights.
    func queryHelperStatus() async -> HelperResponse {
        await sendCommand(.getStatus, ips: [], config: "")
    }

    /// Re-syncs `blockingActive` with the helper and returns the reconciled
    /// value. Used after wake, where the local flag may no longer match reality.
    @discardableResult
    func resyncBlockingState() async -> Bool {
        let response = await sendCommand(.getStatus, ips: [], config: "")
        blockingActive = BlockingStateReconciler.reconcile(
            success: response.success,
            helperBlockingActive: response.blockingActive,
            current: blockingActive
        )
        return blockingActive
    }

    /// Stops reconnect attempts and closes the helper XPC connection.
    func shutdown() {
        reconnectTask?.cancel()
        reconnectTask = nil
        connection?.invalidate()
        connection = nil
    }

    // MARK: - Private

    private func sendCommand(
        _ command: HelperCommand,
        ips: [String],
        config: String
    ) async -> HelperResponse {
        if connection == nil {
            connectToHelper()
        }

        guard let conn = connection else {
            return HelperResponse(
                success: false,
                message: "No XPC connection to helper",
                blockingActive: blockingActive
            )
        }

        let currentBlocking = blockingActive
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce()
            let finish: @Sendable (HelperResponse) -> Void = { response in
                once.run { continuation.resume(returning: response) }
            }

            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                finish(HelperResponse(
                    success: false,
                    message: error.localizedDescription,
                    blockingActive: currentBlocking
                ))
            } as? VPNGuardHelperProtocol

            guard let proxy else {
                finish(HelperResponse(
                    success: false,
                    message: "Invalid XPC proxy",
                    blockingActive: currentBlocking
                ))
                return
            }

            // Never wait forever: a reply lost across sleep/wake must not leave
            // the caller (and isTransitioning) stuck.
            Task {
                try? await Task.sleep(
                    nanoseconds: UInt64(Constants.xpcReplyTimeout * 1_000_000_000)
                )
                finish(HelperResponse(
                    success: false,
                    message: "XPC reply timed out",
                    blockingActive: currentBlocking
                ))
            }

            proxy.executeCommand(
                command.rawValue,
                ips: ips,
                pfConfigContent: config
            ) { success, message, blockingActive in
                finish(HelperResponse(
                    success: success,
                    message: message,
                    blockingActive: blockingActive
                ))
            }
        }
    }
}

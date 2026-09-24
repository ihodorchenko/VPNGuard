//
//  PFManager.swift
//  VPNGuard
//
//  Client-side manager that communicates with VPNGuardHelper for PF operations.
//

import Combine
import Foundation
import ServiceManagement
import Security

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

    /// Installs or upgrades the privileged helper via SMJobBless.
    func installHelper() async -> Bool {
        // Request admin rights for bless / upgrade.
        guard let auth = createBlessAuthorization() else {
            lastError = "Authorization failed"
            Logger.shared.error("Helper installation failed", details: [
                "Reason": "AuthorizationCreate failed — admin password required"
            ])
            return false
        }
        defer { AuthorizationFree(auth, [.destroyRights]) }

        var error: Unmanaged<CFError>?
        let blessed = SMJobBless(
            kSMDomainSystemLaunchd,
            Constants.helperLabel as CFString,
            auth,
            &error
        )

        if !blessed {
            let cfError = error?.takeRetainedValue()
            let message = (cfError as Error?)?.localizedDescription ?? "SMJobBless failed"
            let code = cfError.map { CFErrorGetCode($0) } ?? -1

            // Already installed at same version is OK — still connect.
            if isHelperRegistered() {
                Logger.shared.info("Helper already registered — connecting", details: [
                    "BlessMessage": message,
                    "Code": "\(code)"
                ])
                helperInstalled = true
                connectToHelper()
                return true
            }

            lastError = message
            Logger.shared.error("Helper installation failed", details: [
                "Reason": message,
                "Code": "\(code)"
            ])
            return false
        }

        helperInstalled = true
        Logger.shared.info("Privileged helper installed/updated via SMJobBless")
        connectToHelper()
        return true
    }

    func isHelperRegistered() -> Bool {
        FileManager.default.fileExists(
            atPath: "/Library/PrivilegedHelperTools/\(Constants.helperLabel)"
        )
    }

    private func createBlessAuthorization() -> AuthorizationRef? {
        var authRef: AuthorizationRef?
        let rightName = kSMRightBlessPrivilegedHelper

        let status: OSStatus = rightName.withCString { namePtr in
            var item = AuthorizationItem(
                name: namePtr,
                valueLength: 0,
                value: nil,
                flags: 0
            )
            return withUnsafeMutablePointer(to: &item) { itemPtr in
                var rights = AuthorizationRights(count: 1, items: itemPtr)
                let flags: AuthorizationFlags = [.interactionAllowed, .preAuthorize, .extendRights]
                return AuthorizationCreate(&rights, nil, flags, &authRef)
            }
        }

        guard status == errAuthorizationSuccess else { return nil }
        return authRef
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

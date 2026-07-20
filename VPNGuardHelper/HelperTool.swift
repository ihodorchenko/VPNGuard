//
//  HelperTool.swift
//  VPNGuardHelper
//
//  Root-privileged tool that applies PF firewall rules via pfctl.
//

import Foundation

final class HelperTool: NSObject, VPNGuardHelperProtocol {

    private var blockingActive = false
    private let pfExecutor = PFExecutor()
    private let workQueue = DispatchQueue(
        label: "by.home.VPNGuard.helper.work",
        qos: .userInitiated
    )

    func executeCommand(
        _ command: Int,
        ips: [String],
        pfConfigContent: String,
        withReply reply: @escaping (Bool, String, Bool) -> Void
    ) {
        let helperCommand = HelperCommand(rawValue: command) ?? .getStatus

        workQueue.async { [self] in
            let response: HelperResponse

            switch helperCommand {
            case .setupAnchor:
                response = self.setupAnchor()
            case .enableBlock, .refreshRules:
                response = self.enableBlocking(config: pfConfigContent, ips: ips)
            case .disableBlock:
                response = self.disableBlocking()
            case .getStatus:
                response = HelperResponse(
                    success: true,
                    message: self.anchorStatusMessage(),
                    blockingActive: self.blockingActive
                )
            }

            // Reply once, on the queue that received the XPC call context.
            // Primitives encode safely over XPC.
            reply(response.success, response.message, response.blockingActive)
        }
    }

    // MARK: - Bootstrap

    private func setupAnchor() -> HelperResponse {
        do {
            try pfExecutor.bootstrapAnchor()
            return HelperResponse(
                success: true,
                message: "PF anchor \(Constants.pfAnchorName) ready",
                blockingActive: blockingActive
            )
        } catch {
            return HelperResponse(
                success: false,
                message: error.localizedDescription,
                blockingActive: blockingActive
            )
        }
    }

    // MARK: - Blocking

    private func enableBlocking(config: String, ips: [String]) -> HelperResponse {
        do {
            try pfExecutor.writeConfig(content: config)
            try pfExecutor.enablePF()
            try pfExecutor.loadAnchorRules()
            try pfExecutor.killStates(for: ips)
            blockingActive = true

            return HelperResponse(
                success: true,
                message: "Blocking enabled for \(ips.count) IP(s)",
                blockingActive: true
            )
        } catch {
            return HelperResponse(
                success: false,
                message: error.localizedDescription,
                blockingActive: blockingActive
            )
        }
    }

    private func disableBlocking() -> HelperResponse {
        do {
            try pfExecutor.flushAnchor()
            blockingActive = false

            return HelperResponse(
                success: true,
                message: "Blocking disabled",
                blockingActive: false
            )
        } catch {
            return HelperResponse(
                success: false,
                message: error.localizedDescription,
                blockingActive: blockingActive
            )
        }
    }

    private func anchorStatusMessage() -> String {
        if pfExecutor.anchorIsRegistered() {
            return blockingActive ? "Blocking active" : "Anchor ready"
        }
        return "Anchor not loaded"
    }
}

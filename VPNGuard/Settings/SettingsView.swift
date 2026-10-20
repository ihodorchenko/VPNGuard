//
//  SettingsView.swift
//  VPNGuard
//
//  SwiftUI settings panel for VPNGuard configuration.
//

import SwiftUI

struct SettingsView: View {

    @AppStorage(Constants.DefaultsKey.vpnInterfacePrefix)
    private var vpnInterfacePrefix = Constants.defaultVPNInterfacePrefix

    @AppStorage(Constants.DefaultsKey.customVPNInterface)
    private var customVPNInterface = ""

    @AppStorage(Constants.DefaultsKey.autoStart)
    private var autoStart = true

    @State private var hostsText: String = ""
    @State private var saveMessage: String?
    @State private var isSaving = false

    private var parsedHosts: ProtectionHostParseResult {
        ProtectionHostParser.parse(hostsText.components(separatedBy: .newlines))
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        Form {
            Section("VPN Interface") {
                TextField("Interface prefix", text: $vpnInterfacePrefix)
                    .help("Default: utun (WireGuard, Tunnelblick, ProtonVPN, Mullvad)")

                TextField("Custom interface (optional)", text: $customVPNInterface)
                    .help("Exact interface name, e.g. utun3")
            }

            Section("Protected Hosts") {
                TextEditor(text: $hostsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 100)
                    .onChange(of: hostsText) { _, _ in
                        saveMessage = nil
                    }

                HStack(spacing: 12) {
                    Button(isSaving ? "Saving…" : "Save Hosts") {
                        saveHosts()
                    }
                    .disabled(isSaving || parsedHosts.hosts.isEmpty)

                    Button("Reset to Defaults") {
                        hostsText = Constants.defaultProtectedHosts.joined(separator: "\n")
                    }
                    .disabled(isSaving)

                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text("One host per line. Schemes, paths and ports are ignored; up to \(Constants.maxProtectedHosts) hosts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !parsedHosts.invalid.isEmpty {
                    Text("Ignored entries: \(parsedHosts.invalid.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let saveMessage {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Startup") {
                Toggle("Auto start protection", isOn: $autoStart)
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Bundle ID", value: Constants.appBundleID)
                Text("VPNGuard blocks access to protected hosts when VPN is unavailable using macOS PF firewall.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
        .onAppear {
            loadHosts()
        }
    }

    private func loadHosts() {
        hostsText = Rules.shared.protectedHosts.joined(separator: "\n")
    }

    private func saveHosts() {
        let result = parsedHosts
        guard !result.hosts.isEmpty else {
            saveMessage = "Add at least one valid host"
            return
        }

        isSaving = true
        saveMessage = nil

        Task { @MainActor in
            let ips = await Rules.shared.updateHosts(result.hosts)
            hostsText = result.hosts.joined(separator: "\n")
            isSaving = false
            saveMessage = "Saved \(result.hosts.count) host(s). Active IP set: \(ips.count)."
            Logger.shared.info("Protected hosts updated", details: [
                "Hosts": result.hosts.joined(separator: ", "),
                "IPCount": "\(ips.count)"
            ])
        }
    }
}

#Preview {
    SettingsView()
}

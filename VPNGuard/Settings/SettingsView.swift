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
                    .frame(minHeight: 80)
                    .onAppear { loadHosts() }

                HStack {
                    Button("Save Hosts") { saveHosts() }
                    if let saveMessage {
                        Text(saveMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Startup") {
                Toggle("Auto start protection", isOn: $autoStart)
            }

            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Bundle ID", value: Constants.appBundleID)
                Text("VPNGuard blocks access to protected hosts when VPN is unavailable using macOS PF firewall.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 420)
        .padding()
    }

    private func loadHosts() {
        if let saved = UserDefaults.standard.stringArray(
            forKey: Constants.DefaultsKey.protectedHosts
        ), !saved.isEmpty {
            hostsText = saved.joined(separator: "\n")
        } else {
            hostsText = Constants.defaultProtectedHosts.joined(separator: "\n")
        }
    }

    private func saveHosts() {
        let hosts = hostsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        Task { @MainActor in
            Rules.shared.updateHosts(hosts)
            saveMessage = "Saved \(hosts.count) host(s)"
            Logger.shared.info("Protected hosts updated", details: [
                "Hosts": hosts.joined(separator: ", ")
            ])
        }
    }
}

#Preview {
    SettingsView()
}

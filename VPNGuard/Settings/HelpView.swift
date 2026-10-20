//
//  HelpView.swift
//  VPNGuard
//
//  Help panel with diagnostics and manual recovery commands.
//

import SwiftUI

struct HelpView: View {

    @ObservedObject var engine: ProtectionEngine

    @State private var snapshot: DiagnosticsSnapshot?
    @State private var isRunningChecks = false
    @State private var copiedCommand: String?
    @State private var helperStatus: String?
    @State private var isQueryingHelper = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                diagnosticsSection
                helperStatusSection
                terminalChecksSection
                manualRemovalSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 500, minHeight: 520)
        .onAppear {
            Task { await runChecks() }
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        GroupBox("Проверка статуса") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(isRunningChecks ? "Проверка…" : "Запустить проверку") {
                        Task { await runChecks() }
                    }
                    .disabled(isRunningChecks)

                    if let snapshot {
                        Text(formattedCheckTime(snapshot.checkedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let snapshot {
                    statusRow(
                        title: "VPN",
                        ok: snapshot.vpnState == "Connected",
                        detail: snapshot.vpnState
                    )
                    statusRow(
                        title: "Защита",
                        ok: snapshot.protectionEnabled,
                        detail: snapshot.protectionEnabled ? "Включена" : "Выключена"
                    )
                    statusRow(
                        title: "Блокировка (приложение)",
                        ok: !snapshot.appBlocking,
                        detail: snapshot.appBlocking ? "Активна" : "Не активна"
                    )
                    statusRow(
                        title: "Helper",
                        ok: snapshot.helperInstalled && snapshot.helperRunning,
                        detail: snapshot.helperDetail
                    )

                    if snapshot.hostChecks.isEmpty {
                        statusRow(
                            title: "Защищённые хосты",
                            ok: false,
                            detail: "Список пуст — добавьте хосты в Settings"
                        )
                    } else {
                        ForEach(snapshot.hostChecks) { check in
                            statusRow(
                                title: check.host,
                                ok: check.reachable,
                                detail: check.detail
                            )
                        }
                    }

                    Divider()

                    Text("PF config (\(Constants.pfConfigPath)):")
                        .font(.caption.bold())
                    Text(snapshot.pfConfigPreview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)

                    Text("PF anchor (\(Constants.pfAnchorName)):")
                        .font(.caption.bold())
                    Text(snapshot.pfRulesOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)

                    if !snapshot.pfRulesReadable {
                        Text("Для точной проверки правил PF используйте команды в Terminal ниже (sudo).")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } else if !isRunningChecks {
                    Text("Нажмите «Запустить проверку» для диагностики.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Helper status (XPC)

    private var helperStatusSection: some View {
        GroupBox("Статус helper (XPC)") {
            VStack(alignment: .leading, spacing: 10) {
                Button(isQueryingHelper ? "Опрос…" : "Опросить helper") {
                    Task { await queryHelper() }
                }
                .disabled(isQueryingHelper)

                if let helperStatus {
                    Text(helperStatus)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Запрашивает у привилегированного helper его состояние по XPC — без sudo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func queryHelper() async {
        isQueryingHelper = true
        defer { isQueryingHelper = false }

        let response = await PFManager.shared.queryHelperStatus()
        let blocking = response.blockingActive ? "BLOCKING" : "idle"
        helperStatus = "\(response.success ? "OK" : "FAIL"): \(response.message) [\(blocking)]"
    }

    // MARK: - Terminal

    private var terminalChecksSection: some View {
        GroupBox("Проверка в Terminal") {
            VStack(alignment: .leading, spacing: 14) {
                commandBlock(
                    title: "Правила PF установлены?",
                    command: pfRulesCheckCommand,
                    hint: "Пустой вывод = правил нет, защищённые хосты доступны через PF."
                )
                commandBlock(
                    title: "Защищённые хосты доступны?",
                    command: hostsCheckCommand,
                    hint: "Timeout = блокировка активна или нет сети. HTTP 403/200 = доступ есть."
                )
                commandBlock(
                    title: "Helper запущен?",
                    command: helperCheckCommand,
                    hint: "Строка с «0» во втором столбце = helper работает."
                )
            }
        }
    }

    // MARK: - Manual removal

    private var manualRemovalSection: some View {
        GroupBox("Снять блокировку вручную") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Если VPNGuard не снял правила после подключения VPN или при выходе из приложения:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                commandBlock(
                    title: "Очистить PF и отключить блокировку",
                    command: manualRemovalCommand,
                    hint: "Выполняйте по порядку. После этого curl к claude.ai должен отвечать."
                )
            }
        }
    }

    // MARK: - Components

    private func statusRow(title: String, ok: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(ok ? Color.green : Color.red)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func commandBlock(title: String, command: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.bold())

            HStack(alignment: .top) {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Button(copiedCommand == command ? "Скопировано" : "Копировать") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copiedCommand = command
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copiedCommand == command {
                            copiedCommand = nil
                        }
                    }
                }
                .controlSize(.small)
            }

            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Commands

    private var pfRulesCheckCommand: String {
        """
        sudo pfctl -a \(Constants.pfAnchorName) -s rules
        """
    }

    private var hostsCheckCommand: String {
        let hosts = Rules.shared.protectedHosts
        guard !hosts.isEmpty else {
            return "echo 'No protected hosts configured'"
        }

        return hosts
            .map { "curl -I --connect-timeout 5 https://\(urlHost($0))" }
            .joined(separator: "\n")
    }

    private var helperCheckCommand: String {
        """
        launchctl list | grep VPNGuard
        """
    }

    private var manualRemovalCommand: String {
        var lines = [
            "sudo pfctl -a \(Constants.pfAnchorName) -F all",
            "echo '# VPNGuard disabled' | sudo tee \(Constants.pfConfigPath)",
            "sudo pfctl -a \(Constants.pfAnchorName) -f \(Constants.pfConfigPath)",
            "sudo pfctl -a \(Constants.pfAnchorName) -s rules"
        ]

        if let firstHost = Rules.shared.protectedHosts.first {
            lines.append("curl -I --connect-timeout 5 https://\(urlHost(firstHost))")
        }

        return lines.joined(separator: "\n")
    }

    private func urlHost(_ host: String) -> String {
        host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
    }

    // MARK: - Actions

    private func runChecks() async {
        isRunningChecks = true
        defer { isRunningChecks = false }

        let vpnLabel: String
        switch engine.state {
        case .checking: vpnLabel = "Checking"
        case .connected: vpnLabel = "Connected"
        case .disconnected: vpnLabel = "Disconnected"
        }

        snapshot = await DiagnosticsService.run(
            vpnState: vpnLabel,
            protectionEnabled: engine.protectionEnabled,
            appBlocking: engine.isBlocking,
            helperInstalled: PFManager.shared.helperInstalled,
            hosts: Rules.shared.protectedHosts
        )
    }

    private func formattedCheckTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return "Обновлено в \(formatter.string(from: date))"
    }
}

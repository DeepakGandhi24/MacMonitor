import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var jamf: JAMFService
    @EnvironmentObject var receiver: AgentReceiver

    // JAMF fields — stored in AppStorage by default, Keychain only if user chooses
    @AppStorage("jamfURL") var jamfURL = ""
    @AppStorage("jamfClientID") var jamfClientID = ""
    @AppStorage("jamfClientSecret") var jamfClientSecret = ""
    @State private var saveToKeychain = false
    @State private var keychainSaved = false
    var credentialsSaved: Bool { keychainSaved }

    // Other settings
    @AppStorage("dashboardIP") var dashboardIP = ""
    @AppStorage("teamsWebhookURL") var teamsWebhookURL = ""
    @AppStorage("snowInstanceURL") var snowInstanceURL = ""
    @AppStorage("snowUsername") var snowUsername = ""
    @AppStorage("snowPassword") var snowPassword = ""

    @Environment(\.dismiss) var dismiss
    @State private var tab = 0
    @State private var agentInstalled = false
    @State private var installing = false
    @State private var installMessage = ""
    @State private var teamsSending = false
    @State private var teamsMessage = ""
    @State private var testStatus = ""
    @State private var isTesting = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }.padding()
            Divider()

            TabView(selection: $tab) {
                jamfTab.tabItem { Label("JAMF", systemImage: "server.rack") }.tag(0)
                agentTab.tabItem { Label("Agent", systemImage: "bolt.fill") }.tag(1)
                exportTab.tabItem { Label("Export", systemImage: "square.and.arrow.up") }.tag(2)
                integrationsTab.tabItem { Label("Integrations", systemImage: "link") }.tag(3)
            }
            .padding()
        }
        .frame(width: 560, height: 520)
        .onAppear {
            checkAgentStatus()
            loadCredentials()
        }
    }

    // MARK: - Load credentials from Keychain if saved
    func loadCredentials() {
        let savedURL    = KeychainService.load("jamfURL")
        let savedID     = KeychainService.load("jamfClientID")
        let savedSecret = KeychainService.load("jamfClientSecret")
        if !savedURL.isEmpty {
            jamfURL = savedURL
            jamfClientID = savedID
            jamfClientSecret = savedSecret
            saveToKeychain = true
            keychainSaved = true
        }
    }

    // MARK: - JAMF Tab
    var jamfTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Status banner
                HStack(spacing: 10) {
                    Image(systemName: credentialsSaved ? "checkmark.shield.fill" : "shield.slash")
                        .foregroundColor(credentialsSaved ? .green : .orange)
                        .font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(credentialsSaved ? "Credentials saved in Keychain" : "No credentials saved")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(credentialsSaved ? .green : .orange)
                        Text(credentialsSaved ? "Stored securely — not visible after saving" : "Enter credentials below to connect to JAMF")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    if credentialsSaved {
                        Button("Clear") {
                            KeychainService.delete("jamfURL")
                            KeychainService.delete("jamfClientID")
                            KeychainService.delete("jamfClientSecret")
                            jamfURL = ""; jamfClientID = ""; jamfClientSecret = ""
                            keychainSaved = false; saveToKeychain = false
                        }
                        .foregroundColor(.red).font(.caption)
                    }
                }
                .padding(12)
                .background(credentialsSaved ? Color.green.opacity(0.08) : Color.orange.opacity(0.08))
                .cornerRadius(10)

                // Input fields
                VStack(alignment: .leading, spacing: 14) {
                    inputField("JAMF URL", placeholder: "https://company.jamfcloud.com",
                               text: $jamfURL, isSecure: false)
                    inputField("Client ID", placeholder: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
                               text: $jamfClientID, isSecure: false)
                    inputField("Client Secret", placeholder: "••••••••••••••••••••",
                               text: $jamfClientSecret, isSecure: true)
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(10)

                // Save to Keychain toggle
                HStack(spacing: 8) {
                    Toggle("", isOn: $saveToKeychain)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save credentials to Keychain")
                            .font(.system(size: 13))
                        Text("Credentials stored securely and auto-loaded on next launch")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }

                // Action buttons + status
                HStack(spacing: 10) {
                    if isTesting {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("Testing...").font(.caption).foregroundColor(.secondary)
                        }
                    } else if !testStatus.isEmpty {
                        Label(testStatus,
                              systemImage: testStatus.contains("✅") ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(testStatus.contains("✅") ? .green : .red)
                    } else if jamf.isLoading {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("Fetching devices...").font(.caption).foregroundColor(.secondary)
                        }
                    } else if !jamf.devices.isEmpty {
                        Label("\(jamf.devices.count) devices loaded",
                              systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundColor(.green)
                    } else if let e = jamf.errorMessage {
                        Label(e, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundColor(.red)
                            .lineLimit(2)
                    }

                    Spacer()

                    Button("Test Auth") { testAuth() }
                        .disabled(jamfURL.isEmpty || jamfClientID.isEmpty || jamfClientSecret.isEmpty || isTesting)

                    Button("Fetch Devices") { fetchDevices() }
                        .buttonStyle(.borderedProminent)
                        .disabled(jamfURL.isEmpty || jamfClientID.isEmpty || jamfClientSecret.isEmpty || jamf.isLoading)
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    func inputField(_ label: String, placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            if isSecure {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Test Auth (OAuth only, no device fetch)
    func testAuth() {
        isTesting = true
        testStatus = ""
        Task {
            do {
                _ = try await jamf.fetchToken(
                    baseURL: jamfURL,
                    clientID: jamfClientID,
                    clientSecret: jamfClientSecret
                )
                await MainActor.run {
                    testStatus = "✅ Authentication successful"
                    isTesting = false
                    // Save to Keychain if checkbox is ticked
                    if saveToKeychain {
                        KeychainService.save(jamfURL,          for: "jamfURL")
                        KeychainService.save(jamfClientID,     for: "jamfClientID")
                        KeychainService.save(jamfClientSecret, for: "jamfClientSecret")
                        keychainSaved = true
                    }
                }
            } catch {
                await MainActor.run {
                    testStatus = "❌ \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }

    // MARK: - Fetch Devices
    func fetchDevices() {
        if saveToKeychain {
            KeychainService.save(jamfURL,          for: "jamfURL")
            KeychainService.save(jamfClientID,     for: "jamfClientID")
            KeychainService.save(jamfClientSecret, for: "jamfClientSecret")
            keychainSaved = true
        }
        Task {
            await jamf.fetchDevices(
                baseURL: jamfURL,
                clientID: jamfClientID,
                clientSecret: jamfClientSecret
            )
        }
    }

    // MARK: - Agent Tab
    var agentTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                Section("Dashboard Receiver") {
                    TextField("This Mac's IP address", text: $dashboardIP)
                    HStack {
                        Circle().fill(receiver.isRunning ? Color.green : Color.red).frame(width: 8, height: 8)
                        Text(receiver.isRunning ? "Listening on port 9876" : "Stopped").font(.caption)
                        Spacer()
                        Button(receiver.isRunning ? "Stop" : "Start") {
                            receiver.isRunning ? receiver.stop() : receiver.start()
                        }
                    }
                    if let e = receiver.lastError { Text(e).foregroundColor(.red).font(.caption) }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Agent on This Mac").font(.headline)
                HStack(spacing: 8) {
                    Circle().fill(agentInstalled ? Color.green : Color.orange).frame(width: 8, height: 8)
                    Text(agentInstalled ? "Agent installed & running" : "Not installed")
                        .font(.caption).foregroundColor(agentInstalled ? .green : .orange)
                    Spacer()
                    Button("Check") { checkAgentStatus() }.font(.caption)
                }
                HStack(spacing: 10) {
                    Button { installAgent() } label: {
                        if installing { HStack(spacing: 6) { ProgressView().scaleEffect(0.7); Text("Installing...") } }
                        else { Label("Install & Start", systemImage: "arrow.down.circle.fill") }
                    }
                    .disabled(installing || dashboardIP.isEmpty).buttonStyle(.borderedProminent)
                    Button { uninstallAgent() } label: { Label("Uninstall", systemImage: "trash") }
                        .disabled(installing).foregroundColor(.red)
                }
                if dashboardIP.isEmpty { Text("⚠️ Enter IP first").font(.caption).foregroundColor(.orange) }
                if !installMessage.isEmpty {
                    Text(installMessage).font(.caption)
                        .foregroundColor(installMessage.hasPrefix("✅") ? .green : .red)
                }
            }.padding(.horizontal, 4)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Deploy to Other Macs via JAMF").font(.subheadline).bold()
                Button { AgentScriptGenerator.exportAll(dashboardIP: dashboardIP) } label: {
                    Label("Export for JAMF Deployment", systemImage: "arrow.down.circle")
                }.disabled(dashboardIP.isEmpty)
            }.padding(.horizontal, 4)
            Spacer()
        }.padding()
    }

    // MARK: - Export Tab
    var exportTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Export Device Data").font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                Text("All Devices (\(jamf.devices.count) total)").font(.subheadline).foregroundColor(.secondary)
                Text("Exports all JAMF devices including those without agent data.")
                    .font(.caption).foregroundColor(.secondary)
                Button { ExportService.exportCSV(devices: jamf.devices) } label: {
                    Label("Export All Devices to CSV", systemImage: "tablecells")
                }.buttonStyle(.borderedProminent).disabled(jamf.devices.isEmpty)
            }
            .padding().background(Color(nsColor: .controlBackgroundColor)).cornerRadius(10)

            VStack(alignment: .leading, spacing: 8) {
                let reporting = jamf.devices.filter { $0.metrics != nil }
                Text("Reporting Devices (\(reporting.count) with agent data)")
                    .font(.subheadline).foregroundColor(.secondary)
                Text("Exports only devices with live metrics — CPU, memory, disk, battery details.")
                    .font(.caption).foregroundColor(.secondary)
                Button { ExportService.exportReportingCSV(devices: jamf.devices) } label: {
                    Label("Export Reporting Devices to CSV", systemImage: "tablecells.badge.ellipsis")
                }.buttonStyle(.bordered).disabled(reporting.isEmpty)
            }
            .padding().background(Color(nsColor: .controlBackgroundColor)).cornerRadius(10)
            Spacer()
        }.padding()
    }

    // MARK: - Integrations Tab
    var integrationsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Teams
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "message.fill").foregroundColor(.purple)
                        Text("Microsoft Teams").font(.headline)
                    }
                    Text("Post fleet health reports to a Teams channel via Incoming Webhook.")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("Webhook URL", text: $teamsWebhookURL).textFieldStyle(.roundedBorder)
                    HStack(spacing: 10) {
                        Button {
                            teamsSending = true
                            Task {
                                await ExportService.sendTeamsAlert(webhookURL: teamsWebhookURL, devices: jamf.devices)
                                teamsSending = false
                                teamsMessage = "✅ Sent"
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { teamsMessage = "" }
                            }
                        } label: {
                            if teamsSending { HStack { ProgressView().scaleEffect(0.7); Text("Sending...") } }
                            else { Label("Send Fleet Report Now", systemImage: "paperplane.fill") }
                        }
                        .buttonStyle(.borderedProminent).tint(.purple)
                        .disabled(teamsWebhookURL.isEmpty || teamsSending)
                        if !teamsMessage.isEmpty {
                            Text(teamsMessage).font(.caption).foregroundColor(.green)
                        }
                    }
                    Text("Teams → Channel → ··· → Connectors → Incoming Webhook")
                        .font(.caption2).foregroundColor(.secondary)
                }
                .padding().background(Color(nsColor: .controlBackgroundColor)).cornerRadius(10)

                // ServiceNow
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "ticket.fill").foregroundColor(.green)
                        Text("ServiceNow").font(.headline)
                    }
                    Text("Create incidents for devices with performance issues.")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("Instance URL (https://yourcompany.service-now.com)", text: $snowInstanceURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("Username", text: $snowUsername).textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $snowPassword).textFieldStyle(.roundedBorder)
                    let alertDevices = jamf.devices.filter { d in
                        guard let m = d.metrics else { return false }
                        return m.cpu.totalUsagePercent > 70 || m.memory.usagePercent > 85 ||
                               (m.battery.percent < 20 && !m.battery.isCharging) ||
                               (m.disk?.usagePercent ?? 0) > 85
                    }
                    if alertDevices.isEmpty {
                        Label("No devices currently need incidents", systemImage: "checkmark.circle")
                            .font(.caption).foregroundColor(.green)
                    } else {
                        Label("\(alertDevices.count) device(s) have performance issues",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundColor(.orange)
                        ForEach(alertDevices.prefix(5)) { d in
                            HStack {
                                Image(systemName: "desktopcomputer").foregroundColor(.orange).frame(width: 14)
                                Text(d.name).font(.caption)
                                Spacer()
                                Button("Create Incident") {
                                    Task {
                                        await ExportService.createServiceNowIncident(
                                            instanceURL: snowInstanceURL,
                                            username: snowUsername,
                                            password: snowPassword,
                                            device: d
                                        )
                                    }
                                }
                                .font(.caption).buttonStyle(.bordered)
                                .disabled(snowInstanceURL.isEmpty || snowUsername.isEmpty || snowPassword.isEmpty)
                            }
                        }
                        Button {
                            Task {
                                for d in alertDevices {
                                    await ExportService.createServiceNowIncident(
                                        instanceURL: snowInstanceURL,
                                        username: snowUsername,
                                        password: snowPassword,
                                        device: d
                                    )
                                }
                            }
                        } label: {
                            Label("Create All Incidents (\(alertDevices.count))", systemImage: "ticket")
                        }
                        .buttonStyle(.borderedProminent).tint(.green)
                        .disabled(alertDevices.isEmpty || snowInstanceURL.isEmpty)
                    }
                }
                .padding().background(Color(nsColor: .controlBackgroundColor)).cornerRadius(10)
            }.padding()
        }
    }

    // MARK: - Agent helpers
    func checkAgentStatus() {
        agentInstalled = FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/com.macmonitor.agent.plist") &&
                         FileManager.default.fileExists(atPath: "/Library/MacMonitor/agent.py")
    }

    func installAgent() {
        guard !dashboardIP.isEmpty else { return }
        installing = true; installMessage = ""
        let script = AgentScriptGenerator.pythonScript(ip: dashboardIP)
        let plist  = AgentScriptGenerator.plist()
        let install = """
#!/bin/bash
set -e
mkdir -p /Library/MacMonitor/libs
/usr/bin/python3 -m pip install psutil --target /Library/MacMonitor/libs --quiet 2>/dev/null || true
cat > /Library/MacMonitor/agent.py << 'PYEOF'
\(script)
PYEOF
cat > /Library/LaunchDaemons/com.macmonitor.agent.plist << 'PLEOF'
\(plist)
PLEOF
chmod 755 /Library/MacMonitor/agent.py
chmod 644 /Library/LaunchDaemons/com.macmonitor.agent.plist
chown root:wheel /Library/LaunchDaemons/com.macmonitor.agent.plist
launchctl unload /Library/LaunchDaemons/com.macmonitor.agent.plist 2>/dev/null || true
launchctl load /Library/LaunchDaemons/com.macmonitor.agent.plist
echo "SUCCESS"
"""
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mm_install.sh")
        try? install.write(to: tmp, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        DispatchQueue.global().async {
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments = ["-e", "do shell script \"bash \(tmp.path)\" with administrator privileges"]
            let pipe = Pipe(); task.standardOutput = pipe; task.standardError = pipe
            try? task.run(); task.waitUntilExit()
            DispatchQueue.main.async {
                installing = false
                agentInstalled = task.terminationStatus == 0
                installMessage = task.terminationStatus == 0 ? "✅ Agent installed and running" : "❌ Install failed"
            }
        }
    }

    func uninstallAgent() {
        installing = true
        DispatchQueue.global().async {
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments = ["-e", "do shell script \"launchctl unload /Library/LaunchDaemons/com.macmonitor.agent.plist 2>/dev/null; rm -f /Library/LaunchDaemons/com.macmonitor.agent.plist; rm -rf /Library/MacMonitor\" with administrator privileges"]
            try? task.run(); task.waitUntilExit()
            DispatchQueue.main.async {
                installing = false; agentInstalled = false
                installMessage = "✅ Agent uninstalled"
            }
        }
    }

    @ViewBuilder
    func credentialField(_ label: String, placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.secondary)
            if isSecure {
                SecureField(placeholder, text: text).textFieldStyle(.roundedBorder)
            } else {
                TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
            }
        }
    }
}

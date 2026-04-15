import SwiftUI

@main
struct MacMonitorApp: App {
    @StateObject private var jamf = JAMFService()
    @StateObject private var receiver = AgentReceiver()
    @AppStorage("lastFetchDate") var lastFetchDate: Double = 0

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(jamf)
                .environmentObject(receiver)
                .frame(minWidth: 960, minHeight: 620)
                .onAppear {
                    let ud = UserDefaults.standard
                    print("[App] onAppear fired")
                    print("[App] jamfURL = '\(ud.string(forKey: "jamfURL") ?? "NIL")'")
                    print("[App] jamfClientID = '\(ud.string(forKey: "jamfClientID") ?? "NIL")'")
                    print("[App] jamfClientSecret = \(ud.string(forKey: "jamfClientSecret") == nil ? "NIL" : "SET")")
                    setupReceiver()
                    loadJAMFThenTriggerAgent()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Force Refresh JAMF") {
                    loadJAMFThenTriggerAgent()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Request Metrics Now") {
                    triggerAgentPost()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Divider()

                Button("Export All to CSV") {
                    ExportService.exportCSV(devices: jamf.devices)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }

    // MARK: - Setup receiver
    private func setupReceiver() {
        receiver.onMetricsReceived = { metrics in
            DispatchQueue.main.async {
                print("[App] ✅ \(metrics.hostname) CPU=\(metrics.cpu.totalUsagePercent)%")
                jamf.updateMetrics(metrics)
            }
        }
        if !receiver.isRunning {
            receiver.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if !receiver.isRunning {
                    receiver.stop()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        receiver.start()
                    }
                }
            }
        }
    }

    // MARK: - Load JAMF then trigger agent
    private func loadJAMFThenTriggerAgent() {
        let ud = UserDefaults.standard
        let url    = ud.string(forKey: "jamfURL") ?? ""
        let id     = ud.string(forKey: "jamfClientID") ?? ""
        let secret = ud.string(forKey: "jamfClientSecret") ?? ""

        print("[App] URL='\(url.prefix(30))' ID='\(id.prefix(8))' Secret=\(secret.isEmpty ? "EMPTY" : "SET(\(secret.count)chars)")")

        guard !url.isEmpty && !id.isEmpty && !secret.isEmpty else {
            print("[App] ⚠️ No credentials — agent only")
            triggerAgentPost()
            return
        }

        print("[App] ✅ Fetching JAMF devices...")
        Task {
            await jamf.fetchDevices(baseURL: url, clientID: id, clientSecret: secret)
            print("[App] ✅ JAMF done: \(jamf.devices.count) devices — triggering agent")
            triggerAgentPost()
        }
    }

    // MARK: - Trigger agent post — runs installed agent once
    private func triggerAgentPost() {
        DispatchQueue.global(qos: .background).async {
            let task = Process()
            task.launchPath = "/usr/bin/python3"
            task.arguments = ["/Library/MacMonitor/agent.py"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            try? task.run()
            // Kill after 30 seconds max (agent needs ~5s for CPU warmup)
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                if task.isRunning { task.terminate() }
            }
            task.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            print("[TriggerAgent] \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}

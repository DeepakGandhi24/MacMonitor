import SwiftUI

struct DeviceDetailView: View {
    let device: JAMFDevice
    @State private var isSyncing = false
    @State private var syncStatus = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── Header ───────────────────────────────────────────
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name).font(.title2).bold()
                        if device.serialNumber != "—" && device.serialNumber != "Unknown" {
                            Text("Serial: \(device.serialNumber)").foregroundColor(.secondary)
                        }
                        if let u = device.username { Text("User: \(u)").foregroundColor(.secondary) }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        if let last = device.lastSeen {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Last Report").font(.caption).foregroundColor(.secondary)
                                Text(last, style: .relative).font(.caption).foregroundColor(.green)
                            }
                        }
                        HStack(spacing: 6) {
                            if !syncStatus.isEmpty {
                                Text(syncStatus)
                                    .font(.caption)
                                    .foregroundColor(
                                        syncStatus.contains("✅") ? .green :
                                        syncStatus.contains("🔴") ? .red : .orange
                                    )
                            }
                            Button { syncDevice() } label: {
                                if isSyncing {
                                    HStack(spacing: 4) {
                                        ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                                        Text("Syncing...").font(.caption)
                                    }
                                } else {
                                    Label("Sync Now", systemImage: "arrow.clockwise").font(.caption)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isSyncing)
                        }
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)

                if let m = device.metrics {

                    // ── Metric Cards ─────────────────────────────────
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                        MetricCard(title: "CPU",
                                   value: String(format: "%.1f%%", m.cpu.totalUsagePercent),
                                   icon: "cpu", color: cpuC(m.cpu.totalUsagePercent))
                        MetricCard(title: "Memory",
                                   value: String(format: "%.1f%%", m.memory.usagePercent),
                                   icon: "memorychip", color: memC(m.memory.usagePercent))
                        MetricCard(title: "Disk",
                                   value: m.disk != nil ? String(format: "%.1f%%", m.disk!.usagePercent) : "N/A",
                                   icon: "internaldrive",
                                   color: m.disk != nil ? diskC(m.disk!.usagePercent) : .gray)
                        MetricCard(title: "Battery",
                                   value: String(format: "%.0f%%", m.battery.percent),
                                   icon: "battery.75", color: batC(m.battery.percent))
                        MetricCard(title: "Uptime",
                                   value: fmtUptime(m.uptime),
                                   icon: "clock", color: .blue)
                    }

                    // ── CPU Details ───────────────────────────────────
                    SectionCard(title: "CPU Details", icon: "cpu") {
                        HStack(spacing: 20) {
                            inf("Cores",    "\(m.cpu.coreCount)")
                            inf("Usage",    String(format: "%.1f%%", m.cpu.totalUsagePercent))
                            inf("Load 1m",  String(format: "%.2f", m.cpu.loadAverage1m))
                            inf("Load 5m",  String(format: "%.2f", m.cpu.loadAverage5m))
                            inf("Load 15m", String(format: "%.2f", m.cpu.loadAverage15m))
                        }
                        ProgressView(value: m.cpu.totalUsagePercent / 100)
                            .tint(cpuC(m.cpu.totalUsagePercent))
                            .padding(.top, 4)
                    }

                    // ── Memory ───────────────────────────────────────
                    SectionCard(title: "Memory", icon: "memorychip") {
                        HStack(spacing: 20) {
                            inf("Total",    String(format: "%.1f GB", m.memory.totalGB))
                            inf("Used",     String(format: "%.1f GB", m.memory.usedGB))
                            inf("Free",     String(format: "%.1f GB", m.memory.availableGB))
                            inf("Pressure", m.memory.pressure?.capitalized ?? "Normal")
                        }
                        ProgressView(value: m.memory.usagePercent / 100)
                            .tint(memC(m.memory.usagePercent))
                            .padding(.top, 4)
                        if let p = m.memory.pressure, p != "normal" {
                            Label(p == "warning" ?
                                  "Memory under pressure — consider closing apps" :
                                  "⚠️ Critical memory pressure!",
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(p == "warning" ? .orange : .red)
                                .padding(.top, 2)
                        }
                    }

                    // ── Disk ─────────────────────────────────────────
                    if let disk = m.disk {
                        SectionCard(title: "Disk Usage (/)", icon: "internaldrive") {
                            HStack(spacing: 20) {
                                inf("Total", String(format: "%.0f GB", disk.totalGB))
                                inf("Used",  String(format: "%.0f GB", disk.usedGB))
                                inf("Free",  String(format: "%.0f GB", disk.freeGB))
                                inf("Used%", String(format: "%.1f%%", disk.usagePercent))
                            }
                            ProgressView(value: disk.usagePercent / 100)
                                .tint(diskC(disk.usagePercent))
                                .padding(.top, 4)
                            if disk.usagePercent > 85 {
                                Label("Low disk space — consider freeing up storage",
                                      systemImage: "exclamationmark.triangle")
                                    .font(.caption).foregroundColor(.orange).padding(.top, 2)
                            }
                        }
                    }

                    // ── Network ───────────────────────────────────────
                    SectionCard(title: "Network (\(m.network.interface))", icon: "network") {
                        HStack(spacing: 20) {
                            inf("Total Sent",     String(format: "%.1f MB", m.network.bytesSentMB))
                            inf("Total Received", String(format: "%.1f MB", m.network.bytesReceivedMB))
                            if let s = m.network.sentRateKBs {
                                inf("↑ Upload",   String(format: "%.1f KB/s", s))
                            }
                            if let r = m.network.recvRateKBs {
                                inf("↓ Download", String(format: "%.1f KB/s", r))
                            }
                        }
                    }

                    // ── Battery ───────────────────────────────────────
                    SectionCard(title: "Battery", icon: "battery.75") {
                        HStack(spacing: 20) {
                            inf("Level",  String(format: "%.0f%%", m.battery.percent))
                            inf("Status", m.battery.isCharging ? "⚡ Charging" : "On Battery")
                            if let c = m.battery.cycleCount { inf("Cycles", "\(c)") }
                            if let h = m.battery.health     { inf("Health", h) }
                        }
                    }

                    // ── Top CPU Apps ──────────────────────────────────
                    if let topApps = m.topCPUApps, !topApps.isEmpty {
                        SectionCard(title: "Apps Using High CPU", icon: "flame") {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("App").frame(maxWidth: .infinity, alignment: .leading)
                                    Text("CPU%").frame(width: 60, alignment: .trailing)
                                    Text("RAM").frame(width: 80, alignment: .trailing)
                                }
                                .font(.caption).foregroundColor(.secondary)
                                .padding(.horizontal, 8).padding(.bottom, 4)
                                Divider()
                                ForEach(topApps, id: \.pid) { a in
                                    HStack {
                                        HStack(spacing: 6) {
                                            Image(systemName: "app.fill")
                                                .font(.system(size: 10)).foregroundColor(.blue)
                                            Text(a.name)
                                                .font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(String(format: "%.1f%%", a.cpuPercent))
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(cpuC(a.cpuPercent))
                                            .frame(width: 60, alignment: .trailing)
                                        Text(String(format: "%.0f MB", a.memoryMB))
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .frame(width: 80, alignment: .trailing)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    Divider()
                                }
                            }
                        }
                    }

                    // ── All Top Processes ─────────────────────────────
                    SectionCard(title: "All Top Processes (by CPU)", icon: "list.bullet") {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Process").frame(maxWidth: .infinity, alignment: .leading)
                                Text("CPU%").frame(width: 60, alignment: .trailing)
                                Text("RAM").frame(width: 80, alignment: .trailing)
                                Text("Status").frame(width: 70, alignment: .trailing)
                            }
                            .font(.caption).foregroundColor(.secondary)
                            .padding(.horizontal, 8).padding(.bottom, 4)
                            Divider()
                            ForEach(m.apps.prefix(20), id: \.pid) { a in
                                HStack {
                                    Text(a.name)
                                        .font(.system(size: 12))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .lineLimit(1)
                                        .foregroundColor((a.isUserApp ?? true) ? .primary : .secondary)
                                    Text(String(format: "%.1f%%", a.cpuPercent))
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(cpuC(a.cpuPercent))
                                        .frame(width: 60, alignment: .trailing)
                                    Text(String(format: "%.0f MB", a.memoryMB))
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 80, alignment: .trailing)
                                    Text(a.status)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .frame(width: 70, alignment: .trailing)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                Divider()
                            }
                        }
                    }

                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 40)).foregroundColor(.secondary)
                        Text("Waiting for agent data...").foregroundColor(.secondary)
                        Text("Deploy the agent via JAMF to this Mac")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(40)
                }
            }
            .padding()
        }
    }

    // MARK: - Sync
    func syncDevice() {
        isSyncing = true
        syncStatus = "Requesting..."
        let localHostname = Host.current().localizedName ?? ""
        let isLocal = device.name.lowercased().contains(localHostname.lowercased()) ||
                      localHostname.lowercased().contains(device.name.lowercased())
        if isLocal {
            syncLocal()
        } else if let ip = device.ipAddress, !ip.isEmpty {
            syncRemote(ip: ip)
        } else {
            syncStatus = "⚠️ No IP yet"
            isSyncing = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { syncStatus = "" }
        }
    }

    func syncLocal() {
        DispatchQueue.global(qos: .background).async {
            let task = Process()
            task.launchPath = "/usr/bin/python3"
            task.arguments = ["/Library/MacMonitor/agent.py"]
            task.environment = ["SINGLE_RUN": "1",
                                 "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            try? task.run()
            task.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                isSyncing = false
                syncStatus = out.contains("OK") ? "✅ Updated" : "❌ Failed"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { syncStatus = "" }
            }
        }
    }

    func syncRemote(ip: String) {
        guard let url = URL(string: "http://\(ip):9877/sync") else {
            DispatchQueue.main.async { isSyncing = false; syncStatus = "❌ Invalid IP" }
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.httpMethod = "POST"
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            DispatchQueue.main.async {
                isSyncing = false
                syncStatus = (resp as? HTTPURLResponse)?.statusCode == 200 ? "✅ Sync requested" : "🔴 Offline"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { syncStatus = "" }
            }
        }.resume()
    }

    // MARK: - Helpers
    func inf(_ l: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(l).font(.caption).foregroundColor(.secondary)
            Text(v).font(.system(size: 13, weight: .medium))
        }
    }
    func fmtUptime(_ s: Double) -> String {
        let h = Int(s) / 3600; let d = h / 24
        return d > 0 ? "\(d)d \(h % 24)h" : "\(h)h"
    }
    func cpuC(_ v: Double) -> Color  { v < 40 ? .green : v < 70 ? .orange : .red }
    func memC(_ v: Double) -> Color  { v < 60 ? .green : v < 80 ? .orange : .red }
    func diskC(_ v: Double) -> Color { v < 70 ? .green : v < 85 ? .orange : .red }
    func batC(_ v: Double) -> Color  { v > 30 ? .green : v > 15 ? .orange : .red }
}

// MARK: - Reusable Cards
struct MetricCard: View {
    let title: String; let value: String; let icon: String; let color: Color
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundColor(color)
            Text(value).font(.title3).bold()
            Text(title).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding()
        .background(color.opacity(0.08)).cornerRadius(12)
    }
}

struct SectionCard<Content: View>: View {
    let title: String; let icon: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline)
            content
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var jamf: JAMFService
    @EnvironmentObject var receiver: AgentReceiver
    @State private var search = ""
    @State private var selectedID: Int? = nil
    @State private var showSettings = false
    @State private var isRefreshing = false
    @State private var activeTab = 0 // 0 = Devices, 1 = Overview

    let refreshTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    var filtered: [JAMFDevice] {
        search.isEmpty ? jamf.devices :
        jamf.devices.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var selectedDevice: JAMFDevice? {
        guard let id = selectedID else { return nil }
        return jamf.devices.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Label("MacMonitor", systemImage: "desktopcomputer").font(.headline)
                    Spacer()
                    HStack(spacing: 4) {
                        Circle()
                            .fill(receiver.isRunning ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(receiver.isRunning ? "Listening" : "Stopped")
                            .font(.caption)
                            .foregroundColor(receiver.isRunning ? .green : .red)
                    }
                    Button {
                        refreshMetrics()
                    } label: {
                        if isRefreshing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.6)
                                .frame(width: 16, height: 16, alignment: .center)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .frame(width: 24, height: 24)
                    .disabled(isRefreshing)
                    .help("Refresh metrics now")
                    Button { showSettings = true } label: { Image(systemName: "gear") }
                }
                .padding(12)

                // Tab switcher
                Picker("", selection: $activeTab) {
                    Text("Devices").tag(0)
                    Text("Overview").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                Divider()

                if activeTab == 0 {
                    // Device list tab
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Search...", text: $search).textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    if jamf.isLoading {
                        Spacer()
                        ProgressView("Fetching from JAMF...")
                        Spacer()
                    } else if jamf.devices.isEmpty {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "server.rack").font(.largeTitle).foregroundColor(.secondary)
                            Text("No devices loaded").foregroundColor(.secondary)
                            Text("Open Settings to connect JAMF").font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        List(selection: $selectedID) {
                            ForEach(filtered) { device in
                                DeviceRowView(device: device).tag(device.id)
                            }
                        }
                    }
                } else {
                    // Overview tab — mini stats in sidebar
                    ScrollView {
                        VStack(spacing: 12) {
                            // Online status
                            VStack(spacing: 4) {
                                Text("FLEET STATUS")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)

                                HStack {
                                    miniStat("Reporting", "\(jamf.devices.filter { $0.metrics != nil }.count)", .green)
                                    miniStat("No Agent", "\(jamf.devices.filter { $0.metrics == nil }.count)", .orange)
                                }
                                .padding(.horizontal, 8)
                            }

                            Divider().padding(.horizontal, 8)

                            // Mini metric bars
                            let active = jamf.devices.filter { $0.metrics != nil }
                            if !active.isEmpty {
                                VStack(spacing: 10) {
                                    Text("AVERAGES")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)

                                    miniBar("CPU", avg(active, \.cpu.totalUsagePercent), .blue)
                                    miniBar("Memory", avg(active, \.memory.usagePercent), .orange)
                                    miniBar("Battery", avgBat(active), .green)
                                }

                                Divider().padding(.horizontal, 8)

                                // Alerts
                                let highCPU = active.filter { ($0.metrics?.cpu.totalUsagePercent ?? 0) > 70 }
                                let lowBat  = active.filter { ($0.metrics?.battery.percent ?? 100) < 20 && ($0.metrics?.battery.isCharging == false) }
                                let highMem = active.filter { ($0.metrics?.memory.usagePercent ?? 0) > 85 }

                                if !highCPU.isEmpty || !lowBat.isEmpty || !highMem.isEmpty {
                                    VStack(spacing: 6) {
                                        Text("ALERTS")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 12)

                                        if !highCPU.isEmpty {
                                            alertRow("cpu", "\(highCPU.count) high CPU", .red)
                                        }
                                        if !highMem.isEmpty {
                                            alertRow("memorychip", "\(highMem.count) high memory", .orange)
                                        }
                                        if !lowBat.isEmpty {
                                            alertRow("battery.25", "\(lowBat.count) low battery", .red)
                                        }
                                    }
                                } else {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                        Text("All systems healthy").font(.caption).foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 12)
                                }
                            }
                        }
                        .padding(.vertical, 12)
                    }
                }

                Divider()
                HStack {
                    Text("\(jamf.devices.count) devices").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("\(receiver.receivedCount) reports").font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
            .frame(minWidth: 320)

        } detail: {
            if activeTab == 1 {
                // Overview is full screen when tab is selected
                OverviewView()
                    .environmentObject(jamf)
                    .environmentObject(receiver)
            } else if let device = selectedDevice {
                DeviceDetailView(device: device)
                    .id(device.lastSeen?.timeIntervalSince1970 ?? 0)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 48)).foregroundColor(.secondary)
                    Text("Select a device to view metrics").foregroundColor(.secondary)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(jamf).environmentObject(receiver)
        }
        .onReceive(refreshTimer) { _ in refreshMetrics() }
        .onChange(of: receiver.receivedCount) { _ in
            if selectedID == nil {
                selectedID = jamf.devices.first { $0.metrics != nil }?.id
            }
        }
        .onChange(of: jamf.devices.count) { _ in
            if selectedID == nil {
                selectedID = jamf.devices.first { $0.metrics != nil }?.id
            }
            if let id = selectedID, !jamf.devices.contains(where: { $0.id == id }) {
                selectedID = jamf.devices.first { $0.metrics != nil }?.id
            }
        }
    }

    func avg(_ devices: [JAMFDevice], _ kp: KeyPath<DeviceMetrics, Double>) -> Double {
        guard !devices.isEmpty else { return 0 }
        let vals = devices.compactMap { $0.metrics.map { $0[keyPath: kp] } }
        return vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count)
    }
    func avgBat(_ devices: [JAMFDevice]) -> Double {
        guard !devices.isEmpty else { return 0 }
        let vals = devices.compactMap { $0.metrics?.battery.percent }
        return vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count)
    }

    @ViewBuilder
    func miniStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold)).foregroundColor(color)
            Text(label).font(.system(size: 10)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }

    @ViewBuilder
    func miniBar(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", value))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.15)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3).fill(color)
                        .frame(width: geo.size.width * CGFloat(min(value / 100, 1.0)), height: 6)
                }
            }
            .frame(height: 6)
            // Health score tag
            HStack {
                Spacer()
                Text(healthLabel(label: label, value: value))
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(healthColor(label: label, value: value).opacity(0.15))
                    .foregroundColor(healthColor(label: label, value: value))
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 12)
    }

    func healthLabel(label: String, value: Double) -> String {
        switch label {
        case "Battery":
            if value > 50 { return "✓ Good" }
            else if value > 20 { return "⚠ Low" }
            else { return "✗ Critical" }
        default:
            // CPU and Memory — lower is better
            if value < 40 { return "✓ Good" }
            else if value < 70 { return "⚠ Moderate" }
            else if value < 85 { return "✗ High" }
            else { return "✗ Critical" }
        }
    }

    func healthColor(label: String, value: Double) -> Color {
        switch label {
        case "Battery":
            return value > 50 ? .green : value > 20 ? .orange : .red
        default:
            return value < 40 ? .green : value < 70 ? .orange : .red
        }
    }

    @ViewBuilder
    func alertRow(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(color).frame(width: 14)
            Text(text).font(.system(size: 11)).foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 12)
    }

    func refreshMetrics() {
        guard !isRefreshing else { return }
        isRefreshing = true
        DispatchQueue.global(qos: .background).async {
            let task = Process()
            task.launchPath = "/usr/bin/python3"
            task.arguments = ["-c", """
import sys
sys.path.insert(0, '/Library/MacMonitor/libs')
import json, socket, subprocess, urllib.request
from datetime import datetime, timezone
import psutil

URL = "http://127.0.0.1:9876/metrics"

def serial():
    try:
        o = subprocess.check_output(["system_profiler","SPHardwareDataType"],text=True)
        for l in o.splitlines():
            if "Serial Number" in l: return l.split(":")[1].strip()
    except: pass
    return "UNKNOWN"

def battery():
    try:
        b = psutil.sensors_battery()
        return {"percent":b.percent if b else 0,"isCharging":bool(b.power_plugged) if b else False,
                "isPluggedIn":bool(b.power_plugged) if b else False,"cycleCount":None,"health":None}
    except:
        return {"percent":0,"isCharging":False,"isPluggedIn":False,"cycleCount":None,"health":None}

def network():
    try:
        n=psutil.net_io_counters(pernic=True)
        iface=next((k for k in n if k.startswith("en")),list(n.keys())[0])
        s=n[iface]
        return {"bytesSentMB":round(s.bytes_sent/1e6,2),"bytesReceivedMB":round(s.bytes_recv/1e6,2),"interface":iface}
    except:
        return {"bytesSentMB":0,"bytesReceivedMB":0,"interface":"unknown"}

def disk():
    try:
        d=psutil.disk_usage("/")
        return {"totalGB":round(d.total/1e9,2),"usedGB":round(d.used/1e9,2),
                "freeGB":round(d.free/1e9,2),"usagePercent":round(d.percent,1),"mountPoint":"/"}
    except:
        return {"totalGB":0,"usedGB":0,"freeGB":0,"usagePercent":0,"mountPoint":"/"}

def apps():
    out=[]
    for p in psutil.process_iter(["pid","name","cpu_percent","memory_info","status"]):
        try:
            i=p.info
            out.append({"pid":i["pid"],"name":i["name"] or "unknown",
                "cpuPercent":round(i["cpu_percent"] or 0,2),
                "memoryMB":round((i["memory_info"].rss if i["memory_info"] else 0)/1e6,2),
                "status":i["status"] or "unknown","isUserApp":True})
        except: pass
    top=sorted(out,key=lambda x:x["cpuPercent"],reverse=True)[:20]
    return top,[a for a in top if a["cpuPercent"]>0][:10]

cpu=psutil.cpu_percent(interval=2)
la=psutil.getloadavg()
mem=psutil.virtual_memory()
top_all,top_user=apps()
payload={
    "serialNumber":serial(),"hostname":socket.gethostname(),
    "timestamp":datetime.now(timezone.utc).isoformat(),
    "cpu":{"totalUsagePercent":cpu,"coreCount":psutil.cpu_count(logical=True),
           "loadAverage1m":round(la[0],2),"loadAverage5m":round(la[1],2),"loadAverage15m":round(la[2],2)},
    "memory":{"totalGB":round(mem.total/1e9,2),"usedGB":round(mem.used/1e9,2),
              "availableGB":round(mem.available/1e9,2),"usagePercent":mem.percent,"pressure":"normal"},
    "battery":battery(),"network":network(),"disk":disk(),
    "ipAddress":socket.gethostbyname(socket.gethostname()),
    "uptime":__import__("time").time()-psutil.boot_time(),
    "apps":top_all,"topCPUApps":top_user
}
req=urllib.request.Request(URL,data=json.dumps(payload).encode(),
    headers={"Content-Type":"application/json"},method="POST")
try:
    with urllib.request.urlopen(req,timeout=10) as r: print(f"OK {r.status}")
except Exception as e: print(f"Error: {e}")
"""]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            try? task.run()
            task.waitUntilExit()
            DispatchQueue.main.async { self.isRefreshing = false }
        }
    }
}

struct DeviceRowView: View {
    let device: JAMFDevice
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "desktopcomputer")
                .foregroundColor(device.metrics != nil ? .blue : .secondary)
                .frame(width: 20)
            Text(device.name).font(.system(size: 13, weight: .medium))
            Spacer()
            if let m = device.metrics {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.0f%%", m.cpu.totalUsagePercent))
                        .font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(cpuColor(m.cpu.totalUsagePercent).opacity(0.15))
                        .foregroundColor(cpuColor(m.cpu.totalUsagePercent))
                        .cornerRadius(4)
                    Text(ago(device.lastSeen)).font(.caption2).foregroundColor(.secondary)
                }
            } else {
                Text("No agent").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    func cpuColor(_ v: Double) -> Color { v < 40 ? .green : v < 70 ? .orange : .red }
    func ago(_ d: Date?) -> String {
        guard let d else { return "never" }
        let s = Int(-d.timeIntervalSinceNow)
        return s < 60 ? "\(s)s ago" : s < 3600 ? "\(s/60)m ago" : "\(s/3600)h ago"
    }
}

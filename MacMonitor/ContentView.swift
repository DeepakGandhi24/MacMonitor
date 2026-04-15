import SwiftUI

enum AppTab: String, CaseIterable {
    case dashboard = "Dashboard"
    case devices   = "Devices"
    case export    = "Export"

    var icon: String {
        switch self {
        case .dashboard: return "chart.bar.fill"
        case .devices:   return "desktopcomputer"
        case .export:    return "square.and.arrow.up"
        }
    }

    var color: Color {
        switch self {
        case .dashboard: return .blue
        case .devices:   return .indigo
        case .export:    return .orange
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var jamf: JAMFService
    @EnvironmentObject var receiver: AgentReceiver
    @State private var selectedTab: AppTab = .dashboard
    @State private var selectedDeviceID: Int? = nil
    @State private var showSettings = false
    @State private var isRefreshing = false
    @State private var search = ""
    @AppStorage("lastFetchDate") var lastFetchDate: Double = 0

    let refreshTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    var selectedDevice: JAMFDevice? {
        guard let id = selectedDeviceID else { return nil }
        return jamf.devices.first { $0.id == id }
    }

    var filtered: [JAMFDevice] {
        search.isEmpty ? jamf.devices :
        jamf.devices.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationSplitView {
            // ── Sidebar ───────────────────────────────────────
            VStack(spacing: 0) {

                // App header
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "desktopcomputer.and.arrow.down")
                                .font(.system(size: 18))
                                .foregroundColor(.blue)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MacMonitor")
                                .font(.system(size: 14, weight: .bold))
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(receiver.isRunning ? Color.green : Color.red)
                                    .frame(width: 6, height: 6)
                                Text(receiver.isRunning ? "Listening on :9876" : "Receiver stopped")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        // Settings button
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Settings")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider()

                // Tab navigation
                VStack(spacing: 2) {
                    ForEach(AppTab.allCases, id: \.self) { tab in
                        tabButton(tab)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                // Device list (only in Devices tab)
                if selectedTab == .devices {
                    Divider().padding(.top, 8)

                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary).font(.system(size: 11))
                        TextField("Search devices...", text: $search)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                    if jamf.isLoading {
                        Spacer()
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Fetching \(jamf.devices.count > 0 ? "\(jamf.devices.count)" : "") devices from JAMF...")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    } else if jamf.devices.isEmpty {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "server.rack").font(.largeTitle).foregroundColor(.secondary)
                            Text("No devices loaded").foregroundColor(.secondary)
                            Text("Open Settings → JAMF to connect").font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        List(selection: $selectedDeviceID) {
                            ForEach(filtered) { device in
                                DeviceRowView(device: device).tag(device.id)
                            }
                        }
                        .listStyle(.sidebar)
                    }
                } else {
                    Spacer()
                }

                Divider()

                // Footer
                HStack {
                    Button {
                        isRefreshing = true
                        refreshMetrics()
                    } label: {
                        HStack(spacing: 4) {
                            if isRefreshing {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11))
                            }
                            Text("Refresh")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(jamf.devices.count) devices")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("\(jamf.devices.filter { $0.metrics != nil }.count) reporting")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .frame(minWidth: 220, maxWidth: 260)

        } detail: {
            // ── Detail panel ──────────────────────────────────
            switch selectedTab {
            case .dashboard:
                OverviewView()
                    .environmentObject(jamf)
                    .environmentObject(receiver)
            case .devices:
                if let device = selectedDevice {
                    DeviceDetailView(device: device)
                        .id(device.lastSeen?.timeIntervalSince1970 ?? 0)
                } else {
                    emptyState(
                        icon: "desktopcomputer",
                        title: "Select a Device",
                        subtitle: "Choose a device from the sidebar to view its metrics"
                    )
                }
            case .export:
                ExportPanelView()
                    .environmentObject(jamf)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(jamf)
                .environmentObject(receiver)
        }
        .onReceive(refreshTimer) { _ in refreshMetrics() }
        .onChange(of: receiver.receivedCount) { _ in
            if selectedDeviceID == nil {
                selectedDeviceID = jamf.devices.first { $0.metrics != nil }?.id
            }
        }
        .onChange(of: jamf.devices.count) { _ in
            if selectedDeviceID == nil {
                selectedDeviceID = jamf.devices.first { $0.metrics != nil }?.id
            }
        }
        .onChange(of: selectedTab) { tab in
            if tab == .devices && selectedDeviceID == nil {
                selectedDeviceID = jamf.devices.first { $0.metrics != nil }?.id
            }
        }
    }

    // MARK: - Tab Button
    @ViewBuilder
    func tabButton(_ tab: AppTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selectedTab == tab ? tab.color.opacity(0.15) : Color.clear)
                        .frame(width: 28, height: 28)
                    Image(systemName: tab.icon)
                        .font(.system(size: 13))
                        .foregroundColor(selectedTab == tab ? tab.color : .secondary)
                }
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                    .foregroundColor(selectedTab == tab ? .primary : .secondary)
                Spacer()
                if let b = badge(for: tab), b > 0 {
                    Text("\(b)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.red)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedTab == tab ? tab.color.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State
    @ViewBuilder
    func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text(title).font(.title3).fontWeight(.medium)
            Text(subtitle).font(.body).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Badges
    func badge(for tab: AppTab) -> Int? {
        switch tab {
        case .dashboard:
            let alerts = jamf.devices.filter { d in
                guard let m = d.metrics else { return false }
                return m.cpu.totalUsagePercent > 70 ||
                       m.memory.usagePercent > 85 ||
                       (m.battery.percent < 20 && !m.battery.isCharging)
            }.count
            return alerts > 0 ? alerts : nil
        case .devices:
            return jamf.devices.filter { $0.metrics != nil }.count > 0 ?
                   jamf.devices.filter { $0.metrics != nil }.count : nil
        default:
            return nil
        }
    }

    // MARK: - Refresh
    func refreshMetrics() {
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
    "ipAddress": __import__("subprocess").check_output(["ipconfig","getifaddr","en0"],text=True).strip() or "127.0.0.1",
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

import Foundation
import AppKit

struct AgentScriptGenerator {

    static func pythonScript(ip: String, port: Int = 9876) -> String {
        return """
#!/usr/bin/env python3
import json, socket, subprocess, time, urllib.request
from datetime import datetime, timezone
try:
    import psutil
except ImportError:
    import sys
    subprocess.check_call([sys.executable,"-m","pip","install","psutil","--quiet"])
    import psutil

URL = "http://\(ip):\(port)/metrics"
INTERVAL = 300

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
        o = subprocess.check_output(["system_profiler","SPPowerDataType"],text=True)
        cc, h = None, None
        for l in o.splitlines():
            if "Cycle Count" in l: cc = int(l.split(":")[1].strip())
            if "Condition" in l: h = l.split(":")[1].strip()
        return {"percent": b.percent if b else 0,
                "isCharging": bool(b.power_plugged) if b else False,
                "isPluggedIn": bool(b.power_plugged) if b else False,
                "cycleCount": cc, "health": h}
    except:
        return {"percent":0,"isCharging":False,"isPluggedIn":False,"cycleCount":None,"health":None}

def network():
    try:
        n = psutil.net_io_counters(pernic=True)
        iface = next((k for k in n if k.startswith("en")), list(n.keys())[0])
        s = n[iface]
        return {"bytesSentMB": round(s.bytes_sent/1e6,2),
                "bytesReceivedMB": round(s.bytes_recv/1e6,2), "interface": iface}
    except:
        return {"bytesSentMB":0,"bytesReceivedMB":0,"interface":"unknown"}

def apps():
    out = []
    for p in psutil.process_iter(['pid','name','cpu_percent','memory_info','status']):
        try:
            i = p.info
            out.append({"pid":i['pid'],"name":i['name'] or "unknown",
                "cpuPercent":round(i['cpu_percent'] or 0,2),
                "memoryMB":round((i['memory_info'].rss if i['memory_info'] else 0)/1e6,2),
                "status":i['status'] or "unknown"})
        except: pass
    return sorted(out, key=lambda x: x['cpuPercent'], reverse=True)[:20]

def run():
    cpu = psutil.cpu_percent(interval=2)
    la  = psutil.getloadavg()
    mem = psutil.virtual_memory()
    payload = {
        "serialNumber": serial(), "hostname": socket.gethostname(),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "cpu": {"totalUsagePercent": cpu, "coreCount": psutil.cpu_count(logical=True),
                "loadAverage1m": round(la[0],2), "loadAverage5m": round(la[1],2),
                "loadAverage15m": round(la[2],2)},
        "memory": {"totalGB": round(mem.total/1e9,2), "usedGB": round(mem.used/1e9,2),
                   "availableGB": round(mem.available/1e9,2), "usagePercent": mem.percent},
        "battery": battery(), "network": network(),
        "uptime": datetime.now().timestamp() - psutil.boot_time(), "apps": apps()
    }
    req = urllib.request.Request(URL, data=json.dumps(payload).encode(),
        headers={"Content-Type":"application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=10) as r: print(f"[Agent] OK {r.status}")
    except Exception as e: print(f"[Agent] Error: {e}")

if __name__ == "__main__":
    while True: run(); time.sleep(INTERVAL)
"""
    }

    static func plist() -> String {
        return """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>com.macmonitor.agent</string>
    <key>ProgramArguments</key><array>
        <string>/usr/bin/python3</string>
        <string>/Library/MacMonitor/agent.py</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>/Library/MacMonitor/agent.log</string>
    <key>StandardErrorPath</key><string>/Library/MacMonitor/agent_error.log</string>
</dict></plist>
"""
    }

    // MARK: - Export directly to Desktop/MacMonitorAgent/ (no NSOpenPanel)
    static func exportAll(dashboardIP: String) {
        // Try Desktop first, fall back to Documents if sandbox blocks Desktop
        let fm = FileManager.default
        let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let base = desktop ?? documents
        let dir = base.appendingPathComponent("MacMonitorAgent")

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)

            let agentURL = dir.appendingPathComponent("agent.py")
            let plistURL = dir.appendingPathComponent("com.macmonitor.agent.plist")

            try pythonScript(ip: dashboardIP).write(to: agentURL, atomically: true, encoding: .utf8)
            try plist().write(to: plistURL, atomically: true, encoding: .utf8)

            // Open folder in Finder
            NSWorkspace.shared.open(dir)

            showAlert(
                title: "✅ Agent Files Exported",
                message: "Saved to:\n\(dir.path)\n\n• agent.py\n• com.macmonitor.agent.plist\n\nTo test on this Mac:\npip3 install psutil\npython3 \(dir.path)/agent.py"
            )
        } catch {
            showAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private static func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = title.contains("Failed") ? .critical : .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

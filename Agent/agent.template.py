#!/usr/bin/env python3
import sys
sys.path.insert(0, '/Library/MacMonitor/libs')
import json, socket, subprocess, time, urllib.request
from datetime import datetime, timezone
import psutil

URL = "http://127.0.0.1:9876/metrics"
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
        return {"percent":b.percent if b else 0,"isCharging":bool(b.power_plugged) if b else False,
                "isPluggedIn":bool(b.power_plugged) if b else False,"cycleCount":None,"health":None}
    except:
        return {"percent":0,"isCharging":False,"isPluggedIn":False,"cycleCount":None,"health":None}

def network():
    try:
        n1 = psutil.net_io_counters(pernic=True)
        time.sleep(1)
        n2 = psutil.net_io_counters(pernic=True)
        iface = next((k for k in n2 if k.startswith("en")), list(n2.keys())[0])
        s1,s2 = n1[iface],n2[iface]
        return {
            "bytesSentMB": round(s2.bytes_sent/1e6,2),
            "bytesReceivedMB": round(s2.bytes_recv/1e6,2),
            "interface": iface,
            "sentRateKBs": round((s2.bytes_sent-s1.bytes_sent)/1024,1),
            "recvRateKBs": round((s2.bytes_recv-s1.bytes_recv)/1024,1)
        }
    except:
        return {"bytesSentMB":0,"bytesReceivedMB":0,"interface":"unknown","sentRateKBs":0,"recvRateKBs":0}

def disk():
    try:
        d = psutil.disk_usage("/")
        return {"totalGB":round(d.total/1e9,2),"usedGB":round(d.used/1e9,2),
                "freeGB":round(d.free/1e9,2),"usagePercent":round(d.percent,1),"mountPoint":"/"}
    except:
        return {"totalGB":0,"usedGB":0,"freeGB":0,"usagePercent":0,"mountPoint":"/"}

def apps():
    proc_list = []
    for p in psutil.process_iter(["pid","name","memory_info","status"]):
        try:
            p.cpu_percent(interval=None)
            proc_list.append(p)
        except: pass
    time.sleep(2)
    out = []
    for p in proc_list:
        try:
            cpu = p.cpu_percent(interval=None)
            mem = p.memory_info()
            out.append({
                "pid": p.pid,
                "name": p.name() or "unknown",
                "cpuPercent": round(cpu,2),
                "memoryMB": round((mem.rss if mem else 0)/1e6,2),
                "status": p.status() or "unknown",
                "isUserApp": True
            })
        except: pass
    top = sorted(out,key=lambda x:x["cpuPercent"],reverse=True)[:20]
    return top,[a for a in top if a["cpuPercent"]>0.1][:10]

def run():
    psutil.cpu_percent(interval=None)
    time.sleep(2)
    cpu = psutil.cpu_percent(interval=None)
    la = psutil.getloadavg()
    mem = psutil.virtual_memory()
    pressure = "critical" if mem.percent>85 else "warning" if mem.percent>70 else "normal"
    top_all,top_user = apps()
    net = network()
    try:
        ip = subprocess.check_output(["ipconfig","getifaddr","en0"],text=True).strip()
    except:
        ip = "127.0.0.1"
    payload = {
        "serialNumber": serial(),
        "hostname": socket.gethostname(),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "cpu": {
            "totalUsagePercent": cpu,
            "coreCount": psutil.cpu_count(logical=True),
            "loadAverage1m": round(la[0],2),
            "loadAverage5m": round(la[1],2),
            "loadAverage15m": round(la[2],2)
        },
        "memory": {
            "totalGB": round(mem.total/1e9,2),
            "usedGB": round(mem.used/1e9,2),
            "availableGB": round(mem.available/1e9,2),
            "usagePercent": mem.percent,
            "pressure": pressure
        },
        "battery": battery(),
        "network": net,
        "disk": disk(),
        "ipAddress": ip,
        "uptime": time.time()-psutil.boot_time(),
        "apps": top_all,
        "topCPUApps": top_user
    }
    req = urllib.request.Request(URL,data=json.dumps(payload).encode(),
        headers={"Content-Type":"application/json"},method="POST")
    try:
        with urllib.request.urlopen(req,timeout=15) as r:
            print(f"[Agent] OK {r.status} CPU:{cpu}% NET_RECV:{net['recvRateKBs']}KB/s")
    except Exception as e:
        print(f"[Agent] Error: {e}")

import os
if __name__=="__main__":
    if os.environ.get("SINGLE_RUN") == "1":
        run()
    else:
        print(f"[Agent] Starting -> {URL}")
        run()
        while True:
            time.sleep(INTERVAL)
            run()


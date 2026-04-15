# 🖥️ MacMonitor

<div align="center">

![macOS](https://img.shields.io/badge/macOS-13.0+-blue?style=for-the-badge&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=for-the-badge&logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-5.0-purple?style=for-the-badge&logo=swift&logoColor=white)
![JAMF](https://img.shields.io/badge/JAMF-Pro-red?style=for-the-badge&logo=jamf&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

**A native macOS SwiftUI app for monitoring Mac fleet performance via JAMF Pro.**

Real-time CPU · Memory · Disk · Battery · Network metrics for all your managed Macs.

[Features](#-features) • [Requirements](#-requirements) • [Installation](#-installation) • [Setup](#-setup) • [Agent](#-how-the-agent-works) • [Integrations](#-integrations)

</div>

---

## ✨ Features

| Feature | Description |
|---|---|
| 🔗 **JAMF Pro Integration** | Fetches full device inventory via OAuth2 API |
| 📊 **Real-time Metrics** | CPU, memory pressure, disk space, battery health, network rates |
| 🗂️ **Fleet Overview** | Combined stats with gauges, distribution charts and alerts |
| 🖥️ **Per-device Detail** | Top processes, load averages, memory breakdown |
| 🤖 **Agent-based Collection** | Lightweight Python agent runs as a launchd daemon |
| 📤 **CSV Export** | Export all devices or reporting devices for auditing |
| 💬 **Microsoft Teams** | Post fleet health reports via Incoming Webhook |
| 🎫 **ServiceNow** | Auto-create incidents for devices with performance issues |
| 🔐 **Keychain Storage** | Credentials stored securely, never in plain text |

---

## 📋 Requirements

- 🍎 macOS 13.0 (Ventura) or later
- 🛠️ Xcode 15 or later
- 🏢 JAMF Pro with OAuth2 API client configured
- 🐍 Python 3 on managed Macs (pre-installed on macOS)

---

## 📦 Installation

```bash
git clone https://github.com/DeepakGandhi24/MacMonitor.git
cd MacMonitor
open MacMonitor.xcodeproj
```

1. In Xcode select your team under **Signing & Capabilities**
2. Press **⌘R** to build and run

---

## ⚙️ Setup

### Step 1 — Connect to JAMF Pro

1. Launch **MacMonitor**
2. Click the **⚙️ gear icon → JAMF tab**
3. Enter your JAMF Pro URL, Client ID and Client Secret
4. Tick **Save credentials to Keychain** ✅
5. Click **Test Auth** → wait for ✅ Authentication successful
6. Click **Fetch Devices** → all your Macs appear in the sidebar

### Step 2 — Create a JAMF Pro API Client

1. JAMF Pro → **Settings → API Roles and Clients**
2. Create an **API Role** with:
   - `Read Computers`
   - `Read Computer Inventory Collection`
3. Create an **API Client** → assign the role → generate a **Client Secret**

### Step 3 — Install Agent on the Dashboard Mac

1. **Settings → Agent tab**
2. Enter this Mac's IP address
3. Click **Install & Start Agent** → enter admin password
4. Agent starts automatically and posts metrics every 5 minutes ✅

### Step 4 — Deploy to All Macs via JAMF

1. **Settings → Agent tab → Export for JAMF Deployment**
2. Files saved to `~/Desktop/MacMonitorAgent/`
3. JAMF Pro → **Scripts → New** → paste `jamf_deploy.sh`
4. Create **Policy** → scope to **All Computers** → trigger **Recurring Check-in**

> ✅ Once deployed, each Mac's agent phones home to the dashboard automatically.

---

## 🏗️ Project Structure

```
MacMonitor/
├── 📁 MacMonitor.xcodeproj/
├── 📁 MacMonitor/
│   ├── MacMonitorApp.swift          ← App entry point
│   ├── ContentView.swift            ← Main navigation (sidebar + tabs)
│   ├── OverviewView.swift           ← Fleet overview dashboard
│   ├── DeviceDetailView.swift       ← Per-device metrics
│   ├── ExportPanelView.swift        ← CSV export UI
│   ├── SettingsView.swift           ← JAMF, Agent, Export, Integrations
│   ├── JAMFService.swift            ← JAMF Pro API (OAuth2 + device fetch)
│   ├── AgentReceiver.swift          ← HTTP server (receives agent POSTs)
│   ├── AgentScriptGenerator.swift   ← Generates agent.py + deploy script
│   ├── KeychainService.swift        ← Secure credential storage
│   ├── ExportService.swift          ← CSV, Teams, ServiceNow
│   └── Models.swift                 ← Data models
└── 📁 Agent/
    ├── agent.template.py            ← Reference only — generate via app
    └── com.macmonitor.agent.plist   ← launchd daemon configuration
```

---

## 🤖 How the Agent Works

```
Mac boots
  ↓
launchd reads com.macmonitor.agent.plist
  ↓
Starts agent.py as a background daemon (runs as root)
  ↓
Every 5 minutes collects:
  CPU usage · Memory · Disk · Battery · Network · Top processes
  ↓
POSTs JSON payload to Dashboard Mac on port 9876
  ↓
If agent crashes → launchd restarts it automatically ♻️
```

> ⚠️ **Always generate the agent via the app** — Settings → Agent → Export for JAMF Deployment.
> This ensures your dashboard Mac's IP is correctly embedded in the script.
> The `Agent/agent.template.py` in this repo is a **reference only**.

---

## 🔗 Integrations

### 💬 Microsoft Teams

1. Teams → Channel → **···** → **Connectors → Incoming Webhook** → copy URL
2. MacMonitor → **Settings → Integrations → Teams**
3. Paste URL → click **Send Fleet Report Now**

### 🎫 ServiceNow

1. MacMonitor → **Settings → Integrations → ServiceNow**
2. Enter instance URL, username and password
3. Devices with issues appear automatically
4. Click **Create Incident** per device or **Create All Incidents**

---

## 🔒 Privacy & Security

- ✅ No data leaves your network except to your own JAMF Pro server
- ✅ All credentials stored in **macOS Keychain** (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- ✅ Agent communicates only with the dashboard Mac's IP on port 9876
- ✅ No third-party services, no telemetry, no cloud storage

---

## 🔧 Troubleshooting

| Problem | Solution |
|---|---|
| No devices loading | Settings → JAMF → **Test Auth** |
| Dashboard shows only 1 device | Enter credentials → Settings → JAMF → **Fetch Devices** |
| Agent shows 0% CPU | Reinstall agent → Settings → Agent → **Install & Start** |
| Network shows 0 KB/s | Normal when idle — no active traffic during measurement |
| Agent not posting | `tail -f /Library/MacMonitor/agent.log` |
| Firewall blocking port 9876 | Create JAMF config profile to allow incoming connections |

---

## 📄 License

MIT — see [LICENSE](LICENSE)

---

## 🙏 Acknowledgements

- [JAMF Pro API](https://developer.jamf.com/) documentation
- [psutil](https://github.com/giampaolo/psutil) — Python system metrics library
- Built with [SwiftUI](https://developer.apple.com/xcode/swiftui/) on macOS
- AI assistance — [Claude](https://claude.ai) by Anthropic

---

<div align="center">
Made with ❤️ for Mac Admins
</div>

import Foundation
import AppKit

struct ExportService {

    // MARK: - CSV Export
    static func exportCSV(devices: [JAMFDevice]) {
        let header = "Device Name,Serial Number,Username,CPU %,Memory %,Memory Used GB,Memory Total GB,Disk %,Disk Used GB,Disk Free GB,Battery %,Charging,Uptime,Last Report,Top Process,Top Process CPU%"

        let rows = devices.map { d -> String in
            let m = d.metrics
            let name = d.name
            let serial = d.serialNumber
            let user = d.username ?? ""
            let cpu = m.map { String(format: "%.1f", $0.cpu.totalUsagePercent) } ?? ""
            let memPct = m.map { String(format: "%.1f", $0.memory.usagePercent) } ?? ""
            let memUsed = m.map { String(format: "%.1f", $0.memory.usedGB) } ?? ""
            let memTotal = m.map { String(format: "%.1f", $0.memory.totalGB) } ?? ""
            let diskPct = m?.disk.map { String(format: "%.1f", $0.usagePercent) } ?? ""
            let diskUsed = m?.disk.map { String(format: "%.1f", $0.usedGB) } ?? ""
            let diskFree = m?.disk.map { String(format: "%.1f", $0.freeGB) } ?? ""
            let bat = m.map { String(format: "%.0f", $0.battery.percent) } ?? ""
            let charging = m.map { $0.battery.isCharging ? "Yes" : "No" } ?? ""
            let uptime = m.map { formatUptime($0.uptime) } ?? ""
            let lastReport = d.lastSeen.map { formatDate($0) } ?? "Never"
            let topProc = m?.apps.first?.name ?? ""
            let topProcCPU = m?.apps.first.map { String(format: "%.1f", $0.cpuPercent) } ?? ""

            return [name, serial, user, cpu, memPct, memUsed, memTotal,
                    diskPct, diskUsed, diskFree, bat, charging, uptime,
                    lastReport, topProc, topProcCPU]
                .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: ",")
        }

        let csv = ([header] + rows).joined(separator: "\n")

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MacMonitor_Export_\(dateStamp()).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.message = "Export device data to CSV"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.open(url)
            } catch {
                showAlert("Export Failed", error.localizedDescription)
            }
        }
    }

    // MARK: - Export only reporting devices
    static func exportReportingCSV(devices: [JAMFDevice]) {
        exportCSV(devices: devices.filter { $0.metrics != nil })
    }

    // MARK: - Teams Webhook
    static func sendTeamsAlert(webhookURL: String, devices: [JAMFDevice]) async {
        guard let url = URL(string: webhookURL) else { return }

        let highCPU = devices.filter { ($0.metrics?.cpu.totalUsagePercent ?? 0) > 70 }
        let lowBat  = devices.filter { ($0.metrics?.battery.percent ?? 100) < 20 && ($0.metrics?.battery.isCharging == false) }
        let highMem = devices.filter { ($0.metrics?.memory.usagePercent ?? 0) > 85 }
        let reporting = devices.filter { $0.metrics != nil }

        var facts: [[String: String]] = [
            ["title": "Total Devices", "value": "\(devices.count)"],
            ["title": "Reporting", "value": "\(reporting.count)"],
            ["title": "High CPU (>70%)", "value": "\(highCPU.count)"],
            ["title": "High Memory (>85%)", "value": "\(highMem.count)"],
            ["title": "Low Battery (<20%)", "value": "\(lowBat.count)"]
        ]

        // Add top 3 high CPU devices
        for d in highCPU.prefix(3) {
            if let cpu = d.metrics?.cpu.totalUsagePercent {
                facts.append(["title": "⚠️ \(d.name)", "value": String(format: "CPU: %.1f%%", cpu)])
            }
        }

        let hasAlerts = !highCPU.isEmpty || !lowBat.isEmpty || !highMem.isEmpty
        let themeColor = hasAlerts ? "FF0000" : "00B050"
        let title = hasAlerts ? "⚠️ MacMonitor Alert" : "✅ MacMonitor Fleet Report"
        let summary = hasAlerts
            ? "\(highCPU.count) high CPU, \(highMem.count) high memory, \(lowBat.count) low battery"
            : "Fleet is healthy — \(reporting.count) Macs reporting"

        let payload: [String: Any] = [
            "@type": "MessageCard",
            "@context": "http://schema.org/extensions",
            "themeColor": themeColor,
            "summary": summary,
            "sections": [[
                "activityTitle": title,
                "activitySubtitle": "Generated \(formatDate(Date()))",
                "facts": facts,
                "markdown": true
            ]]
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            await MainActor.run {
                showAlert(status == 200 ? "✅ Teams Alert Sent" : "⚠️ Teams Error",
                          status == 200 ? "Fleet report posted to Teams channel." : "HTTP \(status)")
            }
        } catch {
            await MainActor.run { showAlert("Teams Error", error.localizedDescription) }
        }
    }

    // MARK: - ServiceNow
    static func createServiceNowIncident(
        instanceURL: String, username: String, password: String,
        device: JAMFDevice
    ) async {
        guard let m = device.metrics else { return }
        guard let url = URL(string: "\(instanceURL)/api/now/table/incident") else { return }

        var issues: [String] = []
        if m.cpu.totalUsagePercent > 70 { issues.append("High CPU: \(String(format: "%.1f", m.cpu.totalUsagePercent))%") }
        if m.memory.usagePercent > 85   { issues.append("High Memory: \(String(format: "%.1f", m.memory.usagePercent))%") }
        if m.battery.percent < 20 && !m.battery.isCharging { issues.append("Low Battery: \(String(format: "%.0f", m.battery.percent))%") }
        if (m.disk?.usagePercent ?? 0) > 85 { issues.append("Low Disk: \(String(format: "%.1f", m.disk!.usagePercent))% used") }

        let description = """
Mac: \(device.name)
Serial: \(device.serialNumber)
User: \(device.username ?? "Unknown")

Performance Issues:
\(issues.joined(separator: "\n"))

CPU: \(String(format: "%.1f", m.cpu.totalUsagePercent))% | \(m.cpu.coreCount) cores
Memory: \(String(format: "%.1f", m.memory.usedGB))GB / \(String(format: "%.1f", m.memory.totalGB))GB
Disk: \(m.disk.map { String(format: "%.0f", $0.usedGB) } ?? "?")GB used
Battery: \(String(format: "%.0f", m.battery.percent))%
Uptime: \(formatUptime(m.uptime))
Last Report: \(device.lastSeen.map { formatDate($0) } ?? "Unknown")
"""

        let priority = issues.count >= 2 ? "2" : "3"
        let body: [String: Any] = [
            "short_description": "Mac Performance Issue — \(device.name)",
            "description": description,
            "category": "hardware",
            "subcategory": "performance",
            "priority": priority,
            "caller_id": device.username ?? "macmonitor",
            "cmdb_ci": device.name
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let credentials = "\(username):\(password)".data(using: .utf8)!.base64EncodedString()
        req.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status == 201 {
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let result = json?["result"] as? [String: Any]
                let number = result?["number"] as? String ?? "Unknown"
                await MainActor.run {
                    showAlert("✅ Incident Created", "ServiceNow incident \(number) created for \(device.name)")
                }
            } else {
                await MainActor.run { showAlert("ServiceNow Error", "HTTP \(status)") }
            }
        } catch {
            await MainActor.run { showAlert("ServiceNow Error", error.localizedDescription) }
        }
    }

    // MARK: - Helpers
    static func formatUptime(_ s: Double) -> String {
        let h = Int(s) / 3600; let d = h / 24
        return d > 0 ? "\(d)d \(h % 24)h" : "\(h)h"
    }

    static func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: d)
    }

    static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        return f.string(from: Date())
    }

    static func showAlert(_ title: String, _ msg: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = msg
        a.alertStyle = title.contains("Error") || title.contains("Failed") ? .critical : .informational
        a.addButton(withTitle: "OK")
        a.runModal()
    }
}

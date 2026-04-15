import SwiftUI

struct ExportPanelView: View {
    @EnvironmentObject var jamf: JAMFService

    var reporting: [JAMFDevice] { jamf.devices.filter { $0.metrics != nil } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Export").font(.title2).bold()
                    Text("Export device data for auditing and reporting")
                        .foregroundColor(.secondary)
                }

                // Stats row
                HStack(spacing: 12) {
                    exportStat("\(jamf.devices.count)", "Total Devices", .blue)
                    exportStat("\(reporting.count)", "With Agent Data", .green)
                    exportStat("\(jamf.devices.count - reporting.count)", "No Agent", .orange)
                }

                // Export options
                VStack(spacing: 12) {

                    ExportCard(
                        icon: "tablecells",
                        iconColor: .blue,
                        title: "All Devices",
                        subtitle: "Exports all \(jamf.devices.count) JAMF devices. Devices without agent show blank metrics.",
                        buttonLabel: "Export to CSV",
                        buttonColor: .blue,
                        disabled: jamf.devices.isEmpty
                    ) {
                        ExportService.exportCSV(devices: jamf.devices)
                    }

                    ExportCard(
                        icon: "tablecells.badge.ellipsis",
                        iconColor: .green,
                        title: "Reporting Devices Only",
                        subtitle: "Exports \(reporting.count) devices with full metrics — CPU, memory, disk, battery, top processes.",
                        buttonLabel: "Export to CSV",
                        buttonColor: .green,
                        disabled: reporting.isEmpty
                    ) {
                        ExportService.exportReportingCSV(devices: jamf.devices)
                    }

                    ExportCard(
                        icon: "exclamationmark.triangle.fill",
                        iconColor: .red,
                        title: "Alert Devices",
                        subtitle: "Exports only devices with performance issues — high CPU (>70%), high memory (>85%), low battery (<20%), or low disk (>85%).",
                        buttonLabel: "Export Alerts to CSV",
                        buttonColor: .red,
                        disabled: alertDevices.isEmpty
                    ) {
                        ExportService.exportCSV(devices: alertDevices)
                    }
                }

                // CSV columns info
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("CSV Columns", systemImage: "info.circle")
                            .font(.subheadline).fontWeight(.medium)
                        Text("Device Name · Serial Number · Username · CPU% · Memory% · Memory Used GB · Memory Total GB · Disk% · Disk Used GB · Disk Free GB · Battery% · Charging · Uptime · Last Report · Top Process · Top Process CPU%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(24)
        }
    }

    var alertDevices: [JAMFDevice] {
        jamf.devices.filter { d in
            guard let m = d.metrics else { return false }
            return m.cpu.totalUsagePercent > 70 ||
                   m.memory.usagePercent > 85 ||
                   (m.battery.percent < 20 && !m.battery.isCharging) ||
                   (m.disk?.usagePercent ?? 0) > 85
        }
    }

    @ViewBuilder
    func exportStat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 28, weight: .bold)).foregroundColor(color)
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.08))
        .cornerRadius(12)
    }
}

struct ExportCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let buttonLabel: String
    let buttonColor: Color
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: action) {
                Text(buttonLabel)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(disabled ? Color.secondary.opacity(0.2) : buttonColor)
                    .foregroundColor(disabled ? .secondary : .white)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(disabled)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

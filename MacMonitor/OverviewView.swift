import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var jamf: JAMFService
    @EnvironmentObject var receiver: AgentReceiver

    var activeDevices: [JAMFDevice] { jamf.devices.filter { $0.metrics != nil } }
    var totalDevices: Int { jamf.devices.count }
    var onlineCount: Int { activeDevices.count }

    var avgCPU: Double {
        guard !activeDevices.isEmpty else { return 0 }
        return activeDevices.compactMap { $0.metrics?.cpu.totalUsagePercent }.reduce(0, +) / Double(activeDevices.count)
    }
    var avgMemory: Double {
        guard !activeDevices.isEmpty else { return 0 }
        return activeDevices.compactMap { $0.metrics?.memory.usagePercent }.reduce(0, +) / Double(activeDevices.count)
    }
    var avgDisk: Double {
        guard !activeDevices.isEmpty else { return 0 }
        let disks = activeDevices.compactMap { $0.metrics?.disk?.usagePercent }
        return disks.isEmpty ? 0 : disks.reduce(0, +) / Double(disks.count)
    }
    var avgBattery: Double {
        guard !activeDevices.isEmpty else { return 0 }
        return activeDevices.compactMap { $0.metrics?.battery.percent }.reduce(0, +) / Double(activeDevices.count)
    }
    var highCPUDevices: [JAMFDevice] {
        activeDevices.filter { ($0.metrics?.cpu.totalUsagePercent ?? 0) > 70 }
            .sorted { ($0.metrics?.cpu.totalUsagePercent ?? 0) > ($1.metrics?.cpu.totalUsagePercent ?? 0) }
    }
    var lowBatteryDevices: [JAMFDevice] {
        activeDevices.filter { ($0.metrics?.battery.percent ?? 100) < 20 && ($0.metrics?.battery.isCharging == false) }
            .sorted { ($0.metrics?.battery.percent ?? 0) < ($1.metrics?.battery.percent ?? 0) }
    }
    var highMemoryDevices: [JAMFDevice] {
        activeDevices.filter { ($0.metrics?.memory.usagePercent ?? 0) > 80 }
            .sorted { ($0.metrics?.memory.usagePercent ?? 0) > ($1.metrics?.memory.usagePercent ?? 0) }
    }
    var highDiskDevices: [JAMFDevice] {
        activeDevices.filter { ($0.metrics?.disk?.usagePercent ?? 0) > 85 }
            .sorted { ($0.metrics?.disk?.usagePercent ?? 0) > ($1.metrics?.disk?.usagePercent ?? 0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── Fleet Status ──────────────────────────────────
                HStack(spacing: 12) {
                    FleetStatCard(value: "\(totalDevices)", label: "Total Devices", icon: "desktopcomputer", color: .blue)
                    FleetStatCard(value: "\(onlineCount)", label: "Reporting", icon: "antenna.radiowaves.left.and.right", color: .green)
                    FleetStatCard(value: "\(totalDevices - onlineCount)", label: "No Agent", icon: "exclamationmark.triangle", color: .orange)
                    FleetStatCard(value: "\(highCPUDevices.count)", label: "High CPU", icon: "cpu", color: .red)
                    FleetStatCard(value: "\(lowBatteryDevices.count)", label: "Low Battery", icon: "battery.25", color: .red)
                }

                // ── Average Metrics ───────────────────────────────
                if !activeDevices.isEmpty {
                    Text("Fleet Averages (\(onlineCount) reporting Macs)")
                        .font(.headline)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                        GaugeCard(title: "Avg CPU", value: avgCPU, color: gaugeColor(avgCPU, warn: 60, crit: 80), unit: "%")
                        GaugeCard(title: "Avg Memory", value: avgMemory, color: gaugeColor(avgMemory, warn: 70, crit: 85), unit: "%")
                        GaugeCard(title: "Avg Disk", value: avgDisk, color: gaugeColor(avgDisk, warn: 70, crit: 85), unit: "%")
                        GaugeCard(title: "Avg Battery", value: avgBattery, color: batColor(avgBattery), unit: "%")
                    }

                    // ── CPU Distribution Bar ──────────────────────
                    SectionCard(title: "CPU Distribution", icon: "cpu") {
                        VStack(spacing: 8) {
                            DistributionBar(
                                segments: [
                                    (label: "Low <40%",  count: activeDevices.filter { ($0.metrics?.cpu.totalUsagePercent ?? 0) < 40 }.count,  color: .green),
                                    (label: "Med 40-70%", count: activeDevices.filter { let v = $0.metrics?.cpu.totalUsagePercent ?? 0; return v >= 40 && v < 70 }.count, color: .orange),
                                    (label: "High >70%", count: activeDevices.filter { ($0.metrics?.cpu.totalUsagePercent ?? 0) >= 70 }.count, color: .red)
                                ],
                                total: activeDevices.count
                            )
                            TopDevicesList(title: "Top CPU Consumers", devices: Array(highCPUDevices.prefix(5)),
                                          value: { String(format: "%.1f%%", $0.metrics?.cpu.totalUsagePercent ?? 0) },
                                          color: .red)
                        }
                    }

                    // ── Memory Distribution ───────────────────────
                    SectionCard(title: "Memory Distribution", icon: "memorychip") {
                        VStack(spacing: 8) {
                            DistributionBar(
                                segments: [
                                    (label: "Normal <70%", count: activeDevices.filter { ($0.metrics?.memory.usagePercent ?? 0) < 70 }.count, color: .green),
                                    (label: "Warning 70-85%", count: activeDevices.filter { let v = $0.metrics?.memory.usagePercent ?? 0; return v >= 70 && v < 85 }.count, color: .orange),
                                    (label: "Critical >85%", count: activeDevices.filter { ($0.metrics?.memory.usagePercent ?? 0) >= 85 }.count, color: .red)
                                ],
                                total: activeDevices.count
                            )
                            if !highMemoryDevices.isEmpty {
                                TopDevicesList(title: "High Memory Usage", devices: Array(highMemoryDevices.prefix(5)),
                                              value: { String(format: "%.1f%%", $0.metrics?.memory.usagePercent ?? 0) },
                                              color: .orange)
                            }
                        }
                    }

                    // ── Battery Status ────────────────────────────
                    SectionCard(title: "Battery Status", icon: "battery.75") {
                        VStack(spacing: 8) {
                            DistributionBar(
                                segments: [
                                    (label: "Good >50%",   count: activeDevices.filter { ($0.metrics?.battery.percent ?? 0) > 50 }.count,  color: .green),
                                    (label: "Low 20-50%",  count: activeDevices.filter { let v = $0.metrics?.battery.percent ?? 0; return v >= 20 && v <= 50 }.count, color: .orange),
                                    (label: "Critical <20%", count: activeDevices.filter { ($0.metrics?.battery.percent ?? 0) < 20 }.count, color: .red)
                                ],
                                total: activeDevices.count
                            )
                            if !lowBatteryDevices.isEmpty {
                                TopDevicesList(title: "Critical Battery (<20%)", devices: Array(lowBatteryDevices.prefix(5)),
                                              value: { String(format: "%.0f%%", $0.metrics?.battery.percent ?? 0) },
                                              color: .red)
                            }
                        }
                    }

                    // ── Disk Status ───────────────────────────────
                    SectionCard(title: "Disk Usage", icon: "internaldrive") {
                        VStack(spacing: 8) {
                            let diskDevices = activeDevices.filter { $0.metrics?.disk != nil }
                            if diskDevices.isEmpty {
                                Text("No disk data yet").foregroundColor(.secondary).font(.caption)
                            } else {
                                DistributionBar(
                                    segments: [
                                        (label: "OK <70%",    count: diskDevices.filter { ($0.metrics?.disk?.usagePercent ?? 0) < 70 }.count,  color: .green),
                                        (label: "Warn 70-85%", count: diskDevices.filter { let v = $0.metrics?.disk?.usagePercent ?? 0; return v >= 70 && v < 85 }.count, color: .orange),
                                        (label: "Full >85%",  count: diskDevices.filter { ($0.metrics?.disk?.usagePercent ?? 0) >= 85 }.count,  color: .red)
                                    ],
                                    total: diskDevices.count
                                )
                                if !highDiskDevices.isEmpty {
                                    TopDevicesList(title: "Low Disk Space", devices: Array(highDiskDevices.prefix(5)),
                                                  value: { String(format: "%.1f%%", $0.metrics?.disk?.usagePercent ?? 0) },
                                                  color: .orange)
                                }
                            }
                        }
                    }

                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 40)).foregroundColor(.secondary)
                        Text("No devices reporting yet").foregroundColor(.secondary)
                        Text("Deploy the agent via JAMF to see fleet overview")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(60)
                }
            }
            .padding()
        }
    }

    func gaugeColor(_ v: Double, warn: Double, crit: Double) -> Color {
        v < warn ? .green : v < crit ? .orange : .red
    }
    func batColor(_ v: Double) -> Color { v > 50 ? .green : v > 20 ? .orange : .red }
}

// MARK: - Fleet Stat Card
struct FleetStatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title2).foregroundColor(color)
            Text(value).font(.system(size: 28, weight: .bold)).foregroundColor(color)
            Text(label).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.08))
        .cornerRadius(12)
    }
}

// MARK: - Gauge Card
struct GaugeCard: View {
    let title: String
    let value: Double
    let color: Color
    let unit: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title).font(.caption).foregroundColor(.secondary)
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: min(value / 100, 1.0))
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: value)
                VStack(spacing: 2) {
                    Text(String(format: "%.0f", value))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(color)
                    Text(unit).font(.caption2).foregroundColor(.secondary)
                }
            }
            .frame(width: 90, height: 90)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.06))
        .cornerRadius(12)
    }
}

// MARK: - Distribution Bar
struct DistributionBar: View {
    let segments: [(label: String, count: Int, color: Color)]
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(segments.indices, id: \.self) { i in
                        let seg = segments[i]
                        if seg.count > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(seg.color)
                                .frame(width: total > 0 ? geo.size.width * CGFloat(seg.count) / CGFloat(total) : 0)
                        }
                    }
                }
            }
            .frame(height: 18)
            // Legend
            HStack(spacing: 16) {
                ForEach(segments.indices, id: \.self) { i in
                    let seg = segments[i]
                    HStack(spacing: 4) {
                        Circle().fill(seg.color).frame(width: 8, height: 8)
                        Text("\(seg.label): \(seg.count)")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Top Devices List
struct TopDevicesList: View {
    let title: String
    let devices: [JAMFDevice]
    let value: (JAMFDevice) -> String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary).padding(.top, 4)
            ForEach(devices) { device in
                HStack {
                    Image(systemName: "desktopcomputer").foregroundColor(color).frame(width: 16)
                    Text(device.name).font(.system(size: 12)).lineLimit(1)
                    Spacer()
                    Text(value(device))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(color)
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

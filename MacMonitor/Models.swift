import Foundation

struct JAMFDevice: Identifiable, Codable, Hashable {
    let id: Int
    var name: String
    var serialNumber: String
    var username: String?
    var lastSeen: Date?
    var metrics: DeviceMetrics?
    var osVersion: String?
    var model: String?
    var managed: Bool?
    var ipAddress: String?

    init(id: Int, name: String, serialNumber: String, username: String? = nil,
         lastSeen: Date? = nil, metrics: DeviceMetrics? = nil,
         osVersion: String? = nil, model: String? = nil,
         managed: Bool? = nil, ipAddress: String? = nil) {
        self.id = id; self.name = name; self.serialNumber = serialNumber
        self.username = username; self.lastSeen = lastSeen; self.metrics = metrics
        self.osVersion = osVersion; self.model = model
        self.managed = managed; self.ipAddress = ipAddress
    }

    static func == (lhs: JAMFDevice, rhs: JAMFDevice) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    enum CodingKeys: String, CodingKey {
        case id, name
        case serialNumber = "serial_number"
        case username
    }
}

struct JAMFDeviceListResponse: Codable { let results: [JAMFDeviceResult] }
struct JAMFDeviceResult: Codable {
    let id: Int
    let name: String
    let serialNumber: String?
    let userAndLocation: UserAndLocation?
}
struct UserAndLocation: Codable { let username: String? }

struct DeviceMetrics: Codable, Hashable {
    let serialNumber: String
    let hostname: String
    let timestamp: Date
    let cpu: CPUMetrics
    let memory: MemoryMetrics
    let battery: BatteryMetrics
    let network: NetworkMetrics
    let disk: DiskMetrics?
    let uptime: Double
    let apps: [AppMetrics]
    let topCPUApps: [AppMetrics]?
    let ipAddress: String?

    var id: String { serialNumber }
    static func == (lhs: DeviceMetrics, rhs: DeviceMetrics) -> Bool {
        lhs.serialNumber == rhs.serialNumber && lhs.timestamp == rhs.timestamp
    }
    func hash(into hasher: inout Hasher) { hasher.combine(serialNumber) }
}

struct CPUMetrics: Codable, Hashable {
    let totalUsagePercent: Double
    let coreCount: Int
    let loadAverage1m: Double
    let loadAverage5m: Double
    let loadAverage15m: Double
}

// pressure is optional — older agents don't send it
struct MemoryMetrics: Codable, Hashable {
    let totalGB: Double
    let usedGB: Double
    let availableGB: Double
    let usagePercent: Double
    let pressure: String?
}

struct BatteryMetrics: Codable, Hashable {
    let percent: Double
    let isCharging: Bool
    let isPluggedIn: Bool
    let cycleCount: Int?
    let health: String?
}

struct NetworkMetrics: Codable, Hashable {
    let bytesSentMB: Double
    let bytesReceivedMB: Double
    let interface: String
    let sentRateKBs: Double?
    let recvRateKBs: Double?
}

struct DiskMetrics: Codable, Hashable {
    let totalGB: Double
    let usedGB: Double
    let freeGB: Double
    let usagePercent: Double
    let mountPoint: String
}

struct AppMetrics: Codable, Hashable {
    let pid: Int
    let name: String
    let cpuPercent: Double
    let memoryMB: Double
    let status: String
    let isUserApp: Bool?

    var id: String { "\(pid)" }
    static func == (lhs: AppMetrics, rhs: AppMetrics) -> Bool { lhs.pid == rhs.pid }
    func hash(into hasher: inout Hasher) { hasher.combine(pid) }
}

struct JAMFTokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

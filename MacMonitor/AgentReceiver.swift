import Foundation
import Darwin

class AgentReceiver: ObservableObject {
    @Published var isRunning = false
    @Published var lastError: String?
    @Published var receivedCount = 0

    let port: UInt16 = 9876
    var onMetricsReceived: ((DeviceMetrics) -> Void)?

    private var serverFD: Int32 = -1
    private var shouldRun = false
    private let queue = DispatchQueue(label: "com.macmonitor.server", qos: .userInitiated)

    func start() {
        guard !isRunning else { return }
        shouldRun = true

        queue.async { [weak self] in
            guard let self else { return }

            // Create socket
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else {
                self.fail("socket() failed: \(String(cString: strerror(errno)))")
                return
            }
            self.serverFD = fd

            // Allow reuse
            var yes: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, 4)

            // Bind
            var addr = sockaddr_in()
            memset(&addr, 0, MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = self.port.bigEndian
            addr.sin_addr.s_addr = INADDR_ANY

            let bound = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bound == 0 else {
                self.fail("bind() failed: \(String(cString: strerror(errno)))")
                return
            }

            // Listen
            guard listen(fd, 5) == 0 else {
                self.fail("listen() failed: \(String(cString: strerror(errno)))")
                return
            }

            DispatchQueue.main.async { self.isRunning = true }
            print("[Receiver] ✅ Listening on port \(self.port)")

            // Accept loop
            while self.shouldRun {
                var clientAddr = sockaddr_in()
                var len = socklen_t(MemoryLayout<sockaddr_in>.size)
                let clientFD = withUnsafeMutablePointer(to: &clientAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        accept(fd, $0, &len)
                    }
                }
                guard clientFD >= 0 else { continue }
                DispatchQueue.global().async { [weak self] in
                    self?.handle(clientFD)
                }
            }
        }
    }

    func stop() {
        shouldRun = false
        if serverFD >= 0 { close(serverFD); serverFD = -1 }
        DispatchQueue.main.async { self.isRunning = false }
    }

    private func fail(_ msg: String) {
        print("[Receiver] ❌ \(msg)")
        DispatchQueue.main.async {
            self.lastError = msg
            self.isRunning = false
        }
    }

    private func handle(_ fd: Int32) {
        defer { close(fd) }

        // Read all incoming data
        var raw = Data()
        var buf = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            raw.append(contentsOf: buf[0..<n])
            // Stop when we have headers + full body
            if let s = String(data: raw, encoding: .utf8), s.contains("\r\n\r\n") {
                let parts = s.components(separatedBy: "\r\n\r\n")
                let headerSection = parts[0]
                var contentLength = 0
                for line in headerSection.components(separatedBy: "\r\n") {
                    if line.lowercased().hasPrefix("content-length:") {
                        contentLength = Int(line.dropFirst(16).trimmingCharacters(in: .whitespaces)) ?? 0
                    }
                }
                let headerBytes = headerSection.utf8.count + 4
                if raw.count >= headerBytes + contentLength { break }
            }
        }

        // Parse HTTP body
        guard let s = String(data: raw, encoding: .utf8),
              s.contains("\r\n\r\n") else {
            respond(fd, 400, "bad request")
            return
        }

        let bodyStr = s.components(separatedBy: "\r\n\r\n").dropFirst().joined(separator: "\r\n\r\n")
        guard let bodyData = bodyStr.data(using: .utf8), !bodyData.isEmpty else {
            respond(fd, 400, "empty body")
            return
        }

        // Decode metrics
        do {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            let metrics = try dec.decode(DeviceMetrics.self, from: bodyData)
            respond(fd, 200, "{\"status\":\"ok\"}")
            DispatchQueue.main.async { [weak self] in
                self?.onMetricsReceived?(metrics)
                self?.receivedCount += 1
                print("[Receiver] ✅ \(metrics.hostname) CPU:\(metrics.cpu.totalUsagePercent)%")
            }
        } catch {
            print("[Receiver] ❌ Decode error: \(error)")
            print("[Receiver] Body: \(bodyStr.prefix(300))")
            respond(fd, 422, "{\"error\":\"parse failed\"}")
        }
    }

    private func respond(_ fd: Int32, _ status: Int, _ body: String) {
        let r = "HTTP/1.1 \(status) OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        r.withCString { ptr in _ = write(fd, ptr, r.utf8.count) }
    }
}

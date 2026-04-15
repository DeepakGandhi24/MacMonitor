import Foundation

@MainActor
class JAMFService: ObservableObject {
    @Published var devices: [JAMFDevice] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    private var accessToken: String?
    private var tokenExpiry: Date?

    // MARK: - OAuth2 Token
    func fetchToken(baseURL: String, clientID: String, clientSecret: String) async throws -> String {
        if let t = accessToken, let e = tokenExpiry, e > Date() { return t }
        guard let url = URL(string: "\(baseURL)/api/oauth/token") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "grant_type=client_credentials&client_id=\(clientID)&client_secret=\(clientSecret)".data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "JAMFAuth", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "OAuth2 failed"])
        }
        let tr = try JSONDecoder().decode(JAMFTokenResponse.self, from: data)
        accessToken = tr.accessToken
        tokenExpiry = Date().addingTimeInterval(TimeInterval(tr.expiresIn - 60))
        return tr.accessToken
    }

    // MARK: - Fetch devices — names only, instant
    func fetchDevices(baseURL: String, clientID: String, clientSecret: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Preserve existing metrics across reload
        let existingMetrics = Dictionary(uniqueKeysWithValues:
            devices.compactMap { d -> (String, (DeviceMetrics, Date?))? in
                guard let m = d.metrics else { return nil }
                return (d.name.lowercased(), (m, d.lastSeen))
            }
        )

        do {
            let token = try await fetchToken(baseURL: baseURL, clientID: clientID, clientSecret: clientSecret)

            if let devs = try? await fetchModernAPI(baseURL: baseURL, token: token), !devs.isEmpty {
                devices = devs.map { d in
                    var dev = d
                    if let saved = existingMetrics[d.name.lowercased()] {
                        dev.metrics = saved.0
                        dev.lastSeen = saved.1
                    }
                    return dev
                }
            } else {
                guard let url = URL(string: "\(baseURL)/JSSResource/computers") else { return }
                var req = URLRequest(url: url)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, _) = try await URLSession.shared.data(for: req)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let computers = json["computers"] as? [[String: Any]] else { return }

                devices = computers.compactMap { c -> JAMFDevice? in
                    guard let id = c["id"] as? Int,
                          let name = c["name"] as? String else { return nil }
                    let saved = existingMetrics[name.lowercased()]
                    return JAMFDevice(
                        id: id, name: name, serialNumber: "—",
                        username: nil,
                        lastSeen: saved?.1,
                        metrics: saved?.0
                    )
                }.sorted { $0.name < $1.name }
            }

            print("[JAMF] Loaded \(devices.count) devices — \(devices.filter { $0.metrics != nil }.count) with metrics")

        } catch {
            errorMessage = error.localizedDescription
            print("[JAMF] Error: \(error)")
        }
    }

    // MARK: - Modern API
    private func fetchModernAPI(baseURL: String, token: String) async throws -> [JAMFDevice] {
        guard let url = URL(string: "\(baseURL)/api/v1/computers-preview?page=0&page-size=200") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        let items = json["results"] as? [[String: Any]]
                 ?? json["content"] as? [[String: Any]]
                 ?? []
        return items.compactMap { item in
            guard let id = item["id"] as? Int,
                  let name = item["name"] as? String else { return nil }
            return JAMFDevice(
                id: id, name: name,
                serialNumber: item["serialNumber"] as? String ?? "—",
                username: (item["userAndLocation"] as? [String: Any])?["username"] as? String
            )
        }
    }

    // MARK: - Update metrics from agent
    @MainActor
    func updateMetrics(_ metrics: DeviceMetrics) {
        if let idx = devices.firstIndex(where: {
            $0.serialNumber.lowercased() == metrics.serialNumber.lowercased() ||
            $0.name.lowercased() == metrics.hostname.lowercased() ||
            $0.name.lowercased().hasPrefix(metrics.hostname.lowercased()) ||
            metrics.hostname.lowercased().hasPrefix($0.name.lowercased())
        }) {
            devices[idx].metrics = metrics
            devices[idx].lastSeen = metrics.timestamp
            // Update serial from agent if missing
            if ["—", "Unknown", "Pending", "Fetching...", ""].contains(devices[idx].serialNumber) {
                devices[idx].serialNumber = metrics.serialNumber
            }
        } else {
            // Not found in JAMF — add as new device
            devices.append(JAMFDevice(
                id: abs(metrics.hostname.hashValue),
                name: metrics.hostname,
                serialNumber: metrics.serialNumber,
                username: nil,
                lastSeen: metrics.timestamp,
                metrics: metrics
            ))
        }
        objectWillChange.send()
    }
}

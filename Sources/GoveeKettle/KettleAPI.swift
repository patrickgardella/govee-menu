import Foundation

/// Govee Cloud API client. Port of the Rust `query_state` / `send_command` logic.
struct KettleAPI {

    struct Config: Codable {
        var apiKey: String
        var deviceId: String
        var sku: String
    }

    enum APIError: Error, LocalizedError {
        case missingEnv(String)
        case httpStatus(Int, String)
        case network(String)

        var errorDescription: String? {
            switch self {
            case .missingEnv(let v): return "\(v) not set. Check .env."
            case .httpStatus(let code, let body): return "API error \(code): \(body)"
            case .network(let msg): return "Network error: \(msg)"
            }
        }
    }

    private let config: Config
    private let session: URLSession
    private let base = "https://openapi.api.govee.com"

    init(config: Config, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// Load config from the environment, falling back to a `.env` file next to the running binary.
    static func loadConfig(env: [String: String] = ProcessInfo.processInfo.environment) -> Result<Config, APIError> {
        let envLoader = EnvLoader()
        let merged = envLoader.load()

        guard let apiKey = merged["GOVEE_API_KEY"], !apiKey.isEmpty else {
            return .failure(.missingEnv("GOVEE_API_KEY"))
        }
        guard let deviceId = merged["GOVEE_DEVICE_ID"], !deviceId.isEmpty else {
            return .failure(.missingEnv("GOVEE_DEVICE_ID"))
        }
        let sku = merged["GOVEE_SKU"] ?? "H7173"

        return .success(Config(apiKey: apiKey, deviceId: deviceId, sku: sku))
    }

    private func envelope(_ payload: [String: Any]) -> [String: Any] {
        [
            "requestId": UUID().uuidString.lowercased(),
            "payload": payload,
        ]
    }

    private func post(_ path: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: "\(base)\(path)") else {
            throw APIError.network("bad URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "Govee-API-Key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.network("no HTTP response")
            }
            guard (200..<300).contains(http.statusCode) else {
                let bodyString = String(data: data, encoding: .utf8) ?? ""
                throw APIError.httpStatus(http.statusCode, bodyString)
            }
            return data
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    private func devicePayload(_ capability: [String: Any]) -> [String: Any] {
        [
            "sku": config.sku,
            "device": config.deviceId,
            "capability": capability,
        ]
    }

    /// Fetch current device state.
    func fetchState() async throws -> KettleState {
        let body = envelope([
            "sku": config.sku,
            "device": config.deviceId,
        ])
        let data = try await post("/router/api/v1/device/state", body: body)
        return try KettleParser.parse(data)
    }

    /// Toggle power. If on, turns off; if off, turns on.
    func togglePower() async throws {
        let state = try await fetchState()
        let isOn = state.powerOn ?? false
        try await send(onOff: isOn ? 0 : 1)
    }

    /// Turn on and heat to the given temperature (°F). Valid range 104–212.
    func heat(to temp: Int) async throws {
        guard let validated = KettleLogic.validatedHeatTemp(temp) else {
            throw APIError.network("Temperature must be 104-212°F, got \(temp)")
        }
        try await send(onOff: 1)
        try await send(temperature: validated)
    }

    private func send(onOff value: Int) async throws {
        let capability: [String: Any] = [
            "type": "devices.capabilities.on_off",
            "instance": "powerSwitch",
            "value": value,
        ]
        _ = try await post("/router/api/v1/device/control", body: envelope(devicePayload(capability)))
    }

    private func send(temperature temp: Int) async throws {
        let capability: [String: Any] = [
            "type": "devices.capabilities.temperature_setting",
            "instance": "sliderTemperature",
            "value": [
                "temperature": temp,
                "unit": "Fahrenheit",
            ],
        ]
        _ = try await post("/router/api/v1/device/control", body: envelope(devicePayload(capability)))
    }
}

/// Minimal `.env` loader. Checks the running executable's directory, then the CWD.
private final class EnvLoader {

    func load() -> [String: String] {
        var result = ProcessInfo.processInfo.environment

        var candidates: [URL] = []
        let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        candidates.append(exe.deletingLastPathComponent().appendingPathComponent(".env"))
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env"))

        for url in candidates {
            if let contents = try? String(contentsOf: url, encoding: .utf8) {
                for line in contents.split(separator: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                    let parts = trimmed.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let value = String(parts[1])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    result[key] = value
                }
                break
            }
        }

        return result
    }
}

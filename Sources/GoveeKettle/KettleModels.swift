import Foundation

/// Parsed Govee kettle device state.
struct KettleState {
    var currentTemp: Double?      // °F
    var targetTemp: Double?       // °F
    var powerOn: Bool?
    var mode: String?
}

/// Computed status for display.
enum KettleStatus {
    case off
    case heating
    case done

    var icon: String {
        switch self {
        case .off: return "⏻"
        case .heating: return "🔥"
        case .done: return "✓"
        }
    }

    var label: String {
        switch self {
        case .off: return "Off"
        case .heating: return "Heating"
        case .done: return "Reached target"
        }
    }

    var waybarClass: String {
        switch self {
        case .off: return "kettle-off"
        case .heating: return "kettle-heating"
        case .done: return "kettle-done"
        }
    }
}

enum KettleLogic {

    /// Map Govee work-mode code to a human label.
    static func modeName(_ code: Int) -> String {
        switch code {
        case 1: return "Tea"
        case 2: return "Coffee"
        case 3: return "DIY"
        case 4: return "Boil"
        default: return "Unknown"
        }
    }

    /// Derive display status from parsed state.
    static func status(from state: KettleState) -> KettleStatus {
        let isOn = state.powerOn ?? false
        guard isOn else { return .off }
        if let current = state.currentTemp, let target = state.targetTemp, current < target {
            return .heating
        }
        return .done
    }

    /// Temperature display string; "N/A" when unknown.
    static func tempString(_ temp: Double?) -> String {
        guard let temp else { return "N/A" }
        return "\(Int(temp))°F"
    }

    /// Validate heat temperature range.
    static func validatedHeatTemp(_ temp: Int) -> Int? {
        (104...212).contains(temp) ? temp : nil
    }

    /// Steep temps (°F) for common tea types.
    static let teaPresets: [(name: String, tempF: Int)] = [
        ("Green Tea", 175),
        ("Black Tea", 200),
        ("Herbal Infusion", 212),
    ]
}

/// Estimates water volume from how fast the kettle heats.
///
/// P = m·c·ΔT/t  =>  m = P·t / (c·ΔT). Wattage isn't exposed by the Govee API,
/// so it's a fixed assumed constant, calibrated against two real boils on this
/// kettle (500mL and 1000mL fills landed within ~5-10% using ~1280W). Good for
/// a rough "about how full" indicator, not a precise measurement.
enum WaterMassEstimator {
    static let assumedWattage = 1280.0
    static let specificHeatJPerGramC = 4.186

    /// Below this ΔT, sensor/timing noise dominates and the estimate isn't trustworthy.
    static let minDeltaTempF = 15.0

    /// Grams of water (~= mL) heated from `startTempF`/`startDate` to `endTempF`/`endDate`.
    static func estimateGrams(startTempF: Double, startDate: Date, endTempF: Double, endDate: Date) -> Double? {
        let deltaTempF = endTempF - startTempF
        guard deltaTempF >= minDeltaTempF else { return nil }
        let deltaSeconds = endDate.timeIntervalSince(startDate)
        guard deltaSeconds > 0 else { return nil }
        let deltaC = deltaTempF * 5.0 / 9.0
        let energyJoules = assumedWattage * deltaSeconds
        return energyJoules / (specificHeatJPerGramC * deltaC)
    }
}

/// JSON response envelope from the Govee API.
private struct KettleResponse: Decodable {
    let payload: Payload?

    struct Payload: Decodable {
        let capabilities: [Capability]?
    }

    struct Capability: Decodable {
        let type: String?
        let instance: String?
        let state: CapabilityState?
    }

    struct CapabilityState: Decodable {
        let value: Value
    }

    /// A value that may be a number, bool, or nested object.
    enum Value: Decodable {
        case number(Double)
        case bool(Bool)
        case object([String: Value])
        case null

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() {
                self = .null
            } else if let b = try? c.decode(Bool.self) {
                self = .bool(b)
            } else if let n = try? c.decode(Double.self) {
                self = .number(n)
            } else if let o = try? c.decode([String: Value].self) {
                self = .object(o)
            } else {
                self = .null
            }
        }

        var number: Double? {
            if case .number(let n) = self { return n }
            return nil
        }
        var bool: Bool? {
            if case .bool(let b) = self { return b }
            return nil
        }
        var object: [String: Value]? {
            if case .object(let o) = self { return o }
            return nil
        }
    }
}

/// Extracts a KettleState from a raw Govee state response.
/// Mirrors the Rust `extract_state_data` parser.
enum KettleParser {

    static func parse(_ data: Data) throws -> KettleState {
        let response = try JSONDecoder().decode(KettleResponse.self, from: data)
        guard let capabilities = response.payload?.capabilities else {
            return KettleState()
        }

        var currentTemp: Double?
        var targetTemp: Double?
        var powerOn: Bool?
        var mode: Int?

        for cap in capabilities {
            guard let type = cap.type, let instance = cap.instance else { continue }
            let value = cap.state?.value

            switch (type, instance) {
            case ("devices.capabilities.on_off", "powerSwitch"):
                powerOn = value?.bool ?? value?.number.map { $0 != 0 }
            case ("devices.capabilities.temperature_setting", "sliderTemperature"):
                targetTemp = value?.object?["targetTemperature"]?.number
            case ("devices.capabilities.property", "sensorTemperature"):
                currentTemp = value?.number
            case ("devices.capabilities.work_mode", "workMode"):
                mode = Int(value?.object?["workMode"]?.number ?? 0)
            default:
                break
            }
        }

        return KettleState(
            currentTemp: currentTemp,
            targetTemp: targetTemp,
            powerOn: powerOn,
            mode: mode.map(KettleLogic.modeName)
        )
    }
}

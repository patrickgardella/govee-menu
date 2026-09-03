#!/usr/bin/env swift
import Foundation
//
// PROTOTYPE — throwaway. Not part of the app build (Package.swift doesn't reference it).
// Run: swift Scripts/water_mass_prototype.swift
//
// QUESTION this answers:
// Can we estimate how much water is in the kettle by timing how long it takes
// the sensor temp to rise by some ΔT, using P = m·c·ΔT/t  =>  m = P·t / (c·ΔT)?
// P (wattage) is *assumed*, not read from the device — Govee doesn't expose it.
// This prototype lets you feed in real timed temp readings (either typed by
// hand while watching the Govee app, or from a captured poll log) and see
// whether the resulting mass/volume estimate is in a sane ballpark, and how
// sensitive it is to the assumed wattage and to sample spacing/noise.

// ============================================================
// PURE LOGIC — lift this into KettleModels.swift if validated.
// No I/O, no printing, no terminal code below this block.
// ============================================================

struct WaterSample {
    let elapsedSeconds: Double // seconds since first sample
    let tempF: Double
}

struct WaterMassState {
    var samples: [WaterSample] = []
    var assumedWattage: Double = 1200 // typical electric kettle, adjustable
}

enum WaterMassLogic {
    static let specificHeatJPerGramC = 4.186
    static let densityGPerML = 1.0 // near-boiling water is ~0.96 g/mL; ignored for this estimate

    static func addSample(_ state: WaterMassState, elapsedSeconds: Double, tempF: Double) -> WaterMassState {
        var next = state
        next.samples.append(WaterSample(elapsedSeconds: elapsedSeconds, tempF: tempF))
        return next
    }

    static func setWattage(_ state: WaterMassState, watts: Double) -> WaterMassState {
        var next = state
        next.assumedWattage = watts
        return next
    }

    static func reset(_ state: WaterMassState) -> WaterMassState {
        WaterMassState(assumedWattage: state.assumedWattage)
    }

    struct Estimate {
        let deltaTempF: Double
        let elapsedSeconds: Double
        let massGrams: Double
        let volumeML: Double
    }

    /// Estimate from the first sample to the latest sample.
    static func estimate(_ state: WaterMassState) -> Estimate? {
        guard let first = state.samples.first, let last = state.samples.last, last.elapsedSeconds > first.elapsedSeconds else {
            return nil
        }
        let deltaTempF = last.tempF - first.tempF
        guard deltaTempF > 0 else { return nil }
        let deltaSeconds = last.elapsedSeconds - first.elapsedSeconds
        let deltaC = deltaTempF * 5.0 / 9.0

        let energyJoules = state.assumedWattage * deltaSeconds
        let massGrams = energyJoules / (specificHeatJPerGramC * deltaC)
        let volumeML = massGrams / densityGPerML

        return Estimate(deltaTempF: deltaTempF, elapsedSeconds: deltaSeconds, massGrams: massGrams, volumeML: volumeML)
    }
}

// ============================================================
// TUI SHELL — throwaway, drives the logic above by hand.
// ============================================================

func clearScreen() {
    print("\u{1B}[2J\u{1B}[H", terminator: "")
}

func bold(_ s: String) -> String { "\u{1B}[1m\(s)\u{1B}[0m" }
func dim(_ s: String) -> String { "\u{1B}[2m\(s)\u{1B}[0m" }

func render(_ state: WaterMassState) {
    clearScreen()
    print(bold("Water Mass Estimator — prototype"))
    print(dim("m = P·t / (c·ΔT), assumes constant wattage, no heat loss"))
    print("")
    print(bold("Assumed wattage: ") + "\(Int(state.assumedWattage)) W")
    print(bold("Samples:"))
    if state.samples.isEmpty {
        print(dim("  (none yet — add a starting reading with [t])"))
    } else {
        for s in state.samples {
            print("  t=\(dim(String(format: "%.0fs", s.elapsedSeconds)))  temp=\(String(format: "%.1f", s.tempF))°F")
        }
    }
    print("")
    if let est = WaterMassLogic.estimate(state) {
        print(bold("Estimate (first → last sample):"))
        print("  ΔT: \(String(format: "%.1f", est.deltaTempF))°F over \(String(format: "%.0f", est.elapsedSeconds))s")
        print("  " + bold("Mass: ") + String(format: "%.0f g", est.massGrams))
        let cups = est.volumeML / 236.6
        print("  " + bold("Volume: ") + String(format: "%.0f mL", est.volumeML) + " (\(String(format: "%.2f", cups)) cups)")
    } else {
        print(dim("Need ≥2 samples with rising temp for an estimate."))
    }
    print("")
    print(bold("[t]") + dim(" add timed reading  ") +
          bold("[w]") + dim(" set assumed wattage  ") +
          bold("[r]") + dim(" reset  ") +
          bold("[q]") + dim(" quit"))
    print("> ", terminator: "")
}

func promptDouble(_ label: String) -> Double? {
    print(label, terminator: "")
    guard let line = readLine(), let value = Double(line.trimmingCharacters(in: .whitespaces)) else { return nil }
    return value
}

var state = WaterMassState()
render(state)

while let line = readLine() {
    switch line.trimmingCharacters(in: .whitespaces).lowercased() {
    case "t":
        if let secs = promptDouble("  elapsed seconds since first reading: "),
           let temp = promptDouble("  current temp (°F): ") {
            state = WaterMassLogic.addSample(state, elapsedSeconds: secs, tempF: temp)
        }
    case "w":
        if let watts = promptDouble("  assumed wattage: ") {
            state = WaterMassLogic.setWattage(state, watts: watts)
        }
    case "r":
        state = WaterMassLogic.reset(state)
    case "q":
        exit(0)
    default:
        break
    }
    render(state)
}

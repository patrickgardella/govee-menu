import AppKit
import Foundation

/// Owns the menu bar status item and polling timer.
final class MenuBarController: NSObject, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private let api: KettleAPI

    private var currentState: KettleState?
    private var savedTarget: Int = 200

    // Water-level estimate: tracked from the moment a heat is requested
    // until the target temp is reached.
    private var heatStartDate: Date?
    private var heatStartTemp: Double?
    private var estimatedWaterGrams: Double?

    init(api: KettleAPI) {
        self.api = api
        super.init()
    }

    func start() {
        installStatusItem()
        refresh()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "…"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    // MARK: - Polling

    func refresh() {
        Task {
            do {
                let state = try await api.fetchState()
                currentState = state
                await MainActor.run { self.updateUI() }
            } catch {
                if let error = error as? KettleAPI.APIError {
                    await MainActor.run { self.showError(error.localizedDescription) }
                }
            }
        }
    }

    private func updateUI() {
        guard let state = currentState, let button = statusItem?.button else { return }

        let status = KettleLogic.status(from: state)
        button.title = "\(status.icon) \(KettleLogic.tempString(state.currentTemp))"

        if let target = state.targetTemp {
            savedTarget = Int(target)
        }

        checkWaterEstimate(status: status, state: state)
    }

    /// Once a requested heat reaches its target, estimate water volume from
    /// how long it took to get there. One-shot per heat request.
    private func checkWaterEstimate(status: KettleStatus, state: KettleState) {
        guard let startDate = heatStartDate, let startTemp = heatStartTemp else { return }

        guard status == .done || state.powerOn == false, let currentTemp = state.currentTemp else { return }

        estimatedWaterGrams = WaterMassEstimator.estimateGrams(
            startTempF: startTemp,
            startDate: startDate,
            endTempF: currentTemp,
            endDate: Date()
        )
        heatStartDate = nil
        heatStartTemp = nil
    }

    private func showError(_ message: String) {
        statusItem?.button?.title = "⚠︎"
        statusItem?.button?.toolTip = message
    }

    // MARK: - Actions

    func toggle() {
        heatStartDate = nil
        heatStartTemp = nil

        Task {
            do {
                try await api.togglePower()
                refresh()
            } catch {
                await MainActor.run { self.showError((error as? KettleAPI.APIError)?.localizedDescription ?? "toggle failed") }
            }
        }
    }

    func heat(_ temp: Int) {
        heatStartDate = Date()
        heatStartTemp = currentState?.currentTemp
        estimatedWaterGrams = nil

        Task {
            do {
                try await api.heat(to: temp)
                refresh()
            } catch {
                await MainActor.run { self.showError((error as? KettleAPI.APIError)?.localizedDescription ?? "heat failed") }
            }
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = currentState.map(KettleLogic.status) ?? .off
        let temp = currentState.flatMap { $0.currentTemp }.map(KettleLogic.tempString) ?? "N/A"
        let target = currentState.flatMap { $0.targetTemp }.map(KettleLogic.tempString) ?? "N/A"
        let mode = currentState?.mode ?? "Unknown"

        menu.addItem(NSMenuItem(title: "Kettle: \(temp) — \(status.label)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Target: \(target)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Mode: \(mode)", action: nil, keyEquivalent: ""))
        if let grams = estimatedWaterGrams {
            menu.addItem(NSMenuItem(title: "Est. water: ~\(Int(grams))mL", action: nil, keyEquivalent: ""))
        } else if heatStartDate != nil {
            menu.addItem(NSMenuItem(title: "Est. water: measuring…", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())

        let toggleItem = NSMenuItem(title: status == .off ? "Turn On" : "Turn Off", action: #selector(toggleTapped), keyEquivalent: "t")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let heatMenu = NSMenu(title: "Heat To")
        for (name, tempValue) in KettleLogic.teaPresets {
            let item = NSMenuItem(title: "\(name) (\(tempValue)°F)", action: #selector(heatTapped(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = tempValue
            heatMenu.addItem(item)
        }
        let heatItem = NSMenuItem(title: "Heat To", action: nil, keyEquivalent: "")
        menu.setSubmenu(heatMenu, for: heatItem)
        menu.addItem(heatItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitTapped), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func toggleTapped() { toggle() }

    @objc private func heatTapped(_ sender: NSMenuItem) {
        if let temp = sender.representedObject as? Int {
            heat(temp)
        }
    }

    @objc private func quitTapped() {
        NSApp.terminate(nil)
    }
}

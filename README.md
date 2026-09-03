# Govee Kettle — macOS Menu Bar

Menu bar utility for the Govee H7173 Smart Kettle. Polls the Govee Cloud API and shows live water temperature with a status glyph in the menu bar; click to control heating, pick a tea preset, and see an estimated water level after a heat completes.

Originally a Swift/AppKit port of a Rust waybar module (same Govee API, same response-parsing fixtures) — has since diverged with kettle-specific features.

## Features

- Menu bar status: `⏻` off, `🔥` heating, `✓` reached target temp
- Live temp in °F, polled every 30s
- Menu shows Kettle / Target / Mode on separate lines
- Toggle power on/off
- Heat to a tea preset: Green Tea (175°F), Black Tea (200°F), Herbal Infusion (212°F)
- Estimated water volume: after a requested heat reaches target, estimates how much water is in the pot from how fast it heated (see below)

## Layout

```
govee-menu/
├── Package.swift
├── .env                          # GOVEE_API_KEY, GOVEE_DEVICE_ID, GOVEE_SKU (gitignored)
├── test-data/                    # state fixtures used by parser tests
├── Sources/GoveeKettle/
│   ├── main.swift                # NSApplication bootstrap (accessory app)
│   ├── MenuBarController.swift   # NSStatusItem + menu + 30s poll timer + water estimate tracking
│   ├── KettleAPI.swift           # URLSession client (Govee Cloud API) + .env loader
│   └── KettleModels.swift        # Codable parsing, status logic, tea presets, water mass estimator
├── Tests/GoveeKettleTests/
│   └── KettleParserTests.swift   # parsing + status + logic tests
├── Scripts/
│   ├── water_mass_prototype.swift # standalone TUI for recalibrating the water estimate (see below)
│   ├── build_app.sh              # builds dist/GoveeKettle.app (release binary + icon + Info.plist)
│   └── icon/                     # kettle.svg (source) → AppIcon.icns (built)
└── dist/                         # build_app.sh output (gitignored, not committed)
```

## Build & test (macOS, Xcode 15+ / Swift 5.9+)

`swift test` needs full Xcode installed (XCTest isn't in Command Line Tools alone) — `sudo xcode-select -s /Applications/Xcode.app` if `swift test` errors with "no such module 'XCTest'".

```sh
swift build
swift test        # parsing + logic tests against test-data fixtures
swift run GoveeKettle
```

## Configuration (.env)

```
GOVEE_API_KEY=<your key>
GOVEE_DEVICE_ID=<MAC>
GOVEE_SKU=H7173
```

Loaded from the executable's directory or CWD. Not committed (gitignored).

## Running as a real app (login item)

```sh
./Scripts/build_app.sh
mv dist/GoveeKettle.app /Applications/
```

Then **System Settings → General → Login Items → +** → pick `GoveeKettle.app`.

`build_app.sh` produces a proper `.app` bundle: release binary, `.env` copied alongside it, `LSUIElement = 1` (no Dock icon, menu bar only), and the kettle `AppIcon.icns`. Re-run the script after code changes and re-copy to `/Applications` to update; the login item keeps pointing at the same path.

The icon source is `Scripts/icon/kettle.svg` — edit it and re-run `Scripts/icon` regeneration (rsvg-convert to PNGs at 16/32/128/256/512 + @2x, then `iconutil -c icns`) if you want to restyle it, then rebuild the app.

## Water volume estimate

Govee doesn't expose kettle wattage or a fill-level sensor, so volume is inferred from the heating curve: `P = m·c·ΔT/t` → `m = P·t / (c·ΔT)`, using a fixed assumed wattage.

- **Calibrated** against two real boils on this specific kettle (500mL and 1000mL fills), cross-validated to within ~5-10% using **1280W** as the assumed constant. See `WaterMassEstimator` in `KettleModels.swift`.
- **Trigger**: only when a "Heat To" preset is tapped — records start time/temp, computes once the kettle reaches target (or powers off mid-heat), shows `Est. water: ~XXXmL` in the menu. Plain toggle-on doesn't track it.
- **Caveat**: this is a rough "about how full" indicator, not a scale-grade measurement — small ΔT windows are noisy (sensor + timing resolution), which is why it only fires over a whole heat cycle rather than short intervals.
- **Recalibrating**: `Scripts/water_mass_prototype.swift` is a standalone throwaway TUI (`swift Scripts/water_mass_prototype.swift`) for feeding in a new timed boil (known water amount + timestamped temp readings) and checking/adjusting the assumed wattage constant before changing it in `KettleModels.swift`.

## API notes

- Base `https://openapi.api.govee.com`, header `Govee-API-Key`
- State: `POST /router/api/v1/device/state`, body envelope `{ requestId, payload: { sku, device } }`
- Control: `POST /router/api/v1/device/control`, body adds `capability`
- Response key is `payload.capabilities` (not `data`)
- Current temp: `devices.capabilities.property` / `sensorTemperature` (float °F)
- Target temp: `temperature_setting` / `sliderTemperature` → `targetTemperature`
- Power: `on_off` / `powerSwitch` (0/1, decoded as a JSON number — not a JSON bool)
- Mode: `work_mode` / `workMode` (1=Tea, 2=Coffee, 3=DIY, 4=Boil)
- Rate limits: 30 state requests/min/device, 120 control requests/min/device

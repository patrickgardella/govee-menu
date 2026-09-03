import XCTest
@testable import GoveeKettle

final class KettleParserTests: XCTestCase {

    private func loadFixture(_ name: String) throws -> Data {
        // Fixtures live at repo root govee-menu/test-data/
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("test-data")
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }

    func testParsesOffCoolingState() throws {
        let state = try KettleParser.parse(loadFixture("state_off_cooling.json"))
        XCTAssertEqual(state.currentTemp, 104.0)
        XCTAssertEqual(state.targetTemp, 212.0)
        XCTAssertEqual(state.powerOn, false)
        XCTAssertEqual(state.mode, "Coffee")
    }

    func testParsesHeatingState() throws {
        let state = try KettleParser.parse(loadFixture("state_heating.json"))
        XCTAssertEqual(state.currentTemp, 150.0)
        XCTAssertEqual(state.targetTemp, 212.0)
        XCTAssertEqual(state.powerOn, true)
        XCTAssertEqual(state.mode, "Boil")
    }

    func testParsesDoneState() throws {
        let state = try KettleParser.parse(loadFixture("state_done.json"))
        XCTAssertEqual(state.currentTemp, 180.0)
        XCTAssertEqual(state.targetTemp, 180.0)
        XCTAssertEqual(state.powerOn, true)
        XCTAssertEqual(state.mode, "Tea")
    }

    func testStatusOffWhenPowerOff() {
        let s = KettleState(currentTemp: 104, targetTemp: 212, powerOn: false, mode: "Coffee")
        XCTAssertEqual(KettleLogic.status(from: s), .off)
        XCTAssertEqual(KettleLogic.status(from: s).icon, "⏻")
    }

    func testStatusHeatingWhenBelowTarget() {
        let s = KettleState(currentTemp: 150, targetTemp: 212, powerOn: true, mode: "Boil")
        XCTAssertEqual(KettleLogic.status(from: s), .heating)
        XCTAssertEqual(KettleLogic.status(from: s).icon, "🔥")
    }

    func testStatusDoneWhenAtTarget() {
        let s = KettleState(currentTemp: 180, targetTemp: 180, powerOn: true, mode: "Tea")
        XCTAssertEqual(KettleLogic.status(from: s), .done)
        XCTAssertEqual(KettleLogic.status(from: s).icon, "✓")
    }

    func testTempStringNAWhenMissing() {
        XCTAssertEqual(KettleLogic.tempString(nil), "N/A")
    }

    func testHeatBoundaryValidation() {
        XCTAssertNil(KettleLogic.validatedHeatTemp(103))
        XCTAssertEqual(KettleLogic.validatedHeatTemp(104), 104)
        XCTAssertEqual(KettleLogic.validatedHeatTemp(212), 212)
        XCTAssertNil(KettleLogic.validatedHeatTemp(213))
    }

    func testModeNameMapping() {
        XCTAssertEqual(KettleLogic.modeName(1), "Tea")
        XCTAssertEqual(KettleLogic.modeName(2), "Coffee")
        XCTAssertEqual(KettleLogic.modeName(3), "DIY")
        XCTAssertEqual(KettleLogic.modeName(4), "Boil")
        XCTAssertEqual(KettleLogic.modeName(99), "Unknown")
    }
}

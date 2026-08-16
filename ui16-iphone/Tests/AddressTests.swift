import XCTest
@testable import UI16Controller

final class AddressTests: XCTestCase {

    func testChannelRefAddressIsZeroBased() {
        XCTAssertEqual(ChannelRef(.input, 1).address, "i.0")
        XCTAssertEqual(ChannelRef(.input, 12).address, "i.11")
        XCTAssertEqual(ChannelRef(.aux, 3).address, "a.2")
        XCTAssertEqual(ChannelRef(.fx, 1).address, "f.0")
    }

    func testUi16Inventory() {
        // The Ui16 has 12 mono inputs + 2 line + 2 player = 16 input sources (not 16 mono).
        XCTAssertEqual(UI16Model.inputCount, 12)
        XCTAssertEqual(UI16Model.lineCount, 2)
        XCTAssertEqual(UI16Model.playerCount, 2)
        XCTAssertEqual(UI16Model.inputSources.count, 16)
        XCTAssertEqual(UI16Model.fxReturns.count, 4)
        XCTAssertEqual(UI16Model.subGroups.count, 4)
        XCTAssertEqual(UI16Model.auxBuses.count, 6)

        // Surface order: 12 inputs, then 2 lines, then 2 players.
        XCTAssertEqual(UI16Model.inputSources[0].address, "i.0")
        XCTAssertEqual(UI16Model.inputSources[11].address, "i.11")
        XCTAssertEqual(UI16Model.inputSources[12].address, "l.0")
        XCTAssertEqual(UI16Model.inputSources[13].address, "l.1")
        XCTAssertEqual(UI16Model.inputSources[14].address, "p.0")
        XCTAssertEqual(UI16Model.inputSources[15].address, "p.1")
    }

    func testMasterKeys() {
        XCTAssertEqual(MasterAddress.mix, "m.mix")
        XCTAssertEqual(MasterAddress.mute, "m.mute")
        XCTAssertEqual(MasterAddress.pan, "m.pan")
    }

    func testChannelParameterKeys() {
        let ch = ChannelRef(.input, 1)
        XCTAssertEqual(UI16Key.mix(ch), "i.0.mix")
        XCTAssertEqual(UI16Key.mute(ch), "i.0.mute")
        XCTAssertEqual(UI16Key.solo(ch), "i.0.solo")
        XCTAssertEqual(UI16Key.pan(ch), "i.0.pan")
        XCTAssertEqual(UI16Key.gain(ch), "i.0.gain")
        XCTAssertEqual(UI16Key.phantom(ch), "i.0.phantom")
        XCTAssertEqual(UI16Key.name(ch), "i.0.name")
    }

    func testSendKeys() {
        let ch = ChannelRef(.input, 1)
        XCTAssertEqual(UI16Key.sendLevel(ch, to: .aux, 2), "i.0.aux.1.value")
        XCTAssertEqual(UI16Key.sendPost(ch, to: .aux, 2), "i.0.aux.1.post")
        XCTAssertEqual(UI16Key.sendLevel(ch, to: .fx, 1), "i.0.fx.0.value")
    }
}

import XCTest
@testable import ParedaoCore
@testable import UI16Controller

final class EQSettingsTests: XCTestCase {

    func testDefaultIsFiveFlatBands() {
        let eq = EQSettings()
        XCTAssertEqual(eq.bands.count, 5)
        XCTAssertEqual(eq.bands.map(\.name), ["LOW", "LOW MID", "MID", "HIGH MID", "HIGH"])
        XCTAssertTrue(eq.bands.allSatisfy { $0.gain == 0 })
    }

    func testFlatCurveIsZeroEverywhere() {
        let eq = EQSettings()
        for f in [40.0, 200, 1_000, 5_000, 15_000] {
            XCTAssertEqual(eq.responseDB(at: f), 0, accuracy: 0.01)
        }
    }

    func testBoostRaisesResponseNearItsFrequency() {
        var eq = EQSettings()
        eq.setGain(12, forBandAt: 2)          // MID @ 1 kHz
        XCTAssertGreaterThan(eq.responseDB(at: 1_000), 6, "deve subir perto de 1 kHz")
        XCTAssertLessThan(eq.responseDB(at: 60), 3, "não deve afetar muito o grave")
    }

    func testCutLowersResponse() {
        var eq = EQSettings()
        eq.setGain(-12, forBandAt: 2)
        XCTAssertLessThan(eq.responseDB(at: 1_000), -6)
    }

    func testLowShelfAffectsBass() {
        var eq = EQSettings()
        eq.setGain(10, forBandAt: 0)          // LOW shelf @ 80 Hz
        XCTAssertGreaterThan(eq.responseDB(at: 40), 5)
        XCTAssertLessThan(eq.responseDB(at: 10_000), 1)
    }

    func testHighShelfAffectsTreble() {
        var eq = EQSettings()
        eq.setGain(10, forBandAt: 4)          // HIGH shelf @ 10 kHz
        XCTAssertGreaterThan(eq.responseDB(at: 16_000), 5)
        XCTAssertLessThan(eq.responseDB(at: 100), 1)
    }

    func testBandBypassRemovesItsEffect() {
        var eq = EQSettings()
        eq.setGain(12, forBandAt: 2)
        let boosted = eq.responseDB(at: 1_000)
        eq.toggleBypass(bandAt: 2)
        XCTAssertEqual(eq.responseDB(at: 1_000), 0, accuracy: 0.01)
        XCTAssertGreaterThan(boosted, 6)
    }

    func testGlobalBypassFlattensEverything() {
        var eq = EQSettings()
        eq.setGain(12, forBandAt: 0)
        eq.setGain(-8, forBandAt: 3)
        eq.bypassed = true
        XCTAssertEqual(eq.responseDB(at: 80), 0, accuracy: 0.01)
        XCTAssertEqual(eq.responseDB(at: 3_500), 0, accuracy: 0.01)
    }

    func testValuesAreClamped() {
        var eq = EQSettings()
        eq.setGain(999, forBandAt: 0)
        XCTAssertEqual(eq.bands[0].gain, EQBand.gainRange.upperBound)
        eq.setGain(-999, forBandAt: 0)
        XCTAssertEqual(eq.bands[0].gain, EQBand.gainRange.lowerBound)
        eq.setFrequency(999_999, forBandAt: 1)
        XCTAssertEqual(eq.bands[1].frequency, EQBand.freqRange.upperBound)
        eq.setQ(0, forBandAt: 1)
        XCTAssertEqual(eq.bands[1].q, EQBand.qRange.lowerBound)
    }

    func testEditingClearsPresetName() {
        var eq = EQSettings()
        eq.apply(EQPreset.builtIn[1])
        XCTAssertFalse(eq.presetName.isEmpty)
        eq.setGain(3, forBandAt: 0)
        XCTAssertTrue(eq.presetName.isEmpty, "curva editada não é mais o preset")
    }

    func testResetReturnsToFlat() {
        var eq = EQSettings()
        eq.apply(EQPreset.builtIn[2])
        eq.reset()
        XCTAssertTrue(eq.bands.allSatisfy { $0.gain == 0 })
        XCTAssertEqual(eq.preamp, 0)
        XCTAssertEqual(eq.presetName, "FLAT")
    }

    func testPresetsExistAndBoostingOnesCutPreamp() {
        XCTAssertGreaterThan(EQPreset.builtIn.count, 3)
        for preset in EQPreset.builtIn {
            let maxBoost = preset.bands.map(\.gain).max() ?? 0
            if maxBoost >= 6 {
                XCTAssertLessThan(preset.preamp, 0,
                                  "\(preset.name) realça bastante e precisa de preamp negativo para não clipar")
            }
        }
    }

    func testPresetRoundTripsThroughCodable() throws {
        var eq = EQSettings()
        eq.apply(EQPreset.builtIn[1])
        let data = try JSONEncoder().encode(eq)
        let back = try JSONDecoder().decode(EQSettings.self, from: data)
        XCTAssertEqual(back, eq)
    }
}

final class PhaseControlTests: XCTestCase {

    func testPolarityBasics() {
        XCTAssertEqual(PhasePolarity.normal.toggled, .inverted)
        XCTAssertEqual(PhasePolarity.inverted.toggled, .normal)
        XCTAssertEqual(PhasePolarity.inverted.wireValue, 1)
        XCTAssertEqual(PhasePolarity.normal.wireValue, 0)
        XCTAssertTrue(PhasePolarity.inverted.isInverted)
    }

    func testUnconfirmedWhenMixerReportedNoPolarityKey() {
        // The mixer sent plenty of keys, none of them polarity — we must not invent one.
        let keys = ["i.0.mix", "i.0.mute", "i.0.gain", "i.0.eq.high.gain"]
        XCTAssertEqual(PhaseControl.resolve(channelAddress: "i.0", reportedKeys: keys), .unconfirmed)
    }

    func testResolvesRealKeyWhenMixerReportsIt() {
        let keys = ["i.0.mix", "i.0.phase", "i.0.mute"]
        XCTAssertEqual(PhaseControl.resolve(channelAddress: "i.0", reportedKeys: keys),
                       .available(key: "i.0.phase"))
    }

    func testAcceptsAlternativeNamesTheMixerMightUse() {
        XCTAssertEqual(PhaseControl.resolve(channelAddress: "i.3", reportedKeys: ["i.3.polarity"]),
                       .available(key: "i.3.polarity"))
        XCTAssertEqual(PhaseControl.resolve(channelAddress: "i.3", reportedKeys: ["i.3.invert"]),
                       .available(key: "i.3.invert"))
    }

    func testDoesNotMatchOtherChannels() {
        // A polarity key on channel 2 must never be used to drive channel 1.
        let keys = ["i.1.phase"]
        XCTAssertEqual(PhaseControl.resolve(channelAddress: "i.0", reportedKeys: keys), .unconfirmed)
    }

    func testDoesNotMatchNestedKeysThatMerelyContainTheWord() {
        let keys = ["i.0.eq.phase.rotate"]
        XCTAssertEqual(PhaseControl.resolve(channelAddress: "i.0", reportedKeys: keys), .unconfirmed)
    }

    func testAwaitingConfirmationReflectsInFlightWrite() {
        var state = PhaseState()
        state.mixerConfirmed = .normal
        state.mixerPolarity = .inverted
        XCTAssertTrue(state.awaitingConfirmation)
        XCTAssertFalse(state.isSynced)

        state.mixerConfirmed = .inverted
        XCTAssertFalse(state.awaitingConfirmation)
        XCTAssertTrue(state.isSynced)
    }

    func testLocalPolarityIsIndependentOfMixer() {
        var state = PhaseState()
        state.localPolarity = .inverted
        XCTAssertEqual(state.mixerPolarity, .normal,
                       "inverter o player não deve mexer no estado da mesa")
    }
}

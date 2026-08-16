import XCTest
@testable import UI16Controller

final class FaderMathTests: XCTestCase {

    func testFaderTopIsAboutPlusTenDB() {
        XCTAssertEqual(FaderMath.faderValueToDB(1.0), 10.0, accuracy: 0.1)
    }

    func testFaderBottomIsSilence() {
        XCTAssertEqual(FaderMath.faderValueToDB(0.0), -.infinity)
    }

    func testFaderDBFaderRoundTrip() {
        // faderValueToDB quantizes to 0.1 dB, so the position can drift slightly on steep
        // sections of the curve — 0.005 covers that quantization while still catching real bugs.
        for v in stride(from: 0.1, through: 1.0, by: 0.1) {
            let db = FaderMath.faderValueToDB(v)
            let back = FaderMath.dbToFaderValue(db)
            XCTAssertEqual(back, v, accuracy: 5e-3, "roundtrip failed at \(v)")
        }
    }

    func testDBFaderDBRoundTripIsExactToTenthDB() {
        for db in stride(from: -60.0, through: 10.0, by: 2.0) {
            let v = FaderMath.dbToFaderValue(db)
            let back = FaderMath.faderValueToDB(v)
            XCTAssertEqual(back, db, accuracy: 0.1, "dB roundtrip failed at \(db)")
        }
    }

    func testGainMapping() {
        XCTAssertEqual(FaderMath.gainValueToDB(0.0), -40, accuracy: 0.001)
        XCTAssertEqual(FaderMath.gainValueToDB(1.0), 50, accuracy: 0.001)
        XCTAssertEqual(FaderMath.gainValueToDB(0.5), 5, accuracy: 0.001)
        XCTAssertEqual(FaderMath.gainDBToValue(5), 0.5, accuracy: 0.001)
    }

    func testVUMapping() {
        XCTAssertEqual(FaderMath.vuValueToDB(1.0), 0, accuracy: 0.001)
        XCTAssertEqual(FaderMath.vuValueToDB(0.0), -80, accuracy: 0.001)
    }

    func testDBStringFormatting() {
        XCTAssertEqual(FaderMath.dbString(0.0), "-∞")
        XCTAssertTrue(FaderMath.dbString(1.0).contains("dB"))
    }
}

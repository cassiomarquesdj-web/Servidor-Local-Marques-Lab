import XCTest
@testable import UI16Controller

final class CommandThrottleTests: XCTestCase {

    /// Deterministic clock + manual scheduler, so no test depends on wall time.
    private final class Harness {
        var now: TimeInterval = 0
        var scheduled: [(TimeInterval, () -> Void)] = []
        var sent: [String] = []
        let throttle: CommandThrottle

        init(interval: TimeInterval = 0.04) {
            var nowBox: () -> TimeInterval = { 0 }
            var scheduleBox: (TimeInterval, @escaping () -> Void) -> Void = { _, _ in }
            let t = CommandThrottle(
                interval: interval,
                now: { nowBox() },
                schedule: { d, w in scheduleBox(d, w) }
            )
            self.throttle = t
            nowBox = { [unowned self] in self.now }
            scheduleBox = { [unowned self] delay, work in
                self.scheduled.append((self.now + delay, work))
            }
            t.send = { [unowned self] payload in self.sent.append(payload) }
        }

        /// Advance time and run anything that came due.
        func advance(to time: TimeInterval) {
            now = time
            let due = scheduled.filter { $0.0 <= time }
            scheduled.removeAll { $0.0 <= time }
            due.forEach { $0.1() }
        }
    }

    func testFirstWriteGoesOutImmediately() {
        let h = Harness()
        h.throttle.submit(key: "i.0.mix", payload: "SETD^i.0.mix^0.5")
        XCTAssertEqual(h.sent, ["SETD^i.0.mix^0.5"])
    }

    func testRapidWritesAreCoalescedToOneTrailingWrite() {
        let h = Harness(interval: 0.04)
        h.throttle.submit(key: "i.0.mix", payload: "SETD^i.0.mix^0.1")   // sent now
        h.now = 0.01
        h.throttle.submit(key: "i.0.mix", payload: "SETD^i.0.mix^0.2")   // held
        h.now = 0.02
        h.throttle.submit(key: "i.0.mix", payload: "SETD^i.0.mix^0.3")   // held
        h.now = 0.03
        h.throttle.submit(key: "i.0.mix", payload: "SETD^i.0.mix^0.4")   // held

        XCTAssertEqual(h.sent, ["SETD^i.0.mix^0.1"], "only the first write should be out")

        h.advance(to: 0.05)
        // The finger stopped at 0.4 — that exact value must reach the mixer.
        XCTAssertEqual(h.sent, ["SETD^i.0.mix^0.1", "SETD^i.0.mix^0.4"])
    }

    func testDifferentKeysDoNotBlockEachOther() {
        let h = Harness()
        h.throttle.submit(key: "i.0.mix", payload: "A")
        h.throttle.submit(key: "i.1.mix", payload: "B")
        h.throttle.submit(key: "m.mix", payload: "C")
        XCTAssertEqual(h.sent, ["A", "B", "C"])
    }

    func testWritesSpacedBeyondIntervalAllGoOut() {
        let h = Harness(interval: 0.04)
        h.throttle.submit(key: "i.0.mix", payload: "A")
        h.now = 0.05
        h.throttle.submit(key: "i.0.mix", payload: "B")
        h.now = 0.10
        h.throttle.submit(key: "i.0.mix", payload: "C")
        XCTAssertEqual(h.sent, ["A", "B", "C"])
        XCTAssertTrue(h.scheduled.isEmpty, "nothing should be pending")
    }

    /// Regression: a late-firing flush must never overwrite a newer value with a stale one.
    /// Timers can fire behind schedule; if the queued value still went out, the mixer would
    /// end up at a level the operator had already moved away from.
    func testLateFlushNeverSendsStaleValueAfterNewerOne() {
        let h = Harness(interval: 0.04)
        h.throttle.submit(key: "i.0.mix", payload: "v1")        // out immediately
        h.now = 0.01
        h.throttle.submit(key: "i.0.mix", payload: "v2")        // queued, flush due at 0.04

        // The next value arrives after the window, so it is sent directly...
        h.now = 0.05
        h.throttle.submit(key: "i.0.mix", payload: "v3")

        // ...and only now does the delayed flush run.
        h.advance(to: 0.06)

        XCTAssertEqual(h.sent, ["v1", "v3"], "stale v2 must not land after v3")
        XCTAssertEqual(h.sent.last, "v3", "the mixer must end on the newest value")
    }

    func testUnchangedValueIsNotResent() {
        let h = Harness(interval: 0.04)
        h.throttle.submit(key: "i.0.mix", payload: "SETD^i.0.mix^1")
        XCTAssertEqual(h.sent, ["SETD^i.0.mix^1"])

        // Fader held against the ceiling: the same value must not be transmitted again.
        h.now = 0.10
        h.throttle.submit(key: "i.0.mix", payload: "SETD^i.0.mix^1")
        h.now = 0.20
        h.throttle.submit(key: "i.0.mix", payload: "SETD^i.0.mix^1")
        XCTAssertEqual(h.sent, ["SETD^i.0.mix^1"])

        // A genuinely new value still goes out.
        h.now = 0.30
        h.throttle.submit(key: "i.0.mix", payload: "SETD^i.0.mix^0.9")
        XCTAssertEqual(h.sent, ["SETD^i.0.mix^1", "SETD^i.0.mix^0.9"])
    }

    func testSendNowBypassesThrottling() {
        let h = Harness(interval: 0.04)
        h.throttle.submit(key: "i.0.mute", payload: "held")
        h.now = 0.01
        // A mute must never wait behind a throttle window.
        h.throttle.sendNow(key: "i.0.mute", payload: "SETD^i.0.mute^1")
        XCTAssertEqual(h.sent, ["held", "SETD^i.0.mute^1"])
    }
}

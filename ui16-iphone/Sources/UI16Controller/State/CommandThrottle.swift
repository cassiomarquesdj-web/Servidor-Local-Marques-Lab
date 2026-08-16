import Foundation

/// Rate-limits continuous parameter writes (fader/gain/pan/send drags).
///
/// A drag generates one value per touch event — around 60 per second, per parameter.
/// Sending all of them adds no precision but does add congestion on a busy stage Wi-Fi.
/// This coalesces writes **per key**: the first write goes out immediately, and further
/// writes to the same key within `interval` are collapsed into a single trailing write.
///
/// The trailing write matters: whatever value the finger stops on is always transmitted,
/// so the mixer never ends up out of sync with the UI.
///
/// Discrete commands (mute, solo, phantom) must bypass this and send immediately.
public final class CommandThrottle {

    /// Minimum spacing between writes to the same key.
    public var interval: TimeInterval

    /// Sink for payloads that are cleared to send.
    public var send: ((String) -> Void)?

    private var lastSent: [String: TimeInterval] = [:]
    private var lastPayload: [String: String] = [:]
    private var pending: [String: String] = [:]
    private var scheduled: Set<String> = []

    /// Injectable clock so the coalescing logic is testable without real time.
    private let now: () -> TimeInterval
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void

    public init(
        interval: TimeInterval = 0.04,
        now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    ) {
        self.interval = interval
        self.now = now
        self.schedule = schedule
    }

    /// Submit a continuous-parameter write for `key`.
    public func submit(key: String, payload: String) {
        // A value that hasn't changed carries no information — e.g. a fader held against
        // its ceiling would otherwise re-send the same level every window.
        guard lastPayload[key] != payload else {
            pending[key] = nil
            return
        }
        let t = now()
        if let last = lastSent[key], t - last < interval {
            // too soon — keep only the newest value and make sure a flush is queued
            pending[key] = payload
            if !scheduled.contains(key) {
                scheduled.insert(key)
                schedule(interval - (t - last)) { [weak self] in self?.flush(key) }
            }
            return
        }
        // Sending now supersedes anything still queued for this key. Without this, a
        // scheduled flush could fire late and overwrite this newer value with a stale one,
        // leaving the mixer at a level the operator already moved away from.
        pending[key] = nil
        lastSent[key] = t
        lastPayload[key] = payload
        send?(payload)
    }

    /// Send a payload immediately, bypassing throttling (mute/solo/phantom).
    public func sendNow(key: String, payload: String) {
        lastSent[key] = now()
        lastPayload[key] = payload
        pending[key] = nil
        send?(payload)
    }

    private func flush(_ key: String) {
        scheduled.remove(key)
        guard let payload = pending.removeValue(forKey: key) else { return }
        lastSent[key] = now()
        lastPayload[key] = payload
        send?(payload)
    }
}

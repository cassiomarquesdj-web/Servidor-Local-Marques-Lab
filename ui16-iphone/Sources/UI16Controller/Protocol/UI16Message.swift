import Foundation

/// Parsing and encoding of the Soundcraft Ui text protocol.
///
/// The mixer carries state in two message families (confirmed from `mixer-store.ts`):
/// - `SETD^path^value` — **numeric** values (levels, booleans as 0/1, enums).
/// - `SETS^path^value` — **string** values (channel names, show names, …).
///
/// The value may itself contain `^`, so everything after the second separator is the value.
/// On the WebSocket, application messages are framed as `3:::<payload>` and multiple
/// payloads can be newline-separated in a single frame.
public enum UI16Message {

    public enum Kind: String, Sendable { case setd = "SETD", sets = "SETS" }

    /// A parsed state message.
    public struct Parsed: Equatable, Sendable {
        public let kind: Kind
        public let path: String
        public let value: String
        public init(kind: Kind, path: String, value: String) {
            self.kind = kind; self.path = path; self.value = value
        }
        /// Numeric interpretation of the value (nil for non-numeric strings).
        public var number: Double? { Double(value) }
        /// Boolean interpretation (`1`/`true` -> true).
        public var bool: Bool { value == "1" || value.lowercased() == "true" }
    }

    // MARK: Framing

    /// Application-message frame prefix used by the Ui socket.io-style transport.
    public static let framePrefix = "3:::"

    /// Wrap an outbound payload in the transport frame.
    public static func frame(_ payload: String) -> String { framePrefix + payload }

    /// Strip the frame prefix (if present) and split a frame into individual payload lines.
    public static func unframe(_ frame: String) -> [String] {
        let clean = frame.hasPrefix(framePrefix) ? String(frame.dropFirst(framePrefix.count)) : frame
        return clean
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    // MARK: Parsing

    /// Parse a single payload line into a `Parsed` state message, or `nil` if it isn't one.
    public static func parse(_ raw: String) -> Parsed? {
        let kind: Kind
        if raw.hasPrefix("SETD^") { kind = .setd }
        else if raw.hasPrefix("SETS^") { kind = .sets }
        else { return nil }

        // "SETD"/"SETS" are 4 chars; first '^' at index 4, path starts at 5.
        let afterType = raw.index(raw.startIndex, offsetBy: 5)
        guard let sep = raw[afterType...].firstIndex(of: "^") else { return nil }
        let path = String(raw[afterType..<sep])
        guard !path.isEmpty else { return nil }
        let value = String(raw[raw.index(after: sep)...])
        return Parsed(kind: kind, path: path, value: value)
    }

    /// `true` if the payload is a VU meter frame (`VU2^<base64>`).
    public static func isVU(_ raw: String) -> Bool { raw.hasPrefix("VU2^") }

    /// Extract the base64 body of a VU frame.
    public static func vuBody(_ raw: String) -> String? {
        guard isVU(raw) else { return nil }
        return String(raw.dropFirst(4))
    }

    // MARK: Encoding

    /// Build a `SETD` numeric command payload (unframed).
    public static func setd(_ path: String, _ value: Double) -> String {
        "SETD^\(path)^\(formatNumber(value))"
    }

    /// Build a `SETD` boolean command payload (`0`/`1`).
    public static func setd(_ path: String, _ value: Bool) -> String {
        "SETD^\(path)^\(value ? 1 : 0)"
    }

    /// Build a `SETD` integer command payload.
    public static func setd(_ path: String, _ value: Int) -> String {
        "SETD^\(path)^\(value)"
    }

    /// Build a `SETS` string command payload.
    public static func sets(_ path: String, _ value: String) -> String {
        "SETS^\(path)^\(value)"
    }

    /// Format a double without a trailing `.0` for integers and without locale decimals.
    static func formatNumber(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 {
            return String(Int(value))
        }
        // Up to 6 significant decimals, trimming trailing zeros; always '.' as separator.
        var s = String(format: "%.6f", value)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}

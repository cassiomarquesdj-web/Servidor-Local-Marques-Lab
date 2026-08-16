import Foundation

public struct UI16State: Equatable, Sendable {
    public var connected = false
    public var masterLevel: Double = 0.5
    public var masterMuted = false
    public var channels: [Int: ChannelState] = (1...16).reduce(into: [:]) { $0[$1] = ChannelState() }
    public var buses: [String: BusState] = [:]
    public var metrics: [String: String] = [:]
    public var meters: [String: Double] = [:]
    public var selectedBus = "master"
    public var lastMessage = ""

    public init() {}

    public struct ChannelState: Equatable, Sendable {
        public var name = ""
        public var level = 0.5
        public var muted = false
        public var solo = false
        public var pan = 0.5
        public var gain = 0.5
        public var highPass = 0.0
        public var lowPass = 1.0
        public var phantom = false
        public var phase = false
        public var link = false
        public var eqEnabled = true
        public var gateEnabled = false
        public var compressorEnabled = false
        public var fxSend = 0.0
        public var auxSends: [Int: Double] = [:]
        public init() {}
    }

    public struct BusState: Equatable, Sendable {
        public var level = 0.5
        public var muted = false
        public var solo = false
        public var pan = 0.5
        public var sends: [Int: Double] = [:]
        public init() {}
    }
}

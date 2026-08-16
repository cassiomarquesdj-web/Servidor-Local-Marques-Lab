import Foundation

struct UI16State: Equatable, Sendable {
    var connected = false
    var masterLevel: Double = 0.5
    var masterMuted = false
    var channels: [Int: ChannelState] = (1...16).reduce(into: [:]) { $0[$1] = ChannelState() }
    var buses: [String: BusState] = [:]
    var metrics: [String: String] = [:]
    var meters: [String: Double] = [:]
    var selectedBus = "master"
    var lastMessage = ""

    struct ChannelState: Equatable, Sendable {
        var name = ""
        var level = 0.5
        var muted = false
        var solo = false
        var pan = 0.5
        var gain = 0.5
        var highPass = 0.0
        var lowPass = 1.0
        var phantom = false
        var phase = false
        var link = false
        var eqEnabled = true
        var gateEnabled = false
        var compressorEnabled = false
        var fxSend = 0.0
        var auxSends: [Int: Double] = [:]
    }

    struct BusState: Equatable, Sendable {
        var level = 0.5
        var muted = false
        var solo = false
        var pan = 0.5
        var sends: [Int: Double] = [:]
    }
}

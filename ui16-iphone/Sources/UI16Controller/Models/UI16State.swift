import Foundation

struct UI16State: Equatable, Sendable {
    var connected = false
    var masterLevel: Double = 0
    var masterMuted = false
    var channels: [Int: ChannelState] = [:]

    struct ChannelState: Equatable, Sendable {
        var name: String = ""
        var level: Double = 0
        var muted = false
        var pan: Double = 0
        var gain: Double = 0
        var highPass: Double = 0
    }
}

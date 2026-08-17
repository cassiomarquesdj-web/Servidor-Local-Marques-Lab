import AVFoundation
import Foundation

/// Polarity inverter: multiplies every sample by -1.
///
/// iOS ships no stock polarity/phase-invert effect, so this is a small in-process
/// AudioUnit. It is the only way to flip the player's polarity for real rather than
/// drawing a button that does nothing.
///
/// Render-thread rules observed here: no allocation, no locking, no Swift runtime calls
/// that can allocate. The `inverted` flag is read through a raw pointer so the audio
/// thread never touches Swift property observers or reference counting.
final class PolarityAudioUnit: AUAudioUnit {

    private var inputBusArray: AUAudioUnitBusArray!
    private var outputBusArray: AUAudioUnitBusArray!
    private let format: AVAudioFormat

    /// Heap flag shared with the render block. `1` = inverted.
    private let invertedFlag = UnsafeMutablePointer<Int32>.allocate(capacity: 1)

    var inverted: Bool {
        get { invertedFlag.pointee != 0 }
        set { invertedFlag.pointee = newValue ? 1 : 0 }
    }

    static let componentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: fourCC("plrt"),
        componentManufacturer: fourCC("MqLb"),
        componentFlags: 0,
        componentFlagsMask: 0
    )

    private static var isRegistered = false

    /// Register the unit once, so `AVAudioUnit.instantiate` can find it.
    static func registerIfNeeded() {
        guard !isRegistered else { return }
        isRegistered = true
        AUAudioUnit.registerSubclass(
            PolarityAudioUnit.self,
            as: componentDescription,
            name: "Marques Lab Polarity",
            version: 1
        )
    }

    override init(componentDescription: AudioComponentDescription,
                  options: AudioComponentInstantiationOptions = []) throws {
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        invertedFlag.pointee = 0
        try super.init(componentDescription: componentDescription, options: options)

        inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input,
                                            busses: [try AUAudioUnitBus(format: format)])
        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output,
                                             busses: [try AUAudioUnitBus(format: format)])
        maximumFramesToRender = 4096
    }

    deinit { invertedFlag.deallocate() }

    override var inputBusses: AUAudioUnitBusArray { inputBusArray }
    override var outputBusses: AUAudioUnitBusArray { outputBusArray }

    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        // Capture the raw pointer, not `self`: the render block must not retain or
        // message a Swift object on the audio thread.
        let flag = invertedFlag

        return { actionFlags, timestamp, frameCount, outputBusNumber, outputData, realtimeEventListHead, pullInputBlock in

            guard let pullInput = pullInputBlock else { return kAudioUnitErr_NoConnection }

            // Pull upstream audio directly into our output buffers, then process in place.
            var pullFlags = AudioUnitRenderActionFlags()
            let status = pullInput(&pullFlags, timestamp, frameCount, 0, outputData)
            guard status == noErr else { return status }

            guard flag.pointee != 0 else { return noErr }   // pass through untouched

            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            for buffer in buffers {
                guard let raw = buffer.mData else { continue }
                let samples = raw.assumingMemoryBound(to: Float.self)
                let count = Int(frameCount)
                for i in 0..<count {
                    samples[i] = -samples[i]
                }
            }
            return noErr
        }
    }
}

/// Build a FourCC code from a 4-character string.
private func fourCC(_ s: String) -> UInt32 {
    var result: UInt32 = 0
    for byte in s.utf8.prefix(4) {
        result = (result << 8) + UInt32(byte)
    }
    return result
}

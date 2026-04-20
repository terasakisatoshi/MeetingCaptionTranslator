import AVFoundation
import CoreMedia
import Foundation

struct AnalyzerInputClock {
    private(set) var lastBufferEndTime: CMTime?

    mutating func normalizedStartTime(
        requestedStartTime: CMTime,
        frameLength: AVAudioFrameCount,
        sampleRate: Double
    ) -> CMTime {
        let requestedStartTime = requestedStartTime.isValid ? requestedStartTime : (lastBufferEndTime ?? .zero)
        let normalizedStartTime: CMTime

        if let lastBufferEndTime, CMTimeCompare(requestedStartTime, lastBufferEndTime) < 0 {
            normalizedStartTime = lastBufferEndTime
        } else {
            normalizedStartTime = requestedStartTime
        }

        if sampleRate > 0 {
            let sampleRateScale = max(1, CMTimeScale(sampleRate.rounded()))
            let bufferDuration = CMTime(value: CMTimeValue(frameLength), timescale: sampleRateScale)
            lastBufferEndTime = normalizedStartTime + bufferDuration
        } else {
            lastBufferEndTime = normalizedStartTime
        }

        return normalizedStartTime
    }
}

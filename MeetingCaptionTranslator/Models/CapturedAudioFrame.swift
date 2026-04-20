import AVFoundation
import CoreMedia

struct CapturedAudioFrame: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let when: CMTime
}

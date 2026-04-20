import Foundation

@MainActor
protocol CaptureServicing: AnyObject {
    func startCapture(
        inputHandler: @escaping @Sendable (CapturedAudioFrame) -> Void,
        errorHandler: @escaping @MainActor @Sendable (String) -> Void
    ) async throws
    func stopCapture() async
}

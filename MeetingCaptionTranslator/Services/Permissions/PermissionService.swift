import CoreGraphics
import Foundation
import Speech

enum PermissionError: Error {
    case screenRecordingDenied
    case speechRecognitionDenied
}

struct PermissionService {
    func hasScreenRecordingAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenRecordingAccessIfNeeded() -> Bool {
        if hasScreenRecordingAccess() {
            return true
        }

        return CGRequestScreenCaptureAccess()
    }

    func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

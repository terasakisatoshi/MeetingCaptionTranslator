# System Audio Taps Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current `ScreenCaptureKit` audio path with a Core Audio taps implementation that captures Mac-wide playback audio without requesting Screen Recording permission.

**Architecture:** The migration keeps the speech, translation, and overlay pipeline intact while replacing the capture boundary. The new capture stack uses Core Audio taps plus an aggregate device, emits PCM buffers directly into the transcription layer, and simplifies the control window to a fixed `Mac System Audio` source.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Core Audio HAL (`CATapDescription`, `AudioHardwareCreateProcessTap`, `AudioHardwareCreateAggregateDevice`, `AudioDeviceCreateIOProcIDWithBlock`), Speech, Translation, XCTest

---

## File Structure

- `MeetingCaptionTranslator/Models/CapturedAudioFrame.swift`
  - Small sendable wrapper around `AVAudioPCMBuffer` plus capture timestamp.
- `MeetingCaptionTranslator/Services/Capture/CaptureServicing.swift`
  - Capture interface with no screen-target concepts.
- `MeetingCaptionTranslator/Services/Capture/CoreAudioTapConfiguration.swift`
  - Pure helper that builds tap descriptions, aggregate device dictionaries, and consistent names.
- `MeetingCaptionTranslator/Services/Capture/CoreAudioHardwareClient.swift`
  - Thin wrapper around HAL APIs and `OSStatus` mapping.
- `MeetingCaptionTranslator/Services/Capture/PlaybackPCMBufferBuilder.swift`
  - Converts HAL callback data (`AudioBufferList` + `AudioStreamBasicDescription`) into owned `AVAudioPCMBuffer` values.
- `MeetingCaptionTranslator/Services/Capture/SystemPlaybackCaptureService.swift`
  - Concrete Mac-wide playback capture service built on Core Audio taps.
- `MeetingCaptionTranslator/Services/Speech/LiveTranscriptionService.swift`
  - Updated to accept PCM frames directly instead of `CMSampleBuffer`.
- `MeetingCaptionTranslator/ViewModels/AppViewModel.swift`
  - Removes screen-target selection state and handles system-audio permission failures through capture start errors.
- `MeetingCaptionTranslator/App/ContentView.swift`
  - Removes the source picker and refresh button, replaces them with a fixed source label.
- `MeetingCaptionTranslator/Resources/Info.plist`
  - Adds `NSAudioCaptureUsageDescription` and removes the need for Screen Recording messaging.
- `tools/generate_project.rb`
  - Replaces `ScreenCaptureKit` linkage with `CoreAudio`.
- `README.md`
  - Updates permission and runtime instructions for System Audio Recording.
- `MeetingCaptionTranslatorTests/AudioBufferConverterTests.swift`
  - Covers the remaining PCM format normalization code path.
- `MeetingCaptionTranslatorTests/AppViewModelTests.swift`
  - Covers source-less startup and system-audio permission messaging.
- `MeetingCaptionTranslatorTests/InfoPlistMetadataTests.swift`
  - Verifies `NSAudioCaptureUsageDescription` exists.
- `MeetingCaptionTranslatorTests/CoreAudioTapConfigurationTests.swift`
  - Covers pure tap and aggregate descriptor creation.
- `MeetingCaptionTranslatorTests/PlaybackPCMBufferBuilderTests.swift`
  - Covers conversion from HAL callback data to owned PCM buffers.
- `MeetingCaptionTranslatorTests/SystemPlaybackCaptureServiceTests.swift`
  - Covers lifecycle orchestration with a fake hardware client.

### Obsolete Files To Delete

- `MeetingCaptionTranslator/Services/Capture/SystemAudioCaptureService.swift`
- `MeetingCaptionTranslator/Services/Permissions/ScreenRecordingPermissionManager.swift`
- `MeetingCaptionTranslatorTests/ScreenRecordingPermissionManagerTests.swift`

### Existing Files To Keep But Change

- `MeetingCaptionTranslator/Infrastructure/OverlayWindowManager.swift`
  - Keep the current draggable-when-interactive behavior.
- `MeetingCaptionTranslator/Models/AppSettings.swift`
  - Keep the default click-through setting as `false`.

### Official References

- Apple sample for Core Audio taps:
  - https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps
- `CATapDescription` reference:
  - https://developer.apple.com/documentation/coreaudio/catapdescription
- `NSAudioCaptureUsageDescription` reference:
  - https://developer.apple.com/documentation/bundleresources/information-property-list/nsaudiocaptureusagedescription

### Task 1: Reshape The Audio Input Boundary

**Files:**
- Create: `MeetingCaptionTranslator/Models/CapturedAudioFrame.swift`
- Modify: `MeetingCaptionTranslator/Services/Capture/CaptureServicing.swift`
- Modify: `MeetingCaptionTranslator/Services/Audio/AudioBufferConverter.swift`
- Modify: `MeetingCaptionTranslator/Services/Speech/LiveTranscriptionService.swift`
- Test: `MeetingCaptionTranslatorTests/AudioBufferConverterTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AVFoundation
import XCTest
@testable import MeetingCaptionTranslator

final class AudioBufferConverterTests: XCTestCase {
    func test_convert_returnsSameBuffer_whenFormatsAlreadyMatch() throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64)!
        buffer.frameLength = 64

        let result = try AudioBufferConverter().convert(buffer, to: format)

        XCTAssertTrue(result === buffer)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslatorTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:MeetingCaptionTranslatorTests/AudioBufferConverterTests`

Expected: FAIL because `AudioBufferConverterTests.swift` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
// MeetingCaptionTranslator/Models/CapturedAudioFrame.swift
import AVFoundation
import CoreMedia

struct CapturedAudioFrame: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let when: CMTime
}

// MeetingCaptionTranslator/Services/Capture/CaptureServicing.swift
@MainActor
protocol CaptureServicing: AnyObject {
    func startCapture(
        inputHandler: @escaping @Sendable (CapturedAudioFrame) -> Void,
        errorHandler: @escaping @MainActor @Sendable (String) -> Void
    ) async throws

    func stopCapture() async
}

// MeetingCaptionTranslator/Services/Speech/LiveTranscriptionService.swift
func append(frame: CapturedAudioFrame) async {
    guard let continuation else { return }

    do {
        let inputBuffer: AVAudioPCMBuffer
        if let targetFormat {
            inputBuffer = try audioBufferConverter.convert(frame.buffer, to: targetFormat)
        } else {
            inputBuffer = frame.buffer
        }

        continuation.yield(AnalyzerInput(buffer: inputBuffer, bufferStartTime: frame.when))
    } catch {
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslatorTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:MeetingCaptionTranslatorTests/AudioBufferConverterTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add MeetingCaptionTranslator/Models/CapturedAudioFrame.swift MeetingCaptionTranslator/Services/Capture/CaptureServicing.swift MeetingCaptionTranslator/Services/Audio/AudioBufferConverter.swift MeetingCaptionTranslator/Services/Speech/LiveTranscriptionService.swift MeetingCaptionTranslatorTests/AudioBufferConverterTests.swift
git commit -m "refactor: reshape capture input around pcm frames"
```

### Task 2: Remove Source Selection From UI And View Model

**Files:**
- Modify: `MeetingCaptionTranslator/App/ContentView.swift`
- Modify: `MeetingCaptionTranslator/ViewModels/AppViewModel.swift`
- Modify: `MeetingCaptionTranslatorTests/AppViewModelTests.swift`
- Modify: `MeetingCaptionTranslator/Services/Permissions/PermissionService.swift`
- Test: `MeetingCaptionTranslatorTests/AppViewModelTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@MainActor
final class AppViewModelTests: XCTestCase {
    func test_initialize_setsFixedSystemAudioDescription() async {
        let captureService = FakeCaptureService()
        let overlayWindowManager = FakeOverlayWindowManager()
        let viewModel = AppViewModel(
            settingsStore: makeSettingsStore(),
            captureService: captureService,
            overlayWindowManagerFactory: { _ in overlayWindowManager }
        )

        viewModel.initialize()
        await Task.yield()

        XCTAssertEqual(viewModel.selectedTargetDescription, "Mac System Audio")
    }

    func test_start_surfacesSystemAudioPermissionMessage_whenCaptureStartFails() async {
        let captureService = FakeCaptureService(startError: PermissionError.systemAudioRecordingDenied)
        let viewModel = AppViewModel(
            settingsStore: makeSettingsStore(),
            captureService: captureService,
            overlayWindowManagerFactory: { _ in FakeOverlayWindowManager() }
        )

        viewModel.start()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(viewModel.errorMessage, "System Audio Recording permission is required")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslatorTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:MeetingCaptionTranslatorTests/AppViewModelTests`

Expected: FAIL because the view model still expects screen-target selection.

- [ ] **Step 3: Write minimal implementation**

```swift
// MeetingCaptionTranslator/Services/Permissions/PermissionService.swift
enum PermissionError: Error {
    case systemAudioRecordingDenied
    case speechRecognitionDenied
}

// MeetingCaptionTranslator/ViewModels/AppViewModel.swift
@Published private(set) var selectedTargetDescription = "Mac System Audio"

func initialize() {
    if overlayWindowManager == nil {
        overlayWindowManager = overlayWindowManagerFactory(overlayViewModel)
        overlayWindowManager?.show()
    }
}

private func startCapture() async {
    errorMessage = nil
    appState = .preparing
    overlayViewModel.render(lines: [], appState: appState)

    do {
        try await captureService.startCapture(
            inputHandler: { [weak transcriptionService] frame in
                guard let transcriptionService else { return }
                Task {
                    await transcriptionService.append(frame: frame)
                }
            },
            errorHandler: { [weak self] message in
                self?.errorMessage = message
                self?.appState = .error(.translationUnavailable)
            }
        )
    } catch PermissionError.systemAudioRecordingDenied {
        appState = .error(.translationUnavailable)
        errorMessage = "System Audio Recording permission is required"
    }
}

// MeetingCaptionTranslator/App/ContentView.swift
VStack(alignment: .leading, spacing: 8) {
    Text("Source")
        .font(.headline)

    Text(viewModel.selectedTargetDescription)
        .font(.body)

    Text("Captures Mac-wide playback audio")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslatorTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:MeetingCaptionTranslatorTests/AppViewModelTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add MeetingCaptionTranslator/App/ContentView.swift MeetingCaptionTranslator/ViewModels/AppViewModel.swift MeetingCaptionTranslator/Services/Permissions/PermissionService.swift MeetingCaptionTranslatorTests/AppViewModelTests.swift
git commit -m "feat: simplify ui for mac system audio capture"
```

### Task 3: Add System Audio Recording Metadata And Build Configuration

**Files:**
- Modify: `MeetingCaptionTranslator/Resources/Info.plist`
- Modify: `tools/generate_project.rb`
- Create: `MeetingCaptionTranslatorTests/InfoPlistMetadataTests.swift`
- Test: `MeetingCaptionTranslatorTests/InfoPlistMetadataTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest

final class InfoPlistMetadataTests: XCTestCase {
    func test_infoPlist_containsAudioCaptureUsageDescription() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoPlistURL = root.appendingPathComponent("MeetingCaptionTranslator/Resources/Info.plist")
        let plist = NSDictionary(contentsOf: infoPlistURL)

        XCTAssertEqual(
            plist?["NSAudioCaptureUsageDescription"] as? String,
            "This app captures Mac playback audio to transcribe live captions."
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslatorTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:MeetingCaptionTranslatorTests/InfoPlistMetadataTests`

Expected: FAIL because `NSAudioCaptureUsageDescription` is missing.

- [ ] **Step 3: Write minimal implementation**

```xml
<!-- MeetingCaptionTranslator/Resources/Info.plist -->
<key>NSAudioCaptureUsageDescription</key>
<string>This app captures Mac playback audio to transcribe live captions.</string>
```

```ruby
# tools/generate_project.rb
[
  "AppKit",
  "AVFoundation",
  "ScreenCaptureKit",
  "CoreAudio",
  "Speech",
  "Translation",
  "SwiftUI"
].each do |framework|
  app_target.add_system_framework(framework)
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec ruby tools/generate_project.rb && xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslatorTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:MeetingCaptionTranslatorTests/InfoPlistMetadataTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add MeetingCaptionTranslator/Resources/Info.plist tools/generate_project.rb MeetingCaptionTranslatorTests/InfoPlistMetadataTests.swift MeetingCaptionTranslator.xcodeproj/project.pbxproj
git commit -m "build: add system audio capture metadata"
```

### Task 4: Build Pure Core Audio Tap Configuration Helpers

**Files:**
- Create: `MeetingCaptionTranslator/Services/Capture/CoreAudioTapConfiguration.swift`
- Create: `MeetingCaptionTranslator/Services/Capture/CoreAudioHardwareClient.swift`
- Create: `MeetingCaptionTranslatorTests/CoreAudioTapConfigurationTests.swift`
- Test: `MeetingCaptionTranslatorTests/CoreAudioTapConfigurationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import CoreAudio
import XCTest
@testable import MeetingCaptionTranslator

final class CoreAudioTapConfigurationTests: XCTestCase {
    func test_globalStereoTapDescription_isPrivateAndNamed() {
        let configuration = CoreAudioTapConfiguration.defaultConfiguration()
        let description = configuration.tapDescription

        XCTAssertTrue(description.isPrivate)
        XCTAssertEqual(description.name, "MeetingCaptionTranslator Playback Tap")
        XCTAssertTrue(description.isMixdown)
        XCTAssertFalse(description.isMono)
    }

    func test_throwIfError_mapsDevicePermissionsError() {
        XCTAssertThrowsError(
            try CoreAudioHardwareClient.throwIfError(kAudioDevicePermissionsError, context: "start")
        ) { error in
            XCTAssertEqual(error as? CoreAudioTapError, .permissionDenied(context: "start"))
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslatorTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:MeetingCaptionTranslatorTests/CoreAudioTapConfigurationTests`

Expected: FAIL because the helper files do not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
// MeetingCaptionTranslator/Services/Capture/CoreAudioTapConfiguration.swift
import CoreAudio
import Foundation

struct CoreAudioTapConfiguration {
    let tapName: String
    let aggregateDeviceName: String
    let aggregateDeviceUID: String

    static func defaultConfiguration() -> CoreAudioTapConfiguration {
        CoreAudioTapConfiguration(
            tapName: "MeetingCaptionTranslator Playback Tap",
            aggregateDeviceName: "MeetingCaptionTranslator Aggregate Device",
            aggregateDeviceUID: "atelierarith.MeetingCaptionTranslator.aggregate.\(UUID().uuidString)"
        )
    }

    var tapDescription: CATapDescription {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = tapName
        description.isPrivate = true
        return description
    }

    var aggregateDeviceDescription: CFDictionary {
        [
            kAudioAggregateDeviceNameKey: aggregateDeviceName,
            kAudioAggregateDeviceUIDKey: aggregateDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true
        ] as CFDictionary
    }
}

// MeetingCaptionTranslator/Services/Capture/CoreAudioHardwareClient.swift
import CoreAudio
import Foundation

enum CoreAudioTapError: Error, Equatable {
    case permissionDenied(context: String)
    case osStatus(OSStatus, context: String)
}

enum CoreAudioHardwareClient {
    static func throwIfError(_ status: OSStatus, context: String) throws {
        guard status != noErr else { return }
        if status == kAudioDevicePermissionsError {
            throw CoreAudioTapError.permissionDenied(context: context)
        }
        throw CoreAudioTapError.osStatus(status, context: context)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslatorTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:MeetingCaptionTranslatorTests/CoreAudioTapConfigurationTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add MeetingCaptionTranslator/Services/Capture/CoreAudioTapConfiguration.swift MeetingCaptionTranslator/Services/Capture/CoreAudioHardwareClient.swift MeetingCaptionTranslatorTests/CoreAudioTapConfigurationTests.swift
git commit -m "feat: add core audio tap configuration helpers"
```

### Task 5: Add A PCM Buffer Builder For HAL Callback Data

**Files:**
- Create: `MeetingCaptionTranslator/Services/Capture/PlaybackPCMBufferBuilder.swift`
- Create: `MeetingCaptionTranslatorTests/PlaybackPCMBufferBuilderTests.swift`
- Test: `MeetingCaptionTranslatorTests/PlaybackPCMBufferBuilderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AVFoundation
import CoreAudio
import XCTest
@testable import MeetingCaptionTranslator

final class PlaybackPCMBufferBuilderTests: XCTestCase {
    func test_makeBuffer_copiesFloatStereoDataIntoOwnedPCMBuffer() throws {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        var samples: [Float] = [0.25, -0.25, 0.5, -0.5]
        let buffer = UnsafeMutableRawPointer(&samples).assumingMemoryBound(to: UInt8.self)
        var audioBuffer = AudioBuffer(
            mNumberChannels: 2,
            mDataByteSize: UInt32(samples.count * MemoryLayout<Float>.size),
            mData: UnsafeMutableRawPointer(buffer)
        )
        var list = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)

        let pcm = try PlaybackPCMBufferBuilder().makeBuffer(
            from: &list,
            format: asbd,
            frameCount: 2
        )

        XCTAssertEqual(pcm.frameLength, 2)
        XCTAssertEqual(pcm.format.sampleRate, 48_000)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslatorTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:MeetingCaptionTranslatorTests/PlaybackPCMBufferBuilderTests`

Expected: FAIL because `PlaybackPCMBufferBuilder` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
import AVFoundation
import CoreAudio
import Foundation

enum PlaybackPCMBufferBuilderError: Error {
    case unsupportedFormat
    case bufferCreationFailed
}

final class PlaybackPCMBufferBuilder {
    func makeBuffer(
        from bufferList: UnsafePointer<AudioBufferList>,
        format: AudioStreamBasicDescription,
        frameCount: UInt32
    ) throws -> AVAudioPCMBuffer {
        guard let avFormat = AVAudioFormat(streamDescription: UnsafePointer(&format)) else {
            throw PlaybackPCMBufferBuilderError.unsupportedFormat
        }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: avFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw PlaybackPCMBufferBuilderError.bufferCreationFailed
        }

        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        let destination = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)

        for index in 0..<min(source.count, destination.count) {
            memcpy(destination[index].mData, source[index].mData, Int(source[index].mDataByteSize))
        }

        return pcmBuffer
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslatorTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:MeetingCaptionTranslatorTests/PlaybackPCMBufferBuilderTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add MeetingCaptionTranslator/Services/Capture/PlaybackPCMBufferBuilder.swift MeetingCaptionTranslatorTests/PlaybackPCMBufferBuilderTests.swift
git commit -m "feat: add pcm buffer builder for playback taps"
```

### Task 6: Implement The Core Audio Playback Capture Service

**Files:**
- Create: `MeetingCaptionTranslator/Services/Capture/SystemPlaybackCaptureService.swift`
- Create: `MeetingCaptionTranslatorTests/SystemPlaybackCaptureServiceTests.swift`
- Delete: `MeetingCaptionTranslator/Services/Capture/SystemAudioCaptureService.swift`
- Modify: `MeetingCaptionTranslator/ViewModels/AppViewModel.swift`
- Test: `MeetingCaptionTranslatorTests/SystemPlaybackCaptureServiceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AVFoundation
import CoreMedia
import XCTest
@testable import MeetingCaptionTranslator

@MainActor
final class SystemPlaybackCaptureServiceTests: XCTestCase {
    func test_startCapture_createsTapAndStartsHardware() async throws {
        let hardware = FakeCoreAudioPlaybackHardware()
        let service = SystemPlaybackCaptureService(
            hardware: hardware,
            configuration: .defaultConfiguration(),
            bufferBuilder: PlaybackPCMBufferBuilder()
        )

        try await service.startCapture(inputHandler: { _ in }, errorHandler: { _ in })

        XCTAssertEqual(hardware.createdTapCount, 1)
        XCTAssertEqual(hardware.createdAggregateDeviceCount, 1)
        XCTAssertTrue(hardware.didStartIO)
    }

    func test_stopCapture_stopsAndDestroysCreatedObjects() async throws {
        let hardware = FakeCoreAudioPlaybackHardware()
        let service = SystemPlaybackCaptureService(
            hardware: hardware,
            configuration: .defaultConfiguration(),
            bufferBuilder: PlaybackPCMBufferBuilder()
        )

        try await service.startCapture(inputHandler: { _ in }, errorHandler: { _ in })
        await service.stopCapture()

        XCTAssertTrue(hardware.didStopIO)
        XCTAssertTrue(hardware.didDestroyAggregateDevice)
        XCTAssertTrue(hardware.didDestroyTap)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslatorTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:MeetingCaptionTranslatorTests/SystemPlaybackCaptureServiceTests`

Expected: FAIL because `SystemPlaybackCaptureService` and the fake hardware type do not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
import CoreAudio
import CoreMedia
import Foundation

@MainActor
final class SystemPlaybackCaptureService: CaptureServicing {
    private let hardware: any CoreAudioPlaybackHardware
    private let configuration: CoreAudioTapConfiguration
    private let bufferBuilder: PlaybackPCMBufferBuilder
    private let callbackQueue = DispatchQueue(label: "atelierarith.live-caption-translator.playback")

    private var tapID: AudioObjectID?
    private var aggregateDeviceID: AudioObjectID?
    private var ioProcID: AudioDeviceIOProcID?

    init(
        hardware: any CoreAudioPlaybackHardware = DefaultCoreAudioPlaybackHardware(),
        configuration: CoreAudioTapConfiguration = .defaultConfiguration(),
        bufferBuilder: PlaybackPCMBufferBuilder = PlaybackPCMBufferBuilder()
    ) {
        self.hardware = hardware
        self.configuration = configuration
        self.bufferBuilder = bufferBuilder
    }

    func startCapture(
        inputHandler: @escaping @Sendable (CapturedAudioFrame) -> Void,
        errorHandler: @escaping @MainActor @Sendable (String) -> Void
    ) async throws {
        do {
            let tapID = try hardware.createProcessTap(description: configuration.tapDescription)
            let aggregateDeviceID = try hardware.createAggregateDevice(description: configuration.aggregateDeviceDescription)
            let tapUID = try hardware.tapUID(for: tapID)
            try hardware.addTap(tapUID, toAggregateDevice: aggregateDeviceID)
            let ioProcID = try hardware.createIOProcID(
                for: aggregateDeviceID,
                queue: callbackQueue
            ) { [bufferBuilder] when, bufferList, format, frameCount in
                guard let pcmBuffer = try? bufferBuilder.makeBuffer(from: bufferList, format: format, frameCount: frameCount) else {
                    return
                }

                inputHandler(CapturedAudioFrame(buffer: pcmBuffer, when: when))
            }

            try hardware.start(deviceID: aggregateDeviceID, ioProcID: ioProcID)

            self.tapID = tapID
            self.aggregateDeviceID = aggregateDeviceID
            self.ioProcID = ioProcID
        } catch CoreAudioTapError.permissionDenied {
            throw PermissionError.systemAudioRecordingDenied
        } catch {
            errorHandler(error.localizedDescription)
            throw error
        }
    }

    func stopCapture() async {
        if let aggregateDeviceID, let ioProcID {
            hardware.stop(deviceID: aggregateDeviceID, ioProcID: ioProcID)
            hardware.destroyIOProcID(deviceID: aggregateDeviceID, ioProcID: ioProcID)
        }

        if let aggregateDeviceID {
            hardware.destroyAggregateDevice(aggregateDeviceID)
        }

        if let tapID {
            hardware.destroyProcessTap(tapID)
        }

        tapID = nil
        aggregateDeviceID = nil
        ioProcID = nil
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslatorTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:MeetingCaptionTranslatorTests/SystemPlaybackCaptureServiceTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add MeetingCaptionTranslator/Services/Capture/SystemPlaybackCaptureService.swift MeetingCaptionTranslatorTests/SystemPlaybackCaptureServiceTests.swift MeetingCaptionTranslator/ViewModels/AppViewModel.swift
git rm MeetingCaptionTranslator/Services/Capture/SystemAudioCaptureService.swift
git commit -m "feat: capture mac playback audio with core audio taps"
```

### Task 7: Remove Screen Recording Artifacts And Verify The Migration

**Files:**
- Delete: `MeetingCaptionTranslator/Services/Permissions/ScreenRecordingPermissionManager.swift`
- Delete: `MeetingCaptionTranslatorTests/ScreenRecordingPermissionManagerTests.swift`
- Modify: `MeetingCaptionTranslator.xcodeproj/project.pbxproj`
- Modify: `README.md`
- Test: `MeetingCaptionTranslatorTests/AppViewModelTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@MainActor
final class AppViewModelTests: XCTestCase {
    func test_start_doesNotMentionScreenRecording_whenPlaybackPermissionFails() async {
        let captureService = FakeCaptureService(startError: PermissionError.systemAudioRecordingDenied)
        let viewModel = AppViewModel(
            settingsStore: makeSettingsStore(),
            captureService: captureService,
            overlayWindowManagerFactory: { _ in FakeOverlayWindowManager() }
        )

        viewModel.start()
        await Task.yield()
        await Task.yield()

        XCTAssertFalse((viewModel.errorMessage ?? "").contains("Screen Recording"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslatorTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:MeetingCaptionTranslatorTests/AppViewModelTests`

Expected: FAIL if any screen-recording message or dependency remains.

- [ ] **Step 3: Write minimal implementation**

```bash
git rm MeetingCaptionTranslator/Services/Permissions/ScreenRecordingPermissionManager.swift
git rm MeetingCaptionTranslatorTests/ScreenRecordingPermissionManagerTests.swift
bundle exec ruby tools/generate_project.rb
```

```markdown
<!-- README.md -->
The app no longer uses Screen Recording permission.
It requests `System Audio Recording` on first playback capture and `Speech Recognition` on first transcription start.
```

- [ ] **Step 4: Run verification to confirm the migration**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslatorTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

Expected: PASS with all tests green.

Run: `xcodebuild build -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

Expected: BUILD SUCCEEDED

Manual verification:

- Launch the app from Xcode.
- Confirm launch does not show a Screen Recording prompt.
- Press `Start`.
- Confirm macOS requests `System Audio Recording`.
- Grant access and play English audio from any app.
- Confirm English and Japanese subtitles appear in the overlay.
- Turn `Overlay Click-Through` off and drag the overlay.
- Turn `Overlay Click-Through` on and confirm the overlay ignores mouse input.

- [ ] **Step 5: Commit**

```bash
git add MeetingCaptionTranslator.xcodeproj/project.pbxproj README.md
git commit -m "chore: remove screen capture path from playback transcription app"
```

## Self-Review

### Spec Coverage

- Core Audio taps replacement: covered by Tasks 4-6
- System Audio Recording permission and `NSAudioCaptureUsageDescription`: covered by Tasks 2-3 and Task 7 verification
- Remove source picker and refresh action: covered by Task 2
- Keep speech and translation pipeline: covered by Task 1 and Task 6
- Draggable overlay while interactive: already present in the working tree; Task 7 manual verification ensures it remains intact
- README and runtime docs update: covered by Tasks 3 and 7

### Placeholder Scan

- No `TODO`, `TBD`, or “similar to previous task” placeholders remain
- Each code step includes concrete file paths, test names, commands, and snippet targets

### Type Consistency

- `CapturedAudioFrame` is the single capture payload type across Tasks 1, 2, and 6
- `PermissionError.systemAudioRecordingDenied` is the single permission failure type across Tasks 2, 6, and 7
- `SystemPlaybackCaptureService` is the default concrete capture implementation after Task 6

# Meeting Caption Translator Design

## Goal

Build a macOS app for new Apple OS releases that captures system audio from the Mac, transcribes English speech in near real time, translates it into Japanese, and renders both lines in a persistent always-on-top overlay window.

## Product Scope

- Target platform: macOS 26+ (Tahoe-era SDKs and newer APIs are acceptable)
- Input source: system audio only
- Input mechanism: `ScreenCaptureKit` audio capture
- Output: always-on-top overlay window
- Language pair: English audio to Japanese subtitles
- Non-goals for v1:
  - Microphone capture
  - Multi-language selection UI
  - General-purpose recording or export
  - Broad backward compatibility

## User Experience

The app has two UI surfaces.

### Control Window

The control window is the operational console for the app.

- Select the capture target
- Start and stop capture
- Show permission and model readiness state
- Configure overlay opacity, font size, line count, and position behavior
- Show recoverable and fatal errors

### Overlay Window

The overlay window is the primary output.

- Always on top
- Semi-transparent
- Displays English source line above Japanese translation
- Uses lighter styling for in-progress text
- Shows only the most recent lines
- Can become interactive temporarily for repositioning or configuration
- Defaults to click-through outside edit mode

## Technical Direction

The app uses `ScreenCaptureKit` for audio acquisition, `SpeechAnalyzer` and `SpeechTranscriber` for English transcription, and the `Translation` framework for Japanese translation.

This intentionally avoids microphone and virtual device routing. Because the app is for a single user and targets a current OS, the design optimizes for shortest path to a working product rather than maximum compatibility.

## Architecture

The architecture is layered so Apple framework boundaries stay isolated from UI code.

### App Layer

- `MeetingCaptionTranslatorApp`
- Application startup and dependency wiring
- Creates the control window and overlay window controllers

### Capture Layer

- `SystemAudioCaptureService`
- Manages `SCShareableContent`, filter selection, stream lifecycle, and `.audio` sample delivery

### Audio Bridge Layer

- `AudioSampleBufferConverter`
- Converts `CMSampleBuffer` audio payloads into `AVAudioPCMBuffer`
- Normalizes audio shape if needed before transcription input

### Transcription Layer

- `SpeechTranscriptionService`
- Owns `SpeechAnalyzer`, `SpeechTranscriber`, asset readiness, and result streaming
- Produces partial and final English transcription events

### Translation Layer

- `TranslationService`
- Owns `TranslationSession` setup and batch or incremental translation
- Translates stable or debounced English text into Japanese

### Caption Pipeline Layer

- `CaptionPipelineService`
- Coordinates capture -> transcription -> translation
- Handles partial replacement, finalization, debounce, and ordering

### Presentation Layer

- `OverlayViewModel`
- `ControlViewModel`
- `CaptionStore`
- Convert pipeline output into stable UI state

## Data Flow

1. User selects a shareable target in the control window.
2. `SystemAudioCaptureService` starts an `SCStream` with audio output enabled.
3. The service emits audio `CMSampleBuffer` instances.
4. `AudioSampleBufferConverter` converts them to `AVAudioPCMBuffer`.
5. `SpeechTranscriptionService` feeds those buffers into `SpeechAnalyzer`.
6. The transcription service emits partial and final English segments.
7. `CaptionPipelineService` debounces eligible text and requests translation.
8. `TranslationService` returns Japanese text for the current stable segment.
9. `CaptionStore` merges source and translated text into overlay lines.
10. The overlay updates immediately.

## State Model

Global app state is intentionally small.

- `idle`
- `preparing`
- `capturing`
- `transcribing`
- `degraded`
- `error`

`degraded` is used when source transcription still works but translation is temporarily unavailable.

## Error Handling

Errors are typed and surfaced consistently.

### Fatal Errors

- Screen Recording permission denied
- Capture target invalid or unavailable
- Stream failed to start
- Speech unavailable for required locale

Fatal errors block subtitle output and appear in the control window.

### Recoverable Errors

- Translation temporarily unavailable
- Capture interrupted and restartable
- Partial stream drop or target disappearance

Recoverable errors keep as much of the app alive as possible. For example, if translation fails, the overlay keeps showing English source text.

## Permissions and Environment Checks

- Request Screen Recording permission when required
- Do not request microphone permission
- Validate speech locale support before starting capture
- Validate translation language support before first translation
- Surface clear instructions for fixing missing permission or models

## Persistence

User-adjustable settings are persisted.

- Overlay opacity
- Overlay font size
- Maximum visible lines
- Overlay click-through behavior
- Preferred capture target identifier when possible
- Language pair model object, even if v1 only exposes `en -> ja`

## Test Strategy

The app will not rely on full Apple framework execution for all tests.

### Unit Tests

- `CaptionStoreTests`
- `CaptionPipelineServiceTests`
- `OverlayViewModelTests`
- `AppSettingsStoreTests`
- Error classification tests

### Integration Tests

- Simulated capture event -> transcription event -> translation event -> overlay line update
- Partial transcription replacement
- Translation failure fallback to English-only display
- Stop and restart lifecycle behavior

### Manual Verification

- Grant Screen Recording permission
- Start capture against real system audio
- Confirm English and Japanese text appear in overlay
- Confirm overlay stays on top
- Confirm click-through behavior
- Confirm settings persistence across relaunch

## File Structure

```text
LiveCaptionTranslator/
├── MeetingCaptionTranslator.xcodeproj
├── MeetingCaptionTranslator/
│   ├── App/
│   │   ├── MeetingCaptionTranslatorApp.swift
│   │   ├── AppEnvironment.swift
│   │   ├── AppState.swift
│   │   └── CaptionLanguagePair.swift
│   ├── Models/
│   │   ├── AppError.swift
│   │   ├── CaptionLine.swift
│   │   ├── CaptureTarget.swift
│   │   ├── TranscriptEvent.swift
│   │   └── TranslationEvent.swift
│   ├── Services/
│   │   ├── Capture/
│   │   │   ├── SystemAudioCaptureService.swift
│   │   │   └── ShareableContentService.swift
│   │   ├── Audio/
│   │   │   └── AudioSampleBufferConverter.swift
│   │   ├── Speech/
│   │   │   ├── SpeechTranscriptionService.swift
│   │   │   └── SpeechReadinessService.swift
│   │   ├── Translation/
│   │   │   ├── TranslationService.swift
│   │   │   └── TranslationReadinessService.swift
│   │   ├── Caption/
│   │   │   ├── CaptionPipelineService.swift
│   │   │   └── CaptionStore.swift
│   │   └── Persistence/
│   │       └── AppSettingsStore.swift
│   ├── ViewModels/
│   │   ├── ControlViewModel.swift
│   │   └── OverlayViewModel.swift
│   ├── Views/
│   │   ├── Control/
│   │   │   ├── ControlWindowView.swift
│   │   │   └── CaptureTargetPickerView.swift
│   │   └── Overlay/
│   │       ├── OverlayWindowController.swift
│   │       └── OverlayView.swift
│   ├── Infrastructure/
│   │   ├── Permissions/
│   │   │   └── ScreenRecordingPermissionManager.swift
│   │   └── Logging/
│   │       └── AppLogger.swift
│   └── Resources/
│       ├── Assets.xcassets
│       ├── Info.plist
│       └── MeetingCaptionTranslator.entitlements
├── MeetingCaptionTranslatorTests/
│   ├── CaptionStoreTests.swift
│   ├── CaptionPipelineServiceTests.swift
│   ├── OverlayViewModelTests.swift
│   └── AppSettingsStoreTests.swift
└── docs/
    └── plans/
```

## Delivery Standard

The product is considered complete when all of the following are true.

- The app launches as a macOS app bundle
- The user can choose a capture target and start capture
- System audio is transcribed from English into Japanese subtitles
- The overlay remains always on top
- The overlay remains usable for passive viewing without blocking normal interaction
- Restart and stop behavior is stable
- Basic tests pass

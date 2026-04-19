# Meeting Caption Translator Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS app that captures system audio with ScreenCaptureKit, transcribes English speech, translates it to Japanese, and renders both in an always-on-top overlay.

**Architecture:** Use a thin SwiftUI and AppKit shell over separable services for capture, audio conversion, transcription, translation, and caption presentation. Keep framework-specific code isolated so the app can degrade gracefully when translation or permission checks fail while preserving source subtitles.

**Tech Stack:** Swift 6, Xcode 16+, macOS 26 SDK, SwiftUI, AppKit, ScreenCaptureKit, AVFoundation, Speech, Translation, XCTest

---

### Task 1: Scaffold the macOS app project

**Files:**
- Create: `MeetingCaptionTranslator.xcodeproj/project.pbxproj`
- Create: `MeetingCaptionTranslator/App/MeetingCaptionTranslatorApp.swift`
- Create: `MeetingCaptionTranslator/Resources/Info.plist`
- Create: `MeetingCaptionTranslator/Resources/MeetingCaptionTranslator.entitlements`
- Create: `MeetingCaptionTranslator/Resources/Assets.xcassets/Contents.json`
- Create: `MeetingCaptionTranslatorTests/Placeholder.swift`

**Step 1: Write the failing test**

Create `MeetingCaptionTranslatorTests/ProjectLayoutSmokeTests.swift` with a test that asserts the expected top-level source files exist.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -destination 'platform=macOS'`

Expected: project or files missing

**Step 3: Write minimal implementation**

Create the Xcode project, app entry file, resource files, and test target wiring with the smallest viable structure.

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -destination 'platform=macOS' -only-testing:MeetingCaptionTranslatorTests/ProjectLayoutSmokeTests`

Expected: PASS

**Step 5: Commit**

```bash
git add MeetingCaptionTranslator.xcodeproj MeetingCaptionTranslator MeetingCaptionTranslatorTests
git commit -m "chore: scaffold macOS caption translator app"
```

### Task 2: Add core models and app state

**Files:**
- Create: `MeetingCaptionTranslator/App/AppState.swift`
- Create: `MeetingCaptionTranslator/App/CaptionLanguagePair.swift`
- Create: `MeetingCaptionTranslator/Models/AppError.swift`
- Create: `MeetingCaptionTranslator/Models/CaptionLine.swift`
- Create: `MeetingCaptionTranslator/Models/CaptureTarget.swift`
- Create: `MeetingCaptionTranslator/Models/TranscriptEvent.swift`
- Create: `MeetingCaptionTranslator/Models/TranslationEvent.swift`
- Test: `MeetingCaptionTranslatorTests/CoreModelTests.swift`

**Step 1: Write the failing test**

Write tests for:
- caption line initialization and replacement semantics
- language pair default value of `en -> ja`
- app state transitions holding a recoverable degraded state

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -destination 'platform=macOS' -only-testing:MeetingCaptionTranslatorTests/CoreModelTests`

Expected: symbols not found

**Step 3: Write minimal implementation**

Implement plain Swift value types and enums only.

**Step 4: Run test to verify it passes**

Run the same test command.

Expected: PASS

**Step 5: Commit**

```bash
git add MeetingCaptionTranslator/App MeetingCaptionTranslator/Models MeetingCaptionTranslatorTests/CoreModelTests.swift
git commit -m "feat: add core caption and app state models"
```

### Task 3: Implement settings persistence

**Files:**
- Create: `MeetingCaptionTranslator/Services/Persistence/AppSettingsStore.swift`
- Create: `MeetingCaptionTranslator/Models/AppSettings.swift`
- Test: `MeetingCaptionTranslatorTests/AppSettingsStoreTests.swift`

**Step 1: Write the failing test**

Write tests for saving and loading:
- font size
- opacity
- maximum visible lines
- click-through mode
- default language pair placeholder

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -destination 'platform=macOS' -only-testing:MeetingCaptionTranslatorTests/AppSettingsStoreTests`

Expected: missing types

**Step 3: Write minimal implementation**

Implement a `UserDefaults`-backed store with small serializable settings state.

**Step 4: Run test to verify it passes**

Run the same command.

Expected: PASS

**Step 5: Commit**

```bash
git add MeetingCaptionTranslator/Services/Persistence MeetingCaptionTranslator/Models/AppSettings.swift MeetingCaptionTranslatorTests/AppSettingsStoreTests.swift
git commit -m "feat: persist overlay and language settings"
```

### Task 4: Build caption storage behavior

**Files:**
- Create: `MeetingCaptionTranslator/Services/Caption/CaptionStore.swift`
- Test: `MeetingCaptionTranslatorTests/CaptionStoreTests.swift`

**Step 1: Write the failing test**

Write tests for:
- appending a new partial line
- replacing a partial line with a newer partial line
- finalizing a line
- trimming old lines to a configured maximum

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -destination 'platform=macOS' -only-testing:MeetingCaptionTranslatorTests/CaptionStoreTests`

Expected: missing store implementation

**Step 3: Write minimal implementation**

Implement a store that tracks current live line and finalized history.

**Step 4: Run test to verify it passes**

Run the same command.

Expected: PASS

**Step 5: Commit**

```bash
git add MeetingCaptionTranslator/Services/Caption/CaptionStore.swift MeetingCaptionTranslatorTests/CaptionStoreTests.swift
git commit -m "feat: add caption line store behavior"
```

### Task 5: Implement the overlay view model

**Files:**
- Create: `MeetingCaptionTranslator/ViewModels/OverlayViewModel.swift`
- Test: `MeetingCaptionTranslatorTests/OverlayViewModelTests.swift`

**Step 1: Write the failing test**

Write tests for:
- rendering caption lines into display rows
- degraded mode preserving English when translation is absent
- applying settings like font size and opacity

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -destination 'platform=macOS' -only-testing:MeetingCaptionTranslatorTests/OverlayViewModelTests`

Expected: missing view model

**Step 3: Write minimal implementation**

Implement an observable view model with published overlay state.

**Step 4: Run test to verify it passes**

Run the same command.

Expected: PASS

**Step 5: Commit**

```bash
git add MeetingCaptionTranslator/ViewModels/OverlayViewModel.swift MeetingCaptionTranslatorTests/OverlayViewModelTests.swift
git commit -m "feat: add overlay presentation state"
```

### Task 6: Implement caption pipeline coordination

**Files:**
- Create: `MeetingCaptionTranslator/Services/Caption/CaptionPipelineService.swift`
- Test: `MeetingCaptionTranslatorTests/CaptionPipelineServiceTests.swift`

**Step 1: Write the failing test**

Write tests using fake transcription and translation clients for:
- partial transcript updates
- final transcript translation
- translation failure falling back to English-only
- stop resetting active transient state

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -destination 'platform=macOS' -only-testing:MeetingCaptionTranslatorTests/CaptionPipelineServiceTests`

Expected: missing pipeline

**Step 3: Write minimal implementation**

Implement the coordinator using protocols for transcription and translation dependencies.

**Step 4: Run test to verify it passes**

Run the same command.

Expected: PASS

**Step 5: Commit**

```bash
git add MeetingCaptionTranslator/Services/Caption/CaptionPipelineService.swift MeetingCaptionTranslatorTests/CaptionPipelineServiceTests.swift
git commit -m "feat: coordinate transcription and translation pipeline"
```

### Task 7: Add screen recording permission management

**Files:**
- Create: `MeetingCaptionTranslator/Infrastructure/Permissions/ScreenRecordingPermissionManager.swift`
- Modify: `MeetingCaptionTranslator/Models/AppError.swift`
- Test: `MeetingCaptionTranslatorTests/PermissionMappingTests.swift`

**Step 1: Write the failing test**

Write tests for mapping raw permission states into app-level readiness and errors.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -destination 'platform=macOS' -only-testing:MeetingCaptionTranslatorTests/PermissionMappingTests`

Expected: missing permission manager

**Step 3: Write minimal implementation**

Implement a manager that exposes current permission status and a request path.

**Step 4: Run test to verify it passes**

Run the same command.

Expected: PASS

**Step 5: Commit**

```bash
git add MeetingCaptionTranslator/Infrastructure/Permissions/ScreenRecordingPermissionManager.swift MeetingCaptionTranslator/Models/AppError.swift MeetingCaptionTranslatorTests/PermissionMappingTests.swift
git commit -m "feat: add screen recording permission handling"
```

### Task 8: Implement shareable content discovery

**Files:**
- Create: `MeetingCaptionTranslator/Services/Capture/ShareableContentService.swift`
- Modify: `MeetingCaptionTranslator/Models/CaptureTarget.swift`
- Test: `MeetingCaptionTranslatorTests/CaptureTargetMappingTests.swift`

**Step 1: Write the failing test**

Write tests for mapping raw display and app candidates into stable app-facing capture targets.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -destination 'platform=macOS' -only-testing:MeetingCaptionTranslatorTests/CaptureTargetMappingTests`

Expected: missing mapping service

**Step 3: Write minimal implementation**

Implement a service that wraps `SCShareableContent` and converts it into app models.

**Step 4: Run test to verify it passes**

Run the same command.

Expected: PASS

**Step 5: Commit**

```bash
git add MeetingCaptionTranslator/Services/Capture/ShareableContentService.swift MeetingCaptionTranslator/Models/CaptureTarget.swift MeetingCaptionTranslatorTests/CaptureTargetMappingTests.swift
git commit -m "feat: discover capture targets"
```

### Task 9: Implement system audio capture service

**Files:**
- Create: `MeetingCaptionTranslator/Services/Capture/SystemAudioCaptureService.swift`
- Create: `MeetingCaptionTranslator/Services/Audio/AudioSampleBufferConverter.swift`
- Test: `MeetingCaptionTranslatorTests/AudioSampleBufferConverterTests.swift`

**Step 1: Write the failing test**

Write converter tests for translating test audio sample buffers into `AVAudioPCMBuffer` shape expected by the speech layer.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -destination 'platform=macOS' -only-testing:MeetingCaptionTranslatorTests/AudioSampleBufferConverterTests`

Expected: converter missing

**Step 3: Write minimal implementation**

Implement the buffer converter first, then implement the stream service around `SCStream` and `.audio` output delivery.

**Step 4: Run test to verify it passes**

Run the same command and then build the app target.

Run: `xcodebuild build -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -destination 'platform=macOS'`

Expected: tests pass and app builds

**Step 5: Commit**

```bash
git add MeetingCaptionTranslator/Services/Capture MeetingCaptionTranslator/Services/Audio MeetingCaptionTranslatorTests/AudioSampleBufferConverterTests.swift
git commit -m "feat: capture system audio via screencapturekit"
```

### Task 10: Implement speech readiness and transcription

**Files:**
- Create: `MeetingCaptionTranslator/Services/Speech/SpeechReadinessService.swift`
- Create: `MeetingCaptionTranslator/Services/Speech/SpeechTranscriptionService.swift`
- Test: `MeetingCaptionTranslatorTests/SpeechReadinessServiceTests.swift`

**Step 1: Write the failing test**

Write tests for:
- English locale support selection
- readiness reporting
- protocol-level transcription event emission with a fake audio feeder

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -destination 'platform=macOS' -only-testing:MeetingCaptionTranslatorTests/SpeechReadinessServiceTests`

Expected: missing speech services

**Step 3: Write minimal implementation**

Implement readiness checks first, then the transcriber wrapper over `SpeechAnalyzer` and `SpeechTranscriber`.

**Step 4: Run test to verify it passes**

Run the same command and build the app target.

Expected: tests pass and app builds

**Step 5: Commit**

```bash
git add MeetingCaptionTranslator/Services/Speech MeetingCaptionTranslatorTests/SpeechReadinessServiceTests.swift
git commit -m "feat: add speech transcription services"
```

### Task 11: Implement translation readiness and translation service

**Files:**
- Create: `MeetingCaptionTranslator/Services/Translation/TranslationReadinessService.swift`
- Create: `MeetingCaptionTranslator/Services/Translation/TranslationService.swift`
- Test: `MeetingCaptionTranslatorTests/TranslationServiceTests.swift`

**Step 1: Write the failing test**

Write tests for:
- checking support for English to Japanese
- translating a stable transcription string through a protocol stub
- error fallback behavior surfaced to the pipeline

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -destination 'platform=macOS' -only-testing:MeetingCaptionTranslatorTests/TranslationServiceTests`

Expected: missing translation services

**Step 3: Write minimal implementation**

Implement readiness checks and a translation wrapper over `TranslationSession`.

**Step 4: Run test to verify it passes**

Run the same command and build the app target.

Expected: tests pass and app builds

**Step 5: Commit**

```bash
git add MeetingCaptionTranslator/Services/Translation MeetingCaptionTranslatorTests/TranslationServiceTests.swift
git commit -m "feat: add translation services"
```

### Task 12: Build the control window view model

**Files:**
- Create: `MeetingCaptionTranslator/ViewModels/ControlViewModel.swift`
- Test: `MeetingCaptionTranslatorTests/ControlViewModelTests.swift`

**Step 1: Write the failing test**

Write tests for:
- loading targets
- start blocked by missing permission
- start blocked by missing target
- stop resetting state
- propagating degraded translation state

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -destination 'platform=macOS' -only-testing:MeetingCaptionTranslatorTests/ControlViewModelTests`

Expected: missing control view model

**Step 3: Write minimal implementation**

Implement the orchestration view model using injected services only.

**Step 4: Run test to verify it passes**

Run the same command.

Expected: PASS

**Step 5: Commit**

```bash
git add MeetingCaptionTranslator/ViewModels/ControlViewModel.swift MeetingCaptionTranslatorTests/ControlViewModelTests.swift
git commit -m "feat: add control window orchestration"
```

### Task 13: Build the overlay and control UI

**Files:**
- Create: `MeetingCaptionTranslator/Views/Control/ControlWindowView.swift`
- Create: `MeetingCaptionTranslator/Views/Control/CaptureTargetPickerView.swift`
- Create: `MeetingCaptionTranslator/Views/Overlay/OverlayView.swift`
- Create: `MeetingCaptionTranslator/Views/Overlay/OverlayWindowController.swift`
- Create: `MeetingCaptionTranslator/App/AppEnvironment.swift`
- Modify: `MeetingCaptionTranslator/App/MeetingCaptionTranslatorApp.swift`

**Step 1: Write the failing test**

Write a lightweight UI-focused test for the overlay view model bindings and add a smoke test that the app environment can be constructed.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -destination 'platform=macOS' -only-testing:MeetingCaptionTranslatorTests/AppEnvironmentSmokeTests`

Expected: view wiring missing

**Step 3: Write minimal implementation**

Build the SwiftUI control window, AppKit overlay window controller, and dependency environment.

**Step 4: Run test to verify it passes**

Run the smoke test and then build the full app target.

Run: `xcodebuild build -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -destination 'platform=macOS'`

Expected: PASS

**Step 5: Commit**

```bash
git add MeetingCaptionTranslator/App MeetingCaptionTranslator/Views
git commit -m "feat: add control and overlay windows"
```

### Task 14: Wire the end-to-end app flow

**Files:**
- Modify: `MeetingCaptionTranslator/ViewModels/ControlViewModel.swift`
- Modify: `MeetingCaptionTranslator/ViewModels/OverlayViewModel.swift`
- Modify: `MeetingCaptionTranslator/Services/Caption/CaptionPipelineService.swift`
- Modify: `MeetingCaptionTranslator/App/AppEnvironment.swift`
- Test: `MeetingCaptionTranslatorTests/EndToEndPipelineIntegrationTests.swift`

**Step 1: Write the failing test**

Write an integration test that injects fake capture, speech, and translation services and verifies final overlay state for:
- partial source text
- final source text
- translated target text

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -destination 'platform=macOS' -only-testing:MeetingCaptionTranslatorTests/EndToEndPipelineIntegrationTests`

Expected: integration not wired

**Step 3: Write minimal implementation**

Wire service graph and UI-facing state propagation until the integration test passes.

**Step 4: Run test to verify it passes**

Run the same command.

Expected: PASS

**Step 5: Commit**

```bash
git add MeetingCaptionTranslator/App MeetingCaptionTranslator/ViewModels MeetingCaptionTranslator/Services/Caption MeetingCaptionTranslatorTests/EndToEndPipelineIntegrationTests.swift
git commit -m "feat: wire end-to-end subtitle flow"
```

### Task 15: Verify the full app

**Files:**
- Modify: `docs/plans/2026-04-19-meeting-caption-translator-design.md`
- Modify: `docs/plans/2026-04-19-meeting-caption-translator.md`

**Step 1: Run automated verification**

Run:

```bash
xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -destination 'platform=macOS'
```

Expected: all tests pass

**Step 2: Run build verification**

Run:

```bash
xcodebuild build -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -destination 'platform=macOS'
```

Expected: build succeeds without unresolved framework issues

**Step 3: Perform manual verification**

Verify:
- app requests Screen Recording permission
- capture target list loads
- system audio capture starts
- English and Japanese subtitles appear
- overlay stays on top
- click-through behavior works
- stop and restart both work

**Step 4: Record any deviations**

Update the docs with any known limitations or required user setup.

**Step 5: Commit**

```bash
git add docs/plans
git commit -m "docs: record verification results and limitations"
```

# System Audio Taps Migration Design

## Goal

Replace the app's `ScreenCaptureKit`-based system audio capture with a system-audio-only path based on Core Audio taps so the product captures Mac-wide playback audio without requesting Screen Recording permission.

## Product Scope

- Target platform: macOS 26.0+
- Input source: Mac-wide playback audio only
- Input permission: System Audio Recording
- Output: existing always-on-top overlay window
- Language pair: English playback audio to Japanese subtitles

## Non-Goals

- Screen or window capture
- Per-app audio capture in v1 of this migration
- Microphone capture
- Audio export or recording file output
- Backward compatibility with pre-Core-Audio-tap macOS releases

## User Experience

The control window should reflect that there is no visual capture source.

- Remove the source picker
- Remove the refresh sources action
- Show a fixed source label such as `Mac System Audio`
- Request system audio recording permission only when the user presses `Start`
- Keep speech recognition permission behavior unchanged
- Keep the overlay click-through toggle, but make the overlay draggable whenever click-through is off

The overlay remains the primary result surface.

- Always on top
- Semi-transparent
- English source text above Japanese translation
- Draggable while click-through is disabled

## Technical Direction

Move capture from `ScreenCaptureKit` to Core Audio taps.

- Create a global audio tap for Mac playback audio
- Route the tap through an aggregate device that can be consumed like an input source
- Read PCM audio buffers from the tap path and adapt them to the existing speech pipeline
- Remove `SCShareableContent`, `SCContentFilter`, and `SCStream` from the capture layer

This aligns the app with Apple's system-audio-only permission model, which uses `NSAudioCaptureUsageDescription` instead of Screen Recording.

## Architecture

### App Layer

- `MeetingCaptionTranslatorApp`
- Keeps startup and window wiring responsibilities

### Capture Layer

- Replace `SystemAudioCaptureService` with `SystemPlaybackCaptureService`
- Own Core Audio tap lifecycle
- Own aggregate device lifecycle
- Emit audio samples suitable for speech ingestion

### Permissions Layer

- Remove Screen Recording permission checks
- Add a system audio capture permission manager or direct service wrapper if needed
- Keep speech recognition permission checks

### Speech Layer

- Reuse `LiveTranscriptionService`
- Preserve current `CapturedAudioSample` and `AudioBufferConverter` boundary where practical

### Translation Layer

- Reuse `AppleTranslationService`

### Presentation Layer

- Simplify `AppViewModel` by removing capture-target selection state
- Preserve overlay settings and rendering flow

## Data Flow

1. User presses `Start`.
2. The app checks system audio recording permission.
3. `SystemPlaybackCaptureService` creates a Core Audio tap and aggregate device.
4. The capture service reads Mac playback audio buffers from the tap path.
5. The existing speech layer transcribes English audio into partial and final transcript events.
6. The translation layer translates stable English segments into Japanese.
7. The caption pipeline merges source and translated lines.
8. The overlay updates immediately.

## Permissions and Environment Checks

- Add `NSAudioCaptureUsageDescription` to `Info.plist`
- Keep `NSSpeechRecognitionUsageDescription`
- Do not request Screen Recording permission
- Do not request microphone permission
- Request system audio recording permission only when capture starts
- Surface clear settings guidance if system audio capture or speech permission is denied

## UI Changes

### Control Window

- Remove `Source` picker
- Remove `Refresh Sources` button
- Replace source selection state with a static description
- Keep `Start`, `Stop`, overlay click-through, status, and error messaging

### Overlay Window

- Keep current appearance
- Ensure dragging works whenever click-through is disabled
- Default click-through to off for first launch so repositioning works without extra steps

## Error Handling

### Fatal Errors

- System audio recording permission denied
- Speech recognition permission denied
- Core Audio tap creation failure
- Aggregate device setup failure
- Audio read failure that prevents transcription

### Recoverable Errors

- Translation temporarily unavailable
- Temporary audio interruption if restart succeeds cleanly

Fatal errors block subtitle output and are shown in the control window.

## Testing Strategy

### Unit Tests

- App view model startup no longer refreshes capture sources automatically
- Default settings disable click-through
- Overlay interaction configuration allows dragging when interactive
- Permission mapping for system audio capture path

### Integration Tests

- Start flow with granted system audio and speech permissions
- Start flow blocked by denied system audio permission
- Transcription and translation pipeline remains unchanged for incoming audio samples

### Manual Verification

- First launch does not request Screen Recording permission
- Pressing `Start` requests System Audio Recording permission
- Granted permission enables transcription from Mac playback audio
- Overlay can be dragged while click-through is off
- Overlay ignores mouse input while click-through is on

## Risks and Trade-Offs

### Recommended Approach: Full Migration to Core Audio Taps

- Best matches the product requirement
- Removes incorrect Screen Recording dependency
- Keeps the runtime model aligned with Apple's system audio permission APIs

### Alternative: Keep ScreenCaptureKit and accept Screen Recording permission

- Lowest code churn
- Incorrect for the desired permission model
- Keeps the current user-facing problem

### Alternative: Dual capture backends

- Could preserve older experiments or future per-app capture support
- Adds complexity without helping the stated requirement
- Not recommended for the current scope

## Implementation Notes

- The capture abstraction should remain interface-driven so the speech pipeline doesn't need framework-specific knowledge
- If Core Audio tap output format differs from the current speech input assumptions, normalize in the capture or audio bridge layer rather than leaking format logic into the speech service
- Update README and user-facing setup instructions after the migration is complete

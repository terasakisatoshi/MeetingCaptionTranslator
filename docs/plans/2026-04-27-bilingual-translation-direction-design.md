# Bilingual Translation Direction Design

## Goal

Allow the app to translate both English system audio to Japanese and Japanese system audio to English. The first implementation uses an explicit user-selected direction, while keeping the model structure ready for a future automatic language detection mode.

## Current State

The app currently starts speech recognition with `Locale(identifier: "en-US")` in `AppViewModel.startCapture`. Translation is configured from `settings.languagePair`, whose default is `CaptionLanguagePair(sourceLanguage: "en", targetLanguage: "ja")`.

This means the translation service already has a language-pair boundary, but speech recognition is still fixed to English.

## Recommended Approach

Add a manual translation direction setting with two supported directions:

- English to Japanese
- Japanese to English

Expand `CaptionLanguagePair` so each supported pair exposes:

- source language identifier for Translation
- target language identifier for Translation
- speech locale identifier for Speech
- user-facing display title

Keep `CaptionLanguagePair.defaultPair` as English to Japanese for compatibility with existing saved settings and current behavior.

## User Experience

The control window adds a `Language Direction` control near the audio input/status controls. The user can choose either `English -> Japanese` or `Japanese -> English`.

Changing the language direction while capture is running is disabled in the first implementation. Speech recognition and translation sessions are both created at startup, so changing direction mid-session would require a pipeline restart. Keeping the control disabled while running makes the behavior explicit and avoids silent restarts.

The selected direction is persisted through `AppSettingsStore`.

## Data Flow

1. `ContentView` displays `CaptionLanguagePair.supportedPairs`.
2. User selection calls a new `AppViewModel.updateLanguagePair(_:)`.
3. `AppViewModel` stores the pair in `AppSettings` and persists it.
4. On `start()`, `AppViewModel` creates:
   - `LiveTranscriptionServiceAdapter(locale: Locale(identifier: settings.languagePair.speechLocaleIdentifier))`
   - `AppleTranslationServiceAdapter(languagePair: settings.languagePair)`
5. `CaptionPipelineService` remains unchanged. It receives transcript text and asks the configured translator for the target-language output.

## Future Automatic Detection

This design does not implement automatic language detection. It keeps the future path straightforward by making the translation direction a first-class value instead of scattering raw language strings.

A later automatic mode can add a separate setting such as `CaptionLanguageMode.manual(CaptionLanguagePair)` or `CaptionLanguageMode.automatic`, then choose a `CaptionLanguagePair` before starting the speech and translation pipeline.

## Error Handling

Existing error behavior remains unchanged:

- Speech authorization or preparation failures use `.transcriptionUnavailable`.
- Translation preparation or translation failures use `.translationUnavailable`.
- System audio capture failures use `.systemAudioCaptureUnavailable`.

If Japanese speech recognition is unavailable on the host system, startup should fail through the existing speech preparation path and show the localized error description.

## Testing

Add or update XCTest coverage for:

- `CaptionLanguagePair` exposes English to Japanese and Japanese to English supported pairs.
- `CaptionLanguagePair.defaultPair` remains English to Japanese.
- `AppViewModel.start()` passes the selected pair's speech locale into the transcription service factory.
- `AppViewModel.start()` passes the selected pair into the translation service factory.
- `AppViewModel.updateLanguagePair(_:)` persists the selection while idle.
- Existing settings payloads without newer fields still load and default to English to Japanese.

Run the full project test command after implementation:

```bash
xcodebuild test \
  -project MeetingCaptionTranslator.xcodeproj \
  -scheme MeetingCaptionTranslatorTests \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

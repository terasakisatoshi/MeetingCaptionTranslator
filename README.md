# MeetingCaptionTranslator

macOS app for capturing English system audio, transcribing it with Apple Speech APIs, translating it to Japanese, and rendering the result in an always-on-top overlay.

## Requirements
- macOS 26.0+
- Xcode 16+ with the macOS 26 SDK
- Ruby/Bundler for project generation

## Project Layout
- `MeetingCaptionTranslator/`: app source
- `MeetingCaptionTranslatorTests/`: XCTest suite
- `tools/generate_project.rb`: regenerates the `.xcodeproj`
- `docs/plans/`: design and implementation notes

## Setup
```bash
bundle install
bundle exec ruby tools/generate_project.rb
```

## Build
```bash
xcodebuild build \
  -project MeetingCaptionTranslator.xcodeproj \
  -scheme MeetingCaptionTranslator \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

## Test
```bash
xcodebuild test \
  -project MeetingCaptionTranslator.xcodeproj \
  -scheme MeetingCaptionTranslatorTests \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

## Run
Open `MeetingCaptionTranslator.xcodeproj` in Xcode and run the `MeetingCaptionTranslator` scheme, or launch the built app from `DerivedData`. On first use, allow:
- `Screen Recording`
- `Speech Recognition`

Then select a display in the control window and press `Start`.

## Architecture
- `SystemAudioCaptureService`: `ScreenCaptureKit` system audio capture
- `LiveTranscriptionService`: `SpeechAnalyzer` / `SpeechTranscriber`
- `AppleTranslationService`: `TranslationSession`
- `CaptionPipelineService`: partial/final caption coordination
- `OverlayWindowManager`: always-on-top AppKit overlay window

## Notes
- Source/target language is currently fixed to English → Japanese through `CaptionLanguagePair.defaultPair`.
- After adding or removing source files, rerun `bundle exec ruby tools/generate_project.rb`.

# MeetingCaptionTranslator

macOS app for capturing English system audio through a fixed Core Audio tap, transcribing it with Apple Speech APIs, translating it to Japanese, and rendering the result in an always-on-top overlay.

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

## Get the App
To obtain a runnable app bundle from this repository:

- Install Xcode, Ruby, and Bundler first.
- Use the HTTPS clone URL below unless you already have GitHub SSH access configured.

```bash
git clone https://github.com/terasakisatoshi/MeetingCaptionTranslator.git
cd MeetingCaptionTranslator
bundle install
bundle exec ruby tools/generate_project.rb
ruby tools/build_release.rb
```

The built app is written to `dist/MeetingCaptionTranslator.app`.

## Build
```bash
xcodebuild build \
  -project MeetingCaptionTranslator.xcodeproj \
  -scheme MeetingCaptionTranslator \
  -destination 'platform=macOS'
```

## Release Artifact
```bash
ruby tools/build_release.rb
```

Copies the built app bundle to `dist/MeetingCaptionTranslator.app`.
Validate the release path with `ruby tools/build_release_test.rb`.
This artifact uses the project's default signing settings.

## Test
```bash
xcodebuild test \
  -project MeetingCaptionTranslator.xcodeproj \
  -scheme MeetingCaptionTranslatorTests \
  -destination 'platform=macOS'
```

## Run
Before building or running, open `MeetingCaptionTranslator.xcodeproj` in Xcode and choose a Team and signing identity in `Signing & Capabilities`. For local development, `Apple Development` is sufficient. On first use, allow:
- `System Audio Recording`
- `Speech Recognition`

Then press `Start` to capture the Mac system audio source and begin transcription.

If you intentionally need an unsigned build for diagnostics, override the command with `CODE_SIGNING_ALLOWED=NO`. Do not use that build for permission testing. macOS TCC uses the app signature to remember privacy grants, so unsigned builds can re-prompt for `Speech Recognition` on every launch.

## Architecture
- `SystemPlaybackCaptureService`: Core Audio tap for the Mac system audio source
- `LiveTranscriptionService`: `SpeechAnalyzer` / `SpeechTranscriber`
- `AppleTranslationService`: `TranslationSession`
- `CaptionPipelineService`: partial/final caption coordination
- `OverlayWindowManager`: always-on-top AppKit overlay window

## Notes
- Source/target language is currently fixed to English → Japanese through `CaptionLanguagePair.defaultPair`.
- The capture source is fixed to the Mac system audio output; there is no display picker.
- After adding or removing source files, rerun `bundle exec ruby tools/generate_project.rb`.

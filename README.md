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
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

## Release Artifact
```bash
ruby tools/build_release.rb
```

Copies the built app bundle to `dist/MeetingCaptionTranslator.app`.
Validate the release path with `ruby tools/build_release_test.rb`.

## Test
```bash
xcodebuild test \
  -project MeetingCaptionTranslator.xcodeproj \
  -scheme MeetingCaptionTranslatorTests \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

## Run
Open `MeetingCaptionTranslator.xcodeproj` in Xcode and run the `MeetingCaptionTranslator` scheme, or launch the built app from `DerivedData`. If you used `ruby tools/build_release.rb`, launch `dist/MeetingCaptionTranslator.app` instead. On first use, allow:
- `System Audio Recording`
- `Speech Recognition`

Then press `Start` to capture the Mac system audio source and begin transcription.

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

# Repository Guidelines

## Project Structure & Module Organization
`MeetingCaptionTranslator/` contains the app target. Use `App/` for entry points and top-level UI, `Models/` for value types, `Services/` for framework-facing logic, `ViewModels/` for state orchestration, `Views/` for SwiftUI views, `Infrastructure/` for AppKit/window glue, and `Resources/` for plist, entitlements, and assets. Tests live in `MeetingCaptionTranslatorTests/`. Design and implementation notes belong in `docs/plans/`. The Xcode project takes both folders from the filesystem (file-system-synchronized groups), so adding or removing a source file needs no project change.

## Build, Test, and Development Commands
Build with `xcodebuild build -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`. Run tests with `xcodebuild test -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslatorTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`.

## Coding Style & Naming Conventions
Follow Swift 6 conventions: 4-space indentation, one top-level type per file when practical, `UpperCamelCase` for types, `lowerCamelCase` for properties and methods. Keep service boundaries explicit: capture, speech, translation, persistence, and caption pipeline should remain isolated. Favor small value types in `Models/` and put Apple framework integration behind service APIs.

## Testing Guidelines
Tests use `XCTest`. Mirror production names in test files, for example `CaptionPipelineServiceTests.swift` for `CaptionPipelineService.swift`. Name test methods by behavior, such as `test_translation_failure_falls_back_to_english_only`. Add unit coverage for new model or service behavior before wiring UI changes. Run the full `xcodebuild test ...` command before claiming completion.

## Commit & Pull Request Guidelines
Use short Conventional Commit style messages such as `feat: add overlay controls` or `fix: handle denied screen recording permission`. PRs should describe user-visible behavior, list verification commands, and include screenshots for control window or overlay UI changes.

## Security & Configuration Tips
The app relies on `Screen Recording` and `Speech Recognition` permissions. Do not hardcode secrets or external service credentials. Keep `Info.plist` usage descriptions accurate, and note any new permission or OS-version requirement in both `README.md` and `docs/plans/`.

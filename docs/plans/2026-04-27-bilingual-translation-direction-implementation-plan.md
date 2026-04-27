# Bilingual Translation Direction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persisted manual translation direction setting so the app can translate English speech to Japanese or Japanese speech to English.

**Architecture:** `CaptionLanguagePair` becomes the single source of truth for supported directions, including Translation language IDs, Speech locale ID, and display title. `AppViewModel` persists direction changes and creates speech/translation services from the selected pair at startup. `ContentView` exposes the setting while the app is idle.

**Tech Stack:** Swift 6, SwiftUI, Speech, Translation, XCTest

---

### Task 1: Extend CaptionLanguagePair

**Files:**
- Modify: `MeetingCaptionTranslator/App/CaptionLanguagePair.swift`
- Modify: `MeetingCaptionTranslatorTests/CoreModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Add tests that define both supported pairs and their speech locales:

```swift
func test_caption_language_pair_exposes_supported_translation_directions() {
    XCTAssertEqual(CaptionLanguagePair.supportedPairs, [
        .englishToJapanese,
        .japaneseToEnglish
    ])
}

func test_caption_language_pair_exposes_speech_locale_and_display_title() {
    XCTAssertEqual(CaptionLanguagePair.englishToJapanese.sourceLanguage, "en")
    XCTAssertEqual(CaptionLanguagePair.englishToJapanese.targetLanguage, "ja")
    XCTAssertEqual(CaptionLanguagePair.englishToJapanese.speechLocaleIdentifier, "en-US")
    XCTAssertEqual(CaptionLanguagePair.englishToJapanese.displayTitle, "English -> Japanese")

    XCTAssertEqual(CaptionLanguagePair.japaneseToEnglish.sourceLanguage, "ja")
    XCTAssertEqual(CaptionLanguagePair.japaneseToEnglish.targetLanguage, "en")
    XCTAssertEqual(CaptionLanguagePair.japaneseToEnglish.speechLocaleIdentifier, "ja-JP")
    XCTAssertEqual(CaptionLanguagePair.japaneseToEnglish.displayTitle, "Japanese -> English")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test \
  -project MeetingCaptionTranslator.xcodeproj \
  -scheme MeetingCaptionTranslatorTests \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:MeetingCaptionTranslatorTests/CoreModelTests
```

Expected: FAIL because `supportedPairs`, `englishToJapanese`, `japaneseToEnglish`, `speechLocaleIdentifier`, and `displayTitle` do not exist.

- [ ] **Step 3: Implement the model additions**

Update `CaptionLanguagePair`:

```swift
import Foundation

struct CaptionLanguagePair: Codable, Equatable, Sendable, Hashable, Identifiable {
    let sourceLanguage: String
    let targetLanguage: String
    let speechLocaleIdentifier: String
    let displayTitle: String

    var id: String {
        "\(sourceLanguage)-\(targetLanguage)"
    }

    static let englishToJapanese = CaptionLanguagePair(
        sourceLanguage: "en",
        targetLanguage: "ja",
        speechLocaleIdentifier: "en-US",
        displayTitle: "English -> Japanese"
    )

    static let japaneseToEnglish = CaptionLanguagePair(
        sourceLanguage: "ja",
        targetLanguage: "en",
        speechLocaleIdentifier: "ja-JP",
        displayTitle: "Japanese -> English"
    )

    static let supportedPairs: [CaptionLanguagePair] = [
        .englishToJapanese,
        .japaneseToEnglish
    ]

    static let defaultPair = englishToJapanese
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same `CoreModelTests` command.

Expected: PASS.

### Task 2: Preserve Legacy Settings Compatibility

**Files:**
- Modify: `MeetingCaptionTranslator/App/CaptionLanguagePair.swift`
- Modify: `MeetingCaptionTranslatorTests/AppSettingsStoreTests.swift`

- [ ] **Step 1: Write the failing legacy decode test**

Add a test showing older saved settings with only source/target language still decode to the richer supported pair:

```swift
func test_store_loads_legacy_language_pair_without_speech_locale_fields() throws {
    let suiteName = "AppSettingsStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let legacyPayload = """
    {
      "overlayOpacity": 0.7,
      "fontSize": 26,
      "maximumVisibleLines": 5,
      "overlayWidth": 960,
      "overlayHeight": 220,
      "languagePair": {
        "sourceLanguage": "ja",
        "targetLanguage": "en"
      }
    }
    """
    defaults.set(try XCTUnwrap(legacyPayload.data(using: .utf8)), forKey: "app_settings")

    let restored = AppSettingsStore(userDefaults: defaults).load()

    XCTAssertEqual(restored.languagePair, .japaneseToEnglish)
    XCTAssertEqual(restored.languagePair.speechLocaleIdentifier, "ja-JP")
    XCTAssertEqual(restored.languagePair.displayTitle, "Japanese -> English")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test \
  -project MeetingCaptionTranslator.xcodeproj \
  -scheme MeetingCaptionTranslatorTests \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:MeetingCaptionTranslatorTests/AppSettingsStoreTests
```

Expected: FAIL because `CaptionLanguagePair` does not yet normalize decoded legacy pairs.

- [ ] **Step 3: Implement custom decoding**

Add a custom initializer and encoder to `CaptionLanguagePair`:

```swift
init(
    sourceLanguage: String,
    targetLanguage: String,
    speechLocaleIdentifier: String,
    displayTitle: String
) {
    self.sourceLanguage = sourceLanguage
    self.targetLanguage = targetLanguage
    self.speechLocaleIdentifier = speechLocaleIdentifier
    self.displayTitle = displayTitle
}

init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let sourceLanguage = try container.decode(String.self, forKey: .sourceLanguage)
    let targetLanguage = try container.decode(String.self, forKey: .targetLanguage)

    if let supportedPair = Self.supportedPairs.first(where: {
        $0.sourceLanguage == sourceLanguage && $0.targetLanguage == targetLanguage
    }) {
        self = supportedPair
        return
    }

    self.init(
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        speechLocaleIdentifier: try container.decodeIfPresent(String.self, forKey: .speechLocaleIdentifier) ?? Locale.current.identifier,
        displayTitle: try container.decodeIfPresent(String.self, forKey: .displayTitle) ?? "\(sourceLanguage) -> \(targetLanguage)"
    )
}

func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(sourceLanguage, forKey: .sourceLanguage)
    try container.encode(targetLanguage, forKey: .targetLanguage)
    try container.encode(speechLocaleIdentifier, forKey: .speechLocaleIdentifier)
    try container.encode(displayTitle, forKey: .displayTitle)
}

private enum CodingKeys: String, CodingKey {
    case sourceLanguage
    case targetLanguage
    case speechLocaleIdentifier
    case displayTitle
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same `AppSettingsStoreTests` command.

Expected: PASS.

### Task 3: Use Selected Pair When Starting Services

**Files:**
- Modify: `MeetingCaptionTranslator/ViewModels/AppViewModel.swift`
- Modify: `MeetingCaptionTranslatorTests/AppViewModelTests.swift`

- [ ] **Step 1: Write the failing start configuration test**

Add a test that saves Japanese to English before creating the view model, then verifies the factories receive `ja-JP` and `.japaneseToEnglish`:

```swift
func test_start_usesSelectedLanguagePairForSpeechAndTranslation() async throws {
    let store = makeSettingsStore()
    var settings = store.load()
    settings.languagePair = .japaneseToEnglish
    try store.save(settings)

    let captureService = RecordingCaptureService()
    let transcriptionService = RecordingTranscriptionService()
    let translationService = RecordingTranslationService()
    var requestedLocale: Locale?
    var requestedLanguagePair: CaptionLanguagePair?
    let viewModel = AppViewModel(
        settingsStore: store,
        captureService: captureService,
        transcriptionServiceFactory: { locale in
            requestedLocale = locale
            return transcriptionService
        },
        translationServiceFactory: { languagePair in
            requestedLanguagePair = languagePair
            return translationService
        },
        overlayWindowManagerFactory: { _, _ in FakeOverlayWindowManager() }
    )

    viewModel.start()
    await waitUntil { captureService.didEnterStartCapture }

    XCTAssertEqual(requestedLocale?.identifier, "ja-JP")
    XCTAssertEqual(requestedLanguagePair, .japaneseToEnglish)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test \
  -project MeetingCaptionTranslator.xcodeproj \
  -scheme MeetingCaptionTranslatorTests \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:MeetingCaptionTranslatorTests/AppViewModelTests/test_start_usesSelectedLanguagePairForSpeechAndTranslation
```

Expected: FAIL because `AppViewModel` still passes `Locale(identifier: "en-US")`.

- [ ] **Step 3: Implement selected locale usage**

Change `startCapture(token:)`:

```swift
let transcriptionService = transcriptionServiceFactory(
    Locale(identifier: settings.languagePair.speechLocaleIdentifier)
)
let translationService = translationServiceFactory(settings.languagePair)
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same single-test command.

Expected: PASS.

### Task 4: Persist Manual Language Direction Changes

**Files:**
- Modify: `MeetingCaptionTranslator/ViewModels/AppViewModel.swift`
- Modify: `MeetingCaptionTranslatorTests/AppViewModelTests.swift`

- [ ] **Step 1: Write the failing persistence test**

Add a test for idle direction updates:

```swift
func test_updateLanguagePair_persistsSelectionWhileIdle() {
    let store = makeSettingsStore()
    let viewModel = AppViewModel(
        settingsStore: store,
        captureService: FakeCaptureService(),
        overlayWindowManagerFactory: { _, _ in FakeOverlayWindowManager() }
    )

    viewModel.updateLanguagePair(.japaneseToEnglish)

    XCTAssertEqual(viewModel.languagePair, .japaneseToEnglish)
    XCTAssertEqual(store.load().languagePair, .japaneseToEnglish)
}
```

Add a test for running-state protection:

```swift
func test_updateLanguagePair_ignoresSelectionWhileRunning() async throws {
    let store = makeSettingsStore()
    let captureService = RecordingCaptureService()
    let transcriptionService = RecordingTranscriptionService()
    let translationService = RecordingTranslationService()
    let viewModel = AppViewModel(
        settingsStore: store,
        captureService: captureService,
        transcriptionServiceFactory: { _ in transcriptionService },
        translationServiceFactory: { _ in translationService },
        overlayWindowManagerFactory: { _, _ in FakeOverlayWindowManager() }
    )

    viewModel.start()
    await waitUntil { captureService.didEnterStartCapture }

    viewModel.updateLanguagePair(.japaneseToEnglish)

    XCTAssertEqual(viewModel.languagePair, .englishToJapanese)
    XCTAssertEqual(store.load().languagePair, .englishToJapanese)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test \
  -project MeetingCaptionTranslator.xcodeproj \
  -scheme MeetingCaptionTranslatorTests \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:MeetingCaptionTranslatorTests/AppViewModelTests/test_updateLanguagePair_persistsSelectionWhileIdle \
  -only-testing:MeetingCaptionTranslatorTests/AppViewModelTests/test_updateLanguagePair_ignoresSelectionWhileRunning
```

Expected: FAIL because `languagePair` and `updateLanguagePair(_:)` do not exist.

- [ ] **Step 3: Implement view model API**

Add a read-only property:

```swift
var languagePair: CaptionLanguagePair {
    settings.languagePair
}
```

Add the update method:

```swift
func updateLanguagePair(_ languagePair: CaptionLanguagePair) {
    guard !appState.isRunning, appState != .preparing else {
        return
    }

    settings.languagePair = languagePair
    try? settingsStore.save(settings)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same two-test command.

Expected: PASS.

### Task 5: Add Language Direction UI

**Files:**
- Modify: `MeetingCaptionTranslator/App/ContentView.swift`

- [ ] **Step 1: Add the Picker**

Place this below the audio input section:

```swift
VStack(alignment: .leading, spacing: 8) {
    Text("Language Direction")
        .font(.headline)

    Picker(
        "Language Direction",
        selection: Binding(
            get: { viewModel.languagePair },
            set: { viewModel.updateLanguagePair($0) }
        )
    ) {
        ForEach(CaptionLanguagePair.supportedPairs) { pair in
            Text(pair.displayTitle).tag(pair)
        }
    }
    .pickerStyle(.segmented)
    .disabled(viewModel.appState.isRunning || viewModel.appState == .preparing)
}
```

- [ ] **Step 2: Update the subtitle copy**

Change the fixed subtitle to:

```swift
Text("System audio to bilingual overlay subtitles")
    .foregroundStyle(.secondary)
```

- [ ] **Step 3: Build to verify UI compilation**

Run:

```bash
xcodebuild build \
  -project MeetingCaptionTranslator.xcodeproj \
  -scheme MeetingCaptionTranslator \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: PASS.

### Task 6: Update README and Run Full Verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update user-facing docs**

Update README references from English-only translation to bidirectional manual translation. Preserve command blocks.

- [ ] **Step 2: Run full tests**

Run:

```bash
xcodebuild test \
  -project MeetingCaptionTranslator.xcodeproj \
  -scheme MeetingCaptionTranslatorTests \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: PASS.

- [ ] **Step 3: Review final diff**

Run:

```bash
git diff --stat
git diff -- MeetingCaptionTranslator/App/CaptionLanguagePair.swift MeetingCaptionTranslator/ViewModels/AppViewModel.swift MeetingCaptionTranslator/App/ContentView.swift MeetingCaptionTranslatorTests/CoreModelTests.swift MeetingCaptionTranslatorTests/AppSettingsStoreTests.swift MeetingCaptionTranslatorTests/AppViewModelTests.swift README.md
```

Expected: Diff only contains bilingual language direction changes and documentation updates.

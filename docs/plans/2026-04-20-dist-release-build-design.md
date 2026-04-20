# Dist Release Build Design

## Goal

Add a repository-local release build entry point that produces `./dist/MeetingCaptionTranslator.app` without requiring the user to manually locate `DerivedData`.

## Non-Goals

- Change the Xcode target, scheme, or build settings to emit products into `dist`
- Package `.dSYM`, `.zip`, or installer artifacts
- Replace the existing direct `xcodebuild` workflow for developers who still want raw build output

## Recommended Approach

Add a new Ruby script at `tools/build_release.rb`.

The script will:

1. Run the existing release build command for the app target:
   `xcodebuild build -project MeetingCaptionTranslator.xcodeproj -scheme MeetingCaptionTranslator -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
2. Query build settings with `xcodebuild -showBuildSettings` using the same project, scheme, and configuration
3. Read `TARGET_BUILD_DIR` and `FULL_PRODUCT_NAME` from that output
4. Resolve the built app bundle path from those values
5. Recreate `./dist`
6. Copy only the built `.app` bundle into `./dist`

This keeps the Xcode project behavior unchanged and makes the release artifact location stable for local use and CI.

## Why This Approach

### Option A: Dedicated wrapper script

Recommended.

- Keeps packaging logic out of the generated Xcode project
- Avoids hidden side effects during normal Xcode builds
- Works the same in terminal and CI
- Stays resilient if `DerivedData` moves

### Option B: Force a custom `-derivedDataPath`

Rejected.

- Makes the build output location predictable
- But changes the build environment for every invocation
- Encourages mixing temporary build intermediates with user-facing artifacts

### Option C: Add an Xcode run script build phase

Rejected.

- Hides packaging behavior inside the app target
- Would require regenerating project structure through `tools/generate_project.rb`
- Makes every release build mutate repository state as a side effect

## Error Handling

- If the release build fails, the script exits with the same non-zero status
- If build settings cannot be resolved, the script fails with a clear message
- If the expected `.app` bundle does not exist after a successful build, the script fails explicitly instead of silently creating an incomplete `dist`

## Verification

Primary verification for this tooling change is end-to-end execution:

```bash
ruby tools/build_release.rb
```

Success criteria:

- Command exits with status `0`
- `dist/MeetingCaptionTranslator.app` exists
- The copied bundle is a valid macOS app bundle

## Documentation Changes

Update `README.md` to add the new release artifact command and document that the built app is copied to `./dist`.

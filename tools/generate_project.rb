#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "xcodeproj"

ROOT = File.expand_path("..", __dir__)
PROJECT_PATH = File.join(ROOT, "MeetingCaptionTranslator.xcodeproj")
APP_DIR = File.join(ROOT, "MeetingCaptionTranslator")
TEST_DIR = File.join(ROOT, "MeetingCaptionTranslatorTests")

ASSET_CATALOG = "Resources/Assets.xcassets"

def ensure_file(path, contents)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, contents) unless File.exist?(path)
end

def write_seed_files
  ensure_file(
    File.join(APP_DIR, "App/MeetingCaptionTranslatorApp.swift"),
    <<~SWIFT
      import SwiftUI

      @main
      struct MeetingCaptionTranslatorApp: App {
          var body: some Scene {
              WindowGroup {
                  ContentView()
              }
          }
      }
    SWIFT
  )

  ensure_file(
    File.join(APP_DIR, "App/ContentView.swift"),
    <<~SWIFT
      import SwiftUI

      struct ContentView: View {
          var body: some View {
              Text("Meeting Caption Translator")
                  .padding()
          }
      }
    SWIFT
  )

  ensure_file(
    File.join(APP_DIR, "Resources/Info.plist"),
    <<~PLIST
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
          <key>CFBundleDevelopmentRegion</key>
          <string>$(DEVELOPMENT_LANGUAGE)</string>
          <key>CFBundleExecutable</key>
          <string>$(EXECUTABLE_NAME)</string>
          <key>CFBundleIdentifier</key>
          <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
          <key>CFBundleInfoDictionaryVersion</key>
          <string>6.0</string>
          <key>CFBundleName</key>
          <string>$(PRODUCT_NAME)</string>
          <key>CFBundlePackageType</key>
          <string>APPL</string>
          <key>CFBundleShortVersionString</key>
          <string>1.0</string>
          <key>CFBundleVersion</key>
          <string>1</string>
          <key>LSMinimumSystemVersion</key>
          <string>26.0</string>
          <key>NSAudioCaptureUsageDescription</key>
          <string>This app captures Mac playback audio to transcribe live captions.</string>
          <key>NSSpeechRecognitionUsageDescription</key>
          <string>This app transcribes captured system audio into captions.</string>
      </dict>
      </plist>
    PLIST
  )

  ensure_file(
    File.join(APP_DIR, "Resources/MeetingCaptionTranslator.entitlements"),
    <<~PLIST
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict/>
      </plist>
    PLIST
  )

  ensure_file(
    File.join(APP_DIR, "Resources/Assets.xcassets/Contents.json"),
    <<~JSON
      {
        "info" : {
          "author" : "xcode",
          "version" : 1
        }
      }
    JSON
  )

  ensure_file(
    File.join(TEST_DIR, "Placeholder.swift"),
    <<~SWIFT
      import XCTest

      final class Placeholder: XCTestCase {}
    SWIFT
  )

  ensure_file(
    File.join(TEST_DIR, "ProjectLayoutSmokeTests.swift"),
    <<~SWIFT
      import XCTest

      final class ProjectLayoutSmokeTests: XCTestCase {
          func test_expected_seed_files_exist() {
              let root = URL(fileURLWithPath: #filePath)
                  .deletingLastPathComponent()
                  .deletingLastPathComponent()

              let requiredPaths = [
                  "MeetingCaptionTranslator/App/MeetingCaptionTranslatorApp.swift",
                  "MeetingCaptionTranslator/App/ContentView.swift",
                  "MeetingCaptionTranslator/Resources/Info.plist",
              ]

              for path in requiredPaths {
                  XCTAssertTrue(
                      FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                      "Expected file missing: \\(path)"
                  )
              }
          }
      }
    SWIFT
  )
end

write_seed_files

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.attributes["LastSwiftMigration"] = "9999"
project.root_object.development_region = "en"
project.build_configuration_list.set_setting("SWIFT_VERSION", "6.0")

app_target = project.new_target(:application, "MeetingCaptionTranslator", :osx, "26.0")
test_target = project.new_target(:unit_test_bundle, "MeetingCaptionTranslatorTests", :osx, "26.0")
test_target.add_dependency(app_target)

[
  "AppKit",
  "AVFoundation",
  "CoreAudio",
  "Speech",
  "Translation",
  "SwiftUI"
].each do |framework|
  app_target.add_system_framework(framework)
end

project.products_group.set_source_tree("<group>")

app_group = project.main_group.new_group("MeetingCaptionTranslator", "MeetingCaptionTranslator")
test_group = project.main_group.new_group("MeetingCaptionTranslatorTests", "MeetingCaptionTranslatorTests")

Dir.glob(File.join(APP_DIR, "**/*"), File::FNM_DOTMATCH)
  .select { |path| File.file?(path) }
  .map { |path| path.delete_prefix("#{APP_DIR}/") }
  .reject { |path| path.include?(".xcassets/") }
  .sort
  .each do |relative_path|
  file_ref = app_group.new_file(relative_path)
  app_target.add_file_references([file_ref]) unless relative_path.end_with?(".plist", ".entitlements")
end

asset_ref = app_group.new_file(ASSET_CATALOG)
app_target.resources_build_phase.add_file_reference(asset_ref)

Dir.glob(File.join(TEST_DIR, "**/*.swift"))
  .map { |path| path.delete_prefix("#{TEST_DIR}/") }
  .sort
  .each do |relative_path|
  file_ref = test_group.new_file(relative_path)
  test_target.add_file_references([file_ref])
end

app_target.build_configurations.each do |config|
  config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "atelierarith.MeetingCaptionTranslator"
  config.build_settings["GENERATE_INFOPLIST_FILE"] = "NO"
  config.build_settings["INFOPLIST_FILE"] = "MeetingCaptionTranslator/Resources/Info.plist"
  config.build_settings["CODE_SIGN_ENTITLEMENTS"] = "MeetingCaptionTranslator/Resources/MeetingCaptionTranslator.entitlements"
  config.build_settings["CODE_SIGN_STYLE"] = "Automatic"
  config.build_settings["SWIFT_EMIT_LOC_STRINGS"] = "NO"
  config.build_settings["MACOSX_DEPLOYMENT_TARGET"] = "26.0"
  config.build_settings["LD_RUNPATH_SEARCH_PATHS"] = ["$(inherited)", "@executable_path/../Frameworks"]
  config.build_settings["PRODUCT_NAME"] = "MeetingCaptionTranslator"
  config.build_settings["ENABLE_APP_SANDBOX"] = "NO"
end

test_target.build_configurations.each do |config|
  config.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
  config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "atelierarith.MeetingCaptionTranslatorTests"
  config.build_settings["MACOSX_DEPLOYMENT_TARGET"] = "26.0"
  config.build_settings["TEST_HOST"] = "$(BUILT_PRODUCTS_DIR)/MeetingCaptionTranslator.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/MeetingCaptionTranslator"
  config.build_settings["BUNDLE_LOADER"] = "$(TEST_HOST)"
end

project.recreate_user_schemes
project.save

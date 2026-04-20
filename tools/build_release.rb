#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "open3"

module BuildRelease
  class BuildError < StandardError; end

  ROOT = File.expand_path("..", __dir__)
  PROJECT = "MeetingCaptionTranslator.xcodeproj"
  SCHEME = "MeetingCaptionTranslator"
  CONFIGURATION = "Release"
  DESTINATION = "platform=macOS"

  class CommandRunner
    def run(*args)
      system(*args)
      $?.dup
    end

    def capture(*args)
      Open3.capture2e(*args)
    end
  end

  def self.run(root: ROOT, runner: CommandRunner.new)
    Dir.chdir(root) do
      build_status = runner.run(*xcodebuild_build_command)
      return build_status.exitstatus || 1 unless build_status.success?

      output, status = runner.capture(*xcodebuild_show_build_settings_command)
      raise BuildError, "xcodebuild -showBuildSettings failed" unless status.success?

      built_app_path = built_app_path_from_settings(parse_build_settings(output))
      copy_product(root: root, built_app_path: built_app_path)
      0
    end
  end

  def self.main(root: ROOT, runner: CommandRunner.new, io: $stderr)
    run(root: root, runner: runner)
  rescue BuildError => e
    io.puts(e.message)
    1
  end

  def self.xcodebuild_build_command
    [
      "xcodebuild",
      "build",
      "-project", PROJECT,
      "-scheme", SCHEME,
      "-configuration", CONFIGURATION,
      "-destination", DESTINATION,
      "CODE_SIGNING_ALLOWED=NO",
      "ONLY_ACTIVE_ARCH=NO",
      "ARCHS=arm64 x86_64"
    ]
  end

  def self.xcodebuild_show_build_settings_command
    [
      "xcodebuild",
      "-showBuildSettings",
      "-project", PROJECT,
      "-scheme", SCHEME,
      "-configuration", CONFIGURATION,
      "-destination", DESTINATION
    ]
  end

  def self.parse_build_settings(output)
    output.each_line.each_with_object({}) do |line, settings|
      next unless line.include?(" = ")

      key, value = line.split(" = ", 2)
      settings[key.strip] = value.strip
    end
  end

  def self.built_app_path_from_settings(settings)
    target_build_dir = settings["TARGET_BUILD_DIR"]
    raise BuildError, "Missing build setting: TARGET_BUILD_DIR" if target_build_dir.to_s.empty?

    full_product_name = settings["FULL_PRODUCT_NAME"]
    raise BuildError, "Missing build setting: FULL_PRODUCT_NAME" if full_product_name.to_s.empty?

    File.join(target_build_dir, full_product_name)
  end

  def self.copy_product(root:, built_app_path:)
    raise BuildError, "Built app bundle not found: #{built_app_path}" unless File.directory?(built_app_path)

    dist_path = File.join(root, "dist")
    FileUtils.rm_rf(dist_path)
    FileUtils.mkdir_p(dist_path)
    FileUtils.cp_r(built_app_path, dist_path)
  end
end

if $PROGRAM_NAME == __FILE__
  exit BuildRelease.main
end

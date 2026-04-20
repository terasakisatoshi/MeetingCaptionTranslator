#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "stringio"
require "tmpdir"
require "minitest/autorun"
require_relative "build_release"

class BuildReleaseTest < Minitest::Test
  Status = Struct.new(:exitstatus) do
    def success?
      exitstatus.to_i.zero?
    end
  end

  class FakeRunner
    attr_reader :build_args, :capture_args, :cwd_during_build, :cwd_during_settings

    def initialize(build_status:, settings_output:, settings_status: Status.new(0))
      @build_status = build_status
      @settings_output = settings_output
      @settings_status = settings_status
    end

    def run(*args)
      @build_args = args
      @cwd_during_build = Dir.pwd
      @build_status
    end

    def capture(*args)
      @capture_args = args
      @cwd_during_settings = Dir.pwd
      [@settings_output, @settings_status]
    end
  end

  def test_built_app_path_from_settings_extracts_app_path
    settings = {
      "TARGET_BUILD_DIR" => "/tmp/build/Release",
      "FULL_PRODUCT_NAME" => "MeetingCaptionTranslator.app"
    }

    assert_equal(
      "/tmp/build/Release/MeetingCaptionTranslator.app",
      BuildRelease.built_app_path_from_settings(settings)
    )
  end

  def test_built_app_path_from_settings_raises_when_target_build_dir_missing
    error = assert_raises(BuildRelease::BuildError) do
      BuildRelease.built_app_path_from_settings("FULL_PRODUCT_NAME" => "MeetingCaptionTranslator.app")
    end

    assert_equal("Missing build setting: TARGET_BUILD_DIR", error.message)
  end

  def test_copy_product_recreates_dist_and_removes_stale_contents
    Dir.mktmpdir do |root|
      built_app_path = File.join(root, "Build/Release/MeetingCaptionTranslator.app")
      FileUtils.mkdir_p(File.join(built_app_path, "Contents"))
      File.write(File.join(built_app_path, "Contents/Info.plist"), "bundle")

      dist_path = File.join(root, "dist")
      FileUtils.mkdir_p(dist_path)
      File.write(File.join(dist_path, "stale.txt"), "old")

      BuildRelease.copy_product(root: root, built_app_path: built_app_path)

      assert_equal ["MeetingCaptionTranslator.app"], Dir.children(dist_path)
      assert File.exist?(File.join(dist_path, "MeetingCaptionTranslator.app", "Contents", "Info.plist"))
      refute File.exist?(File.join(dist_path, "stale.txt"))
    end
  end

  def test_run_uses_repo_root_and_copies_product_from_settings
    Dir.mktmpdir do |outer_cwd|
      Dir.mktmpdir do |root|
        expected_root = File.realpath(root)
        app_path = File.join(root, "Build/Release/MeetingCaptionTranslator.app")
        FileUtils.mkdir_p(File.join(app_path, "Contents"))
        File.write(File.join(app_path, "Contents/Info.plist"), "bundle")

        runner = FakeRunner.new(
          build_status: Status.new(0),
          settings_output: <<~SETTINGS
            TARGET_BUILD_DIR = #{File.dirname(app_path)}
            FULL_PRODUCT_NAME = MeetingCaptionTranslator.app
          SETTINGS
        )

        Dir.chdir(outer_cwd) do
          result = BuildRelease.run(root: root, runner: runner)

          assert_equal 0, result
          assert_equal expected_root, runner.cwd_during_build
          assert_equal expected_root, runner.cwd_during_settings
          assert_equal ["xcodebuild", "build", "-project", "MeetingCaptionTranslator.xcodeproj", "-scheme", "MeetingCaptionTranslator", "-configuration", "Release", "-destination", "platform=macOS", "CODE_SIGNING_ALLOWED=NO"], runner.build_args
          assert_equal ["xcodebuild", "-showBuildSettings", "-project", "MeetingCaptionTranslator.xcodeproj", "-scheme", "MeetingCaptionTranslator", "-configuration", "Release", "-destination", "platform=macOS"], runner.capture_args
          assert_equal ["MeetingCaptionTranslator.app"], Dir.children(File.join(root, "dist"))
        end
      end
    end
  end

  def test_run_returns_build_exit_status_when_build_fails
    Dir.mktmpdir do |root|
      runner = FakeRunner.new(build_status: Status.new(42), settings_output: "")

      assert_equal 42, BuildRelease.run(root: root, runner: runner)
      assert_nil runner.capture_args
    end
  end

  def test_main_reports_build_error_without_stack_trace
    Dir.mktmpdir do |root|
      runner = Class.new do
        def run(*)
          raise BuildRelease::BuildError, "Missing build setting: TARGET_BUILD_DIR"
        end
      end.new
      stderr = StringIO.new

      exit_status = BuildRelease.main(root: root, runner: runner, io: stderr)

      assert_equal 1, exit_status
      assert_equal "Missing build setting: TARGET_BUILD_DIR\n", stderr.string
    end
  end
end

#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "minitest/autorun"
require_relative "build_release"

class BuildReleaseTest < Minitest::Test
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
end

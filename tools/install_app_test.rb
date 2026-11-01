# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "minitest/autorun"
require_relative "install_app"

class InstallAppTest < Minitest::Test
  def test_prepares_speech_and_model_before_build_and_install
    calls = []
    runner = ->(*args) { calls << args; true }
    status = InstallApp.main(
      root: "/repo", runner: runner,
      builder: -> { calls << [:build]; 0 },
      stopper: -> { calls << [:stop] },
      installer: ->(**) { calls << [:install] }
    )
    assert_equal 0, status
    assert_equal ["/repo/tools/build_speech.sh"], calls[0]
    assert_equal ["/repo/build/speech-native/speech", "pull", "haas-ja-v1.0"], calls[1]
    assert_equal ["/repo/build/speech-native/speech", "pull", "qwen3-asr-0.6b"], calls[2]
    assert_equal [[:build], [:stop], [:install]], calls.drop(3)
  end

  def test_failed_model_download_does_not_build_or_replace_app
    calls = []
    runner = ->(*args) { calls << args; calls.size == 1 }
    status = InstallApp.main(root: "/repo", runner: runner, builder: -> { flunk "build must not run" })
    assert_equal 1, status
    assert_equal 2, calls.size
  end

  def test_running_application_is_force_stopped_before_install
    processes = Class.new do
      attr_reader :signals
      def initialize
        @signals = []
      end
      def running_pids
        @signals.empty? ? [123] : []
      end
      def kill(pid)
        @signals << pid
      end
    end.new

    InstallApp.stop_running(processes: processes)
    assert_equal [123], processes.signals
  end

  def test_failure_to_stop_application_aborts_install
    processes = Class.new do
      def running_pids = [123]
      def kill(_pid) = nil
    end.new
    assert_raises(InstallApp::InstallError) do
      InstallApp.stop_running(processes: processes, timeout: 0)
    end
  end

  def test_installs_and_replaces_existing_bundle
    Dir.mktmpdir do |root|
      source = File.join(root, "source.app")
      destination = File.join(root, "Applications", "MeetingCaptionTranslator.app")
      FileUtils.mkdir_p([source, destination])
      File.write(File.join(source, "new"), "new")
      File.write(File.join(destination, "old"), "old")
      InstallApp.install(source: source, destination: destination)
      assert_equal "new", File.read(File.join(destination, "new"))
      refute File.exist?(File.join(destination, "old"))
    end
  end

  def test_missing_source_preserves_existing_bundle
    Dir.mktmpdir do |root|
      destination = File.join(root, "MeetingCaptionTranslator.app")
      FileUtils.mkdir_p(destination)
      File.write(File.join(destination, "old"), "old")
      assert_raises(InstallApp::InstallError) do
        InstallApp.install(source: File.join(root, "missing.app"), destination: destination)
      end
      assert_equal "old", File.read(File.join(destination, "old"))
    end
  end
end

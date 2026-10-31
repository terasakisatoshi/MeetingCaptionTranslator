# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "minitest/autorun"
require_relative "install_app"

class InstallAppTest < Minitest::Test
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

#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "build_release"

module InstallApp
  class InstallError < StandardError; end

  ROOT = File.expand_path("..", __dir__)
  APP_NAME = "MeetingCaptionTranslator.app"
  DESTINATION = File.join("/Applications", APP_NAME)

  class RunningProcesses
    def running_pids
      executable = File.join(DESTINATION, "Contents/MacOS/MeetingCaptionTranslator")
      output, status = Open3.capture2("/usr/bin/pgrep", "-f", "^#{Regexp.escape(executable)}($| )")
      raise InstallError, "Failed to check running applications" unless [0, 1].include?(status.exitstatus)

      output.lines.map { |line| Integer(line.strip) }
    end

    def kill(pid)
      Process.kill("KILL", pid)
    rescue Errno::ESRCH
      # The application has already exited.
    end
  end

  def self.stop_running(processes: RunningProcesses.new, timeout: 5)
    processes.running_pids.each { |pid| processes.kill(pid) }
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until processes.running_pids.empty?
      raise InstallError, "Could not stop MeetingCaptionTranslator" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.1
    end
  rescue SystemCallError => e
    raise InstallError, "Could not stop MeetingCaptionTranslator: #{e.message}"
  end

  def self.install(source:, destination:)
    raise InstallError, "Built app not found: #{source}" unless File.directory?(source)
    raise InstallError, "Destination is not a directory: #{destination}" if File.exist?(destination) && !File.directory?(destination)

    Dir.mktmpdir(".meeting-caption-install-", File.dirname(destination)) do |staging|
      new_app = File.join(staging, APP_NAME)
      backup = File.join(staging, "previous.app")
      raise InstallError, "Failed to copy app to #{staging}" unless system("/usr/bin/ditto", source, new_app)

      had_previous = File.exist?(destination)
      File.rename(destination, backup) if had_previous
      begin
        File.rename(new_app, destination)
      rescue StandardError
        File.rename(backup, destination) if had_previous
        raise
      end
    end
  rescue SystemCallError => e
    raise InstallError, "Installation failed: #{e.message}"
  end

  def self.main(root: ROOT, destination: DESTINATION, runner: ->(*args) { system(*args) },
                builder: -> { BuildRelease.run }, stopper: -> { stop_running },
                installer: ->(**args) { install(**args) })
    puts "Preparing speech.cpp..."
    raise InstallError, "speech.cpp build failed" unless runner.call(File.join(root, "tools", "build_speech.sh"))

    puts "Preparing Haas-ja model..."
    speech = File.join(root, "build", "speech-native", "speech")
    raise InstallError, "Haas-ja model download failed" unless runner.call(speech, "pull", "haas-ja-v1.0")

    puts "Preparing Qwen3-ASR model..."
    raise InstallError, "Qwen3-ASR model download failed" unless runner.call(speech, "pull", "qwen3-asr-0.6b")

    status = builder.call
    return status unless status.zero?

    stopper.call
    installer.call(source: File.join(root, "dist", APP_NAME), destination: destination)
    puts "Installed #{destination}"
    0
  rescue InstallError, BuildRelease::BuildError => e
    warn e.message
    1
  end
end

exit InstallApp.main if $PROGRAM_NAME == __FILE__

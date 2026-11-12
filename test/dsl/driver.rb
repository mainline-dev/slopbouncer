# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

# Drives the real command line against a throwaway git repository: writes
# files, commits them, and runs bin/slopbouncer over a range of commits.
class Driver
  BIN = File.expand_path('../../bin/slopbouncer', __dir__)

  Run = Struct.new(:findings, :status, :output, keyword_init: true)

  def initialize
    @dir = Dir.mktmpdir('slopbouncer')
    git('init', '-q', '-b', 'main')
    git('config', 'user.email', 'test@example.com')
    git('config', 'user.name', 'Test')
    git('commit', '-q', '--allow-empty', '-m', 'start')
  end

  def remove
    FileUtils.remove_entry(@dir)
  end

  # Writes the files (path => source, or nil to delete) and commits them.
  def commit(files)
    files.each do |path, source|
      full = File.join(@dir, path)
      next FileUtils.rm_f(full) if source.nil?

      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, source)
    end
    git('add', '-A')
    git('commit', '-q', '--allow-empty', '-m', 'change')
    git('rev-parse', 'HEAD').strip
  end

  def move(from, to)
    FileUtils.mkdir_p(File.dirname(File.join(@dir, to)))
    git('mv', from, to)
    git('commit', '-q', '-m', 'move')
  end

  def write(path, source)
    File.write(File.join(@dir, path), source)
  end

  def slopbouncer(*arguments)
    output, status = Open3.capture2e(RbConfig.ruby, BIN, *arguments, chdir: @dir)
    Run.new(findings: findings_in(output), status: status.exitstatus, output: output)
  end

  private

  def findings_in(output)
    JSON.parse(output)
  rescue JSON::ParserError
    nil
  end

  def git(*arguments)
    output, status = Open3.capture2e('git', *arguments, chdir: @dir)
    raise "git #{arguments.join(' ')} failed: #{output}" unless status.success?

    output
  end
end

# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'pty'
require 'tmpdir'

# Drives the real command line against a throwaway git repository: writes
# files, commits them, and runs bin/slopbouncer over a range of commits.
class Driver
  BIN = File.expand_path('../../bin/slopbouncer', __dir__)

  Run = Struct.new(:findings, :status, :output, :error, keyword_init: true)

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
    FileUtils.mkdir_p(File.dirname(File.join(@dir, path)))
    File.write(File.join(@dir, path), source)
  end

  def read(path)
    File.read(File.join(@dir, path))
  end

  def exists?(path)
    File.exist?(File.join(@dir, path))
  end

  # Runs a command line through a shell in the repository, with the
  # slopbouncer command on the path as an installed gem would put it.
  def shell(command, input: '')
    path = "#{File.dirname(BIN)}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}"
    output, error, status = Open3.capture3({ 'PATH' => path }, 'sh', '-c', command, chdir: @dir, stdin_data: input)
    Run.new(findings: nil, status: status.exitstatus, output: output, error: error)
  end

  # Runs the command in a terminal of its own, as a person at a prompt does,
  # and gives back what the terminal showed.
  def terminal(*arguments, environment: {})
    shown = +''
    PTY.spawn(environment, RbConfig.ruby, BIN, *arguments, chdir: @dir) do |screen, _keys, pid|
      begin
        loop { shown << screen.readpartial(4096) }
      rescue EOFError, Errno::EIO
        nil
      end
      Process.wait(pid)
    end
    shown.force_encoding(Encoding::UTF_8).gsub("\r\n", "\n")
  end

  def root
    File.realpath(@dir)
  end

  def slopbouncer(*arguments, input: '', from: @dir)
    output, error, status = Open3.capture3(RbConfig.ruby, BIN, *arguments, chdir: from, stdin_data: input)
    Run.new(findings: findings_in(output), status: status.exitstatus, output: output, error: error)
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

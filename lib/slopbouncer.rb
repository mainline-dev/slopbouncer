# frozen_string_literal: true

require 'json'
require 'yaml'
require_relative 'slopbouncer/git'
require_relative 'slopbouncer/ruby_tests'
require_relative 'slopbouncer/compare'

# A static check that flags tests which got weaker in a change, so a person
# can decide whether that was intended.
module Slopbouncer
  class Error < StandardError; end

  # A project's own settings, in the directory the command is run from:
  #   assertions: the names of its helper methods that count as assertions.
  CONFIG = '.slopbouncer.yml'

  TEST_FILE = %r{(\A|/)(test|spec)/.*\.rb\z|(\A|/)(test_[^/]*|[^/]*_(test|spec))\.rb\z}

  USAGE = 'Give a range of commits, such as main..HEAD, or one commit to compare the working tree with, such as HEAD'

  # The findings for the commits in a range such as main..HEAD, or for
  # everything since one commit, committed or not, when given just that.
  def self.check(target)
    base, head = target.split('..', 2)
    raise Error, USAGE if base.to_s.empty? || (target.include?('..') && head.to_s.empty?)

    helpers = settings.fetch('assertions', [])
    results = Git.changed(base, head).filter_map do |changed|
      next unless [changed.before_path, changed.after_path].compact.all? { |path| path.match?(TEST_FILE) }

      before = changed.before_path ? RubyTests.in(Git.show(base, changed.before_path), helpers: helpers) : []
      after = changed.after_path ? RubyTests.in(Git.show(head, changed.after_path), helpers: helpers) : []
      [changed.after_path || changed.before_path, Compare.call(changed.after_path || changed.before_path, before, after)]
    end
    results.flat_map { |_file, result| result.findings } + deleted(results)
  end

  # A test that has gone from one file is deleted unless the same test, body
  # for body, is new in another file of the same change.
  def self.deleted(results)
    moved = results.flat_map { |_file, result| result.fresh.map(&:body) }
    results.flat_map do |file, result|
      result.gone.reject { |test| moved.include?(test.body) }.map { |test| Compare.deleted(file, test) }
    end
  end

  def self.settings
    File.exist?(CONFIG) ? YAML.safe_load_file(CONFIG) || {} : {}
  rescue Psych::Exception => e
    raise Error, "#{CONFIG} could not be read: #{e.message}"
  end

  def self.run(arguments, input: $stdin)
    target = arguments.find { |argument| !argument.start_with?('--') }
    return stop_hook(target.to_s, input) if arguments.include?('--agent')

    findings = check(target.to_s)
    puts arguments.include?('--json') ? JSON.pretty_generate(findings.map { |finding| finding.to_h.compact }) : report(findings)
    arguments.include?('--strict') && findings.any? ? 1 : 0
  rescue Error => e
    warn e.message
    2
  end

  # Run as a coding agent's stop hook. The agent is stopped from finishing
  # once, with what it weakened on standard error, where its harness reads
  # the reason from. Exit status 2 is what tells the harness to stop it.
  def self.stop_hook(target, input)
    return 0 if stopped_before?(input)

    findings = check(target)
    return 0 if findings.empty?

    warn to_the_agent(findings)
    2
  rescue Error => e
    warn e.message
    0
  end

  # The harness says on standard input whether this hook has already made
  # the agent carry on once.
  def self.stopped_before?(input)
    text = input.tty? ? '' : input.read.to_s
    !text.strip.empty? && JSON.parse(text)['stop_hook_active'] == true
  rescue JSON::ParserError
    false
  end

  def self.to_the_agent(findings)
    <<~MESSAGE
      Slopbouncer: this change weakens #{findings.size} existing #{findings.size == 1 ? 'test' : 'tests'}.

      #{report(findings)}

      For each one, do one of two things before you finish:
      1. Put the test back as it was, and make the code pass it.
      2. Leave the change, and tell the person which behaviour changed and why the test had to change with it.
    MESSAGE
  end

  def self.report(findings)
    findings.map { |finding|
      what = finding.before ? "#{finding.before} → #{finding.after}" : finding.detail
      "#{finding.file}: #{finding.test}: #{finding.rule}: #{what}"
    }.join("\n")
  end
  private_class_method :deleted, :settings, :stop_hook, :stopped_before?, :to_the_agent
end

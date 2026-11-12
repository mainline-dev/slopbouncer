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

  # The findings for the commits in a range such as main..HEAD.
  def self.check(range)
    base, head = range.split('..', 2)
    raise Error, 'Give a range of commits, such as main..HEAD' if base.to_s.empty? || head.to_s.empty?

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

  def self.run(arguments)
    range = arguments.find { |argument| !argument.start_with?('--') }
    findings = check(range.to_s)
    puts arguments.include?('--json') ? JSON.pretty_generate(findings.map { |finding| finding.to_h.compact }) : report(findings)
    arguments.include?('--strict') && findings.any? ? 1 : 0
  rescue Error => e
    warn e.message
    2
  end

  def self.report(findings)
    findings.map { |finding|
      what = finding.before ? "#{finding.before} → #{finding.after}" : finding.detail
      "#{finding.file}: #{finding.test}: #{finding.rule}: #{what}"
    }.join("\n")
  end
  private_class_method :deleted, :settings
end

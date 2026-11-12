# frozen_string_literal: true

module Slopbouncer
  # The findings laid out for a person at a terminal: each file once, the
  # tests flagged in it underneath, each rule with its detail under its test,
  # and a count at the end. Colour is optional; the layout is the same without.
  # Past LIMIT findings it gives a count of each rule in each file, unless
  # asked for them all.
  module TerminalReport
    LIMIT = 30
    BOLD = 1
    RED = 31
    GREEN = 32
    YELLOW = 33
    # Red for a check that has gone, yellow for one that was changed or switched off.
    COLOURS = { 'test_deleted' => RED, 'assertion_removed' => RED, 'no_assertions' => RED,
                'expected_value_changed' => YELLOW, 'skip_added' => YELLOW }.freeze

    def self.call(findings, colour:, all: false)
      paint = ->(text, code) { colour ? "\e[#{code}m#{text}\e[0m" : text }
      return paint.call('No tests got weaker.', GREEN) if findings.empty?

      files = findings.group_by(&:file)
      tests = files.sum { |_file, found| found.map(&:test).uniq.size }
      return [*files.map { |file, found| file(file, found, paint) }, count(tests, files.size)].join("\n\n") if all || findings.size <= LIMIT

      [*files.map { |file, found| counted(file, found, paint) }, "#{count(tests, files.size)}\n--all lists every finding."].join("\n\n")
    end

    # A file with how many times each rule was broken in it.
    def self.counted(file, found, paint)
      [paint.call(file, BOLD), *found.group_by(&:rule).map { |rule, broken| "  #{rule(rule, paint)}  #{broken.size}" }].join("\n")
    end

    def self.rule(rule, paint)
      paint.call(rule, COLOURS.fetch(rule, YELLOW))
    end

    def self.file(file, found, paint)
      tests = found.group_by(&:test).flat_map do |test, about|
        ["  #{test}", *about.map { |finding| "    #{rule(finding.rule, paint)}  #{detail(finding)}" }]
      end
      [paint.call(file, BOLD), *tests].join("\n")
    end

    def self.detail(finding)
      finding.before ? "#{finding.before} → #{finding.after}" : finding.detail
    end

    def self.count(tests, files)
      "#{tests} #{tests == 1 ? 'test' : 'tests'} got weaker in #{files} #{files == 1 ? 'file' : 'files'}"
    end
    private_class_method :counted, :rule, :file, :detail, :count
  end
end

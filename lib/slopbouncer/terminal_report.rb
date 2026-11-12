# frozen_string_literal: true

module Slopbouncer
  # The findings laid out for a person at a terminal: each file once, the
  # tests flagged in it underneath, each rule with its detail under its test,
  # and a count at the end. Colour is optional; the layout is the same without.
  module TerminalReport
    BOLD = 1
    RED = 31
    GREEN = 32
    YELLOW = 33
    # Red for a check that has gone, yellow for one that was changed or switched off.
    COLOURS = { 'test_deleted' => RED, 'assertion_removed' => RED, 'no_assertions' => RED,
                'expected_value_changed' => YELLOW, 'skip_added' => YELLOW }.freeze

    def self.call(findings, colour:)
      paint = ->(text, code) { colour ? "\e[#{code}m#{text}\e[0m" : text }
      return paint.call('No tests got weaker.', GREEN) if findings.empty?

      files = findings.group_by(&:file)
      tests = files.sum { |_file, found| found.map(&:test).uniq.size }
      [*files.map { |file, found| file(file, found, paint) }, count(tests, files.size)].join("\n\n")
    end

    def self.file(file, found, paint)
      tests = found.group_by(&:test).flat_map do |test, about|
        ["  #{test}", *about.map { |finding| "    #{paint.call(finding.rule, COLOURS.fetch(finding.rule, YELLOW))}  #{detail(finding)}" }]
      end
      [paint.call(file, BOLD), *tests].join("\n")
    end

    def self.detail(finding)
      finding.before ? "#{finding.before} → #{finding.after}" : finding.detail
    end

    def self.count(tests, files)
      "#{tests} #{tests == 1 ? 'test' : 'tests'} got weaker in #{files} #{files == 1 ? 'file' : 'files'}"
    end
    private_class_method :file, :detail, :count
  end
end

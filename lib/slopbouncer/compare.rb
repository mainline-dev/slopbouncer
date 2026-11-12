# frozen_string_literal: true

module Slopbouncer
  # Compares a test file's table of tests before and after a change and says
  # which tests got weaker. Tests that are new are never flagged. It cannot
  # tell a stronger assertion from a weaker one, so an assertion swapped for
  # another kind is reported as removed, for a person to judge.
  module Compare
    Finding = Struct.new(:file, :test, :rule, :detail, :before, :after, keyword_init: true)
    Result = Struct.new(:findings, :gone, :fresh, keyword_init: true)

    # A reworded test is the same test: one that has gone is taken to be a
    # new one when at least this share of their body lines are the same.
    SAME_TEST = 0.5

    # gone: tests no longer in the file. fresh: tests that are new to it.
    # The caller decides whether a gone test turned up in another file.
    def self.call(file, before, after)
      now = after.to_h { |test| [test.name, test] }
      gone = before.reject { |test| now.key?(test.name) }
      fresh = after.reject { |test| before.any? { |was| was.name == test.name } }
      reworded = reworded(gone, fresh)
      pairs = before.filter_map { |was| [was, now[was.name]] if now.key?(was.name) } + reworded
      Result.new(findings: pairs.flat_map { |was, test| weaker(file, was, test) },
        gone: gone - reworded.map(&:first), fresh: fresh - reworded.map(&:last))
    end

    def self.deleted(file, test)
      Finding.new(file: file, test: test.name, rule: 'test_deleted', detail: "#{test.assertions.size} assertions")
    end

    # Pairs each test that has gone with the new test most like it.
    def self.reworded(gone, fresh)
      left = fresh.dup
      gone.filter_map do |was|
        match = left.max_by { |test| likeness(was, test) }
        next unless match && likeness(was, match) >= SAME_TEST

        left.delete(match)
        [was, match]
      end
    end

    def self.likeness(was, now)
      shared = (was.body & now.body).size
      total = [was.body.size, now.body.size].max
      total.zero? ? 0.0 : shared.to_f / total
    end

    def self.weaker(file, was, now)
      finding = ->(rule, **rest) { Finding.new(file: file, test: now.name, rule: rule, **rest) }
      lost = was.assertions.reject { |assertion| now.assertions.map(&:source).include?(assertion.source) }
      gained = now.assertions.reject { |assertion| was.assertions.map(&:source).include?(assertion.source) }
      found = lost.map do |assertion|
        edit = gained.find { |other| edited_value(assertion, other) }
        next finding.call('assertion_removed', detail: assertion.source) unless edit

        gained.delete(edit)
        before, after = edited_value(assertion, edit)
        finding.call('expected_value_changed', detail: edit.source, before: before, after: after)
      end
      found << finding.call('skip_added', detail: 'marked to be skipped') if now.skipped && !was.skipped
      found << finding.call('no_assertions', detail: 'asserts nothing') if now.assertions.empty? && was.body != now.body
      found
    end

    # The one argument that differs between two calls of the same assertion,
    # as [before, after], when everything else about them is the same.
    def self.edited_value(was, now)
      return unless was.method == now.method && was.arguments.size == now.arguments.size

      differing = was.arguments.zip(now.arguments).reject { |before, after| before == after }
      differing.first if differing.size == 1
    end
    private_class_method :reworded, :likeness, :weaker, :edited_value
  end
end

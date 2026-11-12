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
      named = same_name(before, after)
      gone = without(before, named.map(&:first))
      fresh = without(after, named.map(&:last))
      reworded = reworded(gone, fresh)
      Result.new(findings: (named + reworded).flat_map { |was, test| weaker(file, was, test) },
        gone: without(gone, reworded.map(&:first)), fresh: without(fresh, reworded.map(&:last)))
    end

    # Pairs each test with the test of the same name after the change. A
    # file can hold several tests with one name: those are paired with the
    # one whose body is unchanged if there is one, and otherwise in the
    # order they appear, first with first.
    def self.same_name(before, after)
      waiting = after.group_by(&:name)
      unchanged = before.filter_map { |was| pair(was, waiting) { |test| test.body == was.body } }
      rest = without(before, unchanged.map(&:first)).filter_map { |was| pair(was, waiting) { true } }
      (unchanged + rest).sort_by { |was, _| before.index { |test| test.equal?(was) } }
    end

    # Takes the first waiting test of this name that fits, if any.
    def self.pair(was, waiting)
      candidates = waiting.fetch(was.name, [])
      place = candidates.index { |test| yield test }
      [was, candidates.delete_at(place)] if place
    end

    # The tests that are not, one for one, among those taken. Two tests can
    # be alike in every way and still be two tests.
    def self.without(tests, taken)
      tests.reject { |test| taken.any? { |other| other.equal?(test) } }
    end

    def self.deleted(file, test)
      Finding.new(file: file, test: test.name, rule: 'test_deleted', detail: "#{test.assertions.size} assertions")
    end

    # Pairs each test that has gone with the new test most like it.
    def self.reworded(gone, fresh)
      left = fresh.dup
      gone.filter_map do |was|
        match = left.max_by { |test| likeness(was, test) }
        match = left.find { |test| one_edit?(was, test) } unless match && likeness(was, match) >= SAME_TEST
        next unless match

        left.delete_at(left.index { |test| test.equal?(match) })
        [was, match]
      end
    end

    # A one-line test whose only assertion had one value edited is the same
    # test. This is how a test with no name of its own is followed:
    # it { is_expected.to eq(5) } edited to expect 6.
    def self.one_edit?(was, now)
      [was, now].all? { |test| test.body.size == 1 && test.assertions.size == 1 } &&
        !edited_value(was.assertions.first, now.assertions.first).nil?
    end

    def self.likeness(was, now)
      shared = (was.body & now.body).size
      total = [was.body.size, now.body.size].max
      total.zero? ? 0.0 : shared.to_f / total
    end

    def self.weaker(file, was, now)
      finding = ->(rule, **rest) { Finding.new(file: file, test: now.name, rule: rule, **rest) }
      lost = was.assertions.reject { |assertion| now.assertions.map(&:form).include?(assertion.form) }
      gained = now.assertions.reject { |assertion| was.assertions.map(&:form).include?(assertion.form) }
      found = lost.map do |assertion|
        edit = gained.find { |other| edited_value(assertion, other) }
        next finding.call('assertion_removed', detail: assertion.source) unless edit

        gained.delete(edit)
        before, after = edited_value(assertion, edit)
        finding.call('expected_value_changed', detail: edit.source, before: before, after: after)
      end
      found << finding.call('skip_added', detail: 'marked to be skipped') if now.skipped && !was.skipped
      found << finding.call('no_assertions', detail: 'asserts nothing') if asserts_nothing?(now) && was.body != now.body
      found
    end

    # A test with no assertions of its own still asserts when a hook in its
    # group does it for it.
    def self.asserts_nothing?(test)
      test.assertions.empty? && !test.hooked
    end

    # The one argument that differs between two calls of the same assertion,
    # as [before, after], when everything else about them is the same.
    def self.edited_value(was, now)
      return unless was.method == now.method && was.arguments.size == now.arguments.size

      differing = was.forms.each_index.reject { |place| was.forms[place] == now.forms[place] }
      [was.arguments[differing.first], now.arguments[differing.first]] if differing.size == 1
    end
    private_class_method :same_name, :pair, :without, :reworded, :one_edit?, :likeness, :weaker, :asserts_nothing?, :edited_value
  end
end

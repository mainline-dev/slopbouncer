# frozen_string_literal: true

require_relative '../dsl/dsl'

# One mechanical rewrite can weaken a thousand tests at once. Past 30
# findings a person at a terminal gets a count for each file, and a coding
# agent gets the first 20. Anything a program reads is always complete.
describe 'a report too long to read' do
  include SlopbouncerDSL

  # A file of numbered tests, each making two assertions.
  def tests(count, lines)
    "describe 'Basket' do\n#{(1..count).map { |number| "  it 'holds item #{number}' do\n#{lines.call(number)}  end\n" }.join}end\n"
  end

  # Every test loses its second assertion, and the first few have the value
  # they expect edited as well.
  def weaken(count, edited: 0)
    given tests(count, ->(number) { "    assert_equal #{number}, item\n    assert_equal 1, size\n" })
    change tests(count, ->(number) { "    assert_equal #{number <= edited ? 0 : number}, item\n" })
  end

  def lines_shown(*flags)
    shown_in_a_terminal(*flags).gsub(/\e\[[\d;]*m/, '').lines.map(&:strip)
  end

  it 'gives a person, past 30 findings, each file once with a count for each rule, and says how to see them all' do
    weaken(31, edited: 2)
    lines = lines_shown

    assert_equal 1, lines.count(the_test_file)
    assert_includes lines, 'assertion_removed  31'
    assert_includes lines, 'expected_value_changed  2'
    assert_empty lines.grep(/holds item/)
    assert_equal %w[31 1], lines.grep(/\A\d+ tests? /).first.scan(/\d+/)
    assert_includes lines.last, '--all'
  end

  it 'lists every finding for a person who asks for them all' do
    weaken(31)
    lines = lines_shown('--all')

    assert_equal 31, lines.grep(/\ABasket holds item \d+\z/).size
    assert_equal 31, lines.grep(/\Aassertion_removed  assert_equal 1, size\z/).size
  end

  it 'still lists 30 findings in full' do
    weaken(30)

    assert_equal 30, lines_shown.grep(/\ABasket holds item \d+\z/).size
  end

  it 'is always complete when sent to another program, as lines or as JSON' do
    weaken(31)

    assert_equal 31, piped.lines.size
    assert_equal 31, findings.size
  end

  it 'gives a coding agent the first 20, how many more there are, and the command that lists them all' do
    weaken(31)
    message = as_the_agents_stop_hook.error

    assert_equal 20, message.lines.grep(/\A#{Regexp.escape(the_test_file)}: /).size
    assert_includes message, 'holds item 20:'
    refute_includes message, 'holds item 21:'
    assert_match(/\b11 more\b/, message)
    assert_match(/slopbouncer \h{40}\b/, message)
  end

  it 'gives a coding agent every finding when there are 20 or fewer, with nothing about more' do
    weaken(20)
    message = as_the_agents_stop_hook.error

    assert_equal 20, message.lines.grep(/\A#{Regexp.escape(the_test_file)}: /).size
    refute_match(/\bmore\b/, message)
  end
end

# frozen_string_literal: true

require_relative '../dsl/dsl'

# At a terminal the findings are laid out for a person: each file once, its
# tests under it, the rule in colour, and a count at the end. Sent to another
# program they stay one plain line each.
describe 'the report at a terminal' do
  include SlopbouncerDSL

  COLOUR = "\e["

  def basket(*tests)
    "describe 'Basket' do\n#{tests.join}end\n"
  end

  def spec(name, *lines)
    "  it '#{name}' do\n#{lines.map { |line| "    #{line}\n" }.join}  end\n"
  end

  # Two tests weakened in one file, and one deleted from another.
  def three_tests_weakened_in_two_files
    given('test/test_basket.rb'   => basket(spec('adds up', 'assert_equal 5, total', 'assert_equal 2, size'), spec('is priced', 'assert_equal 9, price')),
          'test/test_checkout.rb' => basket(spec('takes payment', 'assert paid')))
    change('test/test_basket.rb'   => basket(spec('adds up', 'assert_equal 5, total'), spec('is priced', 'assert_equal 8, price')),
           'test/test_checkout.rb' => basket)
  end

  def plain(text)
    text.gsub(/\e\[[\d;]*m/, '')
  end

  it 'names each file once, with the tests flagged in it underneath' do
    three_tests_weakened_in_two_files
    lines = plain(shown_in_a_terminal).lines.map(&:strip)

    assert_equal 1, lines.count('test/test_basket.rb')
    assert_operator lines.index('test/test_basket.rb'), :<, lines.index('Basket adds up')
    assert_operator lines.index('Basket adds up'), :<, lines.index('Basket is priced')
    assert_operator lines.index('test/test_checkout.rb'), :<, lines.index('Basket takes payment')
  end

  it 'puts each rule and its detail under the test it is about' do
    three_tests_weakened_in_two_files
    lines = plain(shown_in_a_terminal).lines.map(&:strip)

    assert_equal 'assertion_removed  assert_equal 2, size', lines[lines.index('Basket adds up') + 1]
    assert_equal 'expected_value_changed  9 → 8', lines[lines.index('Basket is priced') + 1]
  end

  it 'is in colour' do
    three_tests_weakened_in_two_files

    assert_includes shown_in_a_terminal, COLOUR
  end

  it 'ends by counting the tests that got weaker and the files they are in' do
    three_tests_weakened_in_two_files

    assert_equal %w[3 2], plain(shown_in_a_terminal).lines.last.scan(/\d+/)
  end

  it 'keeps its layout and drops the colour for a person who has asked for none' do
    three_tests_weakened_in_two_files
    shown = shown_in_a_terminal(environment: { 'NO_COLOR' => '1' })

    refute_includes shown, COLOUR
    assert_equal 1, shown.lines.map(&:strip).count('test/test_basket.rb')
  end

  it 'says so when nothing got weaker, and does not leave the screen blank' do
    given basket(spec('adds up', 'assert_equal 5, total'))
    change basket(spec('adds up', 'assert_equal 5, total', 'assert_equal 2, size'))

    assert_match(/\w/, plain(shown_in_a_terminal))
  end
end

describe 'the report sent to another program' do
  include SlopbouncerDSL

  def weakened
    given "describe 'Basket' do\n  it 'adds' do\n    assert_equal 1, 1\n    assert true\n  end\nend\n"
    change "describe 'Basket' do\n  it 'adds' do\n    assert true\n  end\nend\n"
  end

  it 'stays one plain line for each finding, with no colour' do
    weakened

    assert_equal ["#{the_test_file}: Basket adds: assertion_removed: assert_equal 1, 1\n"], piped.lines
  end

  it 'is laid out as at a terminal when asked for colour, for a script whose own output a person reads' do
    weakened
    lines = piped('--color').lines.map(&:strip)

    assert_includes piped('--color'), "\e["
    assert_equal 1, lines.count { |line| line.include?(the_test_file) }
    refute_includes lines, "#{the_test_file}: Basket adds: assertion_removed: assert_equal 1, 1"
  end

  it 'is not coloured as JSON, whatever is asked' do
    weakened

    refute_includes piped('--json', '--color'), "\e["
  end
end

# frozen_string_literal: true

require_relative '../dsl/dsl'

describe 'a project with its own assertion helpers' do
  include SlopbouncerDSL

  def page_test(body)
    "describe 'Checkout' do\n  it 'shows the total' do\n#{body.gsub(/^/, '    ')}\n  end\nend\n"
  end

  it 'has a helper counted as an assertion once the project names it' do
    configure "assertions:\n  - sees_total\n"
    given page_test("visit_checkout\nsees_total 5\nsees_total 2")
    change page_test("visit_checkout\nsees_total 5")

    assert_equal [['Checkout shows the total', 'assertion_removed']], flagged
  end

  it 'takes a helper nobody named for an ordinary step, and so sees a test that asserts nothing' do
    given page_test("visit_checkout\nsees_total 5\nsees_total 2")
    change page_test("visit_checkout\nsees_total 5")

    assert_equal [['Checkout shows the total', 'no_assertions']], flagged
  end

  it 'does not say a test of helpers asserts nothing once its helpers are named' do
    configure "assertions:\n  - sees_total\n"
    given page_test("visit_checkout\nsees_total 5")
    change page_test("visit_the_checkout\nsees_total 5")

    assert_empty flagged
  end
end

describe 'tests that only moved' do
  include SlopbouncerDSL

  it 'does not flag a test cut from one file and pasted into another' do
    test = "  it 'adds up' do\n    assert_equal 5, Basket.new(2, 3).total\n  end\n"
    given('test/test_basket.rb' => "describe 'Basket' do\n#{test}end\n", 'test/test_totals.rb' => "describe 'Totals' do\nend\n")
    change('test/test_basket.rb' => "describe 'Basket' do\nend\n", 'test/test_totals.rb' => "describe 'Totals' do\n#{test}end\n")

    assert_empty flagged
  end

  it 'leaves alone a test with no assertions that the change did not touch' do
    quiet = "  it 'runs' do\n    Basket.new\n  end\n"
    given "describe 'Basket' do\n#{quiet}  it 'adds' do\n    assert_equal 1, 1\n  end\nend\n"
    change "describe 'Basket' do\n#{quiet}  it 'adds' do\n    assert_equal 1, 1\n    assert true\n  end\nend\n"

    assert_empty flagged
  end
end

describe 'the command' do
  include SlopbouncerDSL

  def weakened
    given "describe 'Basket' do\n  it 'adds' do\n    assert_equal 1, 1\n    assert true\n  end\nend\n"
    change "describe 'Basket' do\n  it 'adds' do\n    assert true\n  end\nend\n"
  end

  it 'flags without failing, so a person decides' do
    weakened

    assert_equal 0, run_slopbouncer.status
  end

  it 'fails when asked to be strict and something is flagged' do
    weakened

    assert_equal 1, run_slopbouncer('--strict').status
  end

  it 'passes when asked to be strict and nothing is flagged' do
    given "describe 'Basket' do\nend\n"
    change "describe 'Basket' do\n  it 'adds' do\n    assert true\n  end\nend\n"

    assert_equal 0, run_slopbouncer('--strict').status
  end

  it 'prints one line for each finding, naming its file, when not asked for JSON' do
    weakened

    lines = plain_report.lines

    assert_equal 1, lines.size
    assert_includes lines.first, test_file
  end

  it 'says what an edited value was and what it is now' do
    given "describe 'Refund' do\n  it 'refunds part' do\n    assert_equal 100, refund.amount\n  end\nend\n"
    change "describe 'Refund' do\n  it 'refunds part' do\n    assert_equal 90, refund.amount\n  end\nend\n"

    assert_match(/expected_value_changed: 100 → 90\z/, plain_report.strip)
  end

  it 'says so and stops when not given a range of commits' do
    assert_equal 2, slopbouncer_with('HEAD').status
  end

  it 'reads a test file it cannot fully parse as far as it can, without stopping' do
    given "describe 'Basket' do\n  it 'adds' do\n    assert_equal 1, 1\n    assert true\n  end\nend\n"
    change "describe 'Basket' do\n  it 'adds' do\n    assert true\n  end\n"

    assert_equal 0, run_slopbouncer.status
  end
end

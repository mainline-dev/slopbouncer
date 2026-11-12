# frozen_string_literal: true

require_relative '../dsl/dsl'

# A formatter rewrites how a test is written and changes nothing it checks.
# Two assertions are the same when they parse to the same thing.
describe 'a test that was only reformatted' do
  include SlopbouncerDSL

  def order_test(*lines)
    "describe 'Order' do\n  it 'is paid' do\n#{lines.map { |line| "    #{line}\n" }.join}  end\nend\n"
  end

  def order_spec(*lines)
    { 'spec/order_spec.rb' => "RSpec.describe Order do\n  it 'is paid' do\n#{lines.map { |line| "    #{line}\n" }.join}  end\nend\n" }
  end

  def edited
    findings.map { |finding| finding.values_at('rule', 'before', 'after') }
  end

  it 'is not flagged when only the quotes round an expected string change' do
    given order_test("assert_equal 'paid', order.status")
    change order_test('assert_equal "paid", order.status')

    assert_empty flagged
  end

  it 'is not flagged when an expected string is written with %q' do
    given order_test("assert_equal 'paid', order.status")
    change order_test('assert_equal %q(paid), order.status')

    assert_empty flagged
  end

  it 'is not flagged when a line break moves inside a chained expectation' do
    given order_spec('expect(order.lines.first.status).', '  to eq(5)')
    change order_spec('expect(order.lines.first.status)', '  .to eq(5)')

    assert_empty flagged
  end

  it 'is not flagged when parentheses are added round an assertion\'s arguments' do
    given order_test("assert_equal 'paid', order.status")
    change order_test("assert_equal('paid', order.status)")

    assert_empty flagged
  end

  it 'is not flagged when a block changes from braces to do and end' do
    given order_test('assert_raises(Declined) { order.pay }')
    change order_test('assert_raises(Declined) do', '  order.pay', 'end')

    assert_empty flagged
  end

  it 'is not flagged when a comma is added after the last argument' do
    given order_test('assert_includes(', "  %w[paid refunded], order.status", ')')
    change order_test('assert_includes(', '  %w[paid refunded],', '  order.status,', ')')

    assert_empty flagged
  end

  it 'is still flagged when the quotes and the value both change, showing both as written' do
    given order_test("assert_equal 'paid', order.status")
    change order_test('assert_equal "refunded", order.status')

    assert_equal [['expected_value_changed', "'paid'", '"refunded"']], edited
  end

  it 'is still flagged when the braces round a trailing hash are taken away' do
    given order_test("assert_equal({ status: 'paid' }, order.to_h)")
    change order_test("assert_equal(status: 'paid')")

    assert_equal [['Order is paid', 'assertion_removed']], flagged
  end

  it 'is still flagged when a pattern stops ignoring case' do
    given order_test('assert_match(/paid/i, order.status)')
    change order_test('assert_match(/paid/, order.status)')

    assert_equal [['expected_value_changed', '/paid/i', '/paid/']], edited
  end
end

# frozen_string_literal: true

require_relative '../dsl/dsl'

# Nothing stops a file holding two tests with the same full name. They are
# told apart by where they are: the first before the change is the first
# after it.
describe 'two tests with the same name in one file' do
  include SlopbouncerDSL

  def twins(first: "assert_equal 5, total\n    assert_equal 2, size", second: 'assert_equal 9, price', note: 'adds things up')
    <<~RUBY
      describe 'Basket' do
        # #{note}
        it 'adds' do
          #{first}
        end

        it 'adds' do
          #{second}
        end
      end
    RUBY
  end

  def one(body)
    "describe 'Basket' do\n  it 'adds' do\n    #{body}\n  end\nend\n"
  end

  it 'are not flagged when a comment elsewhere in the file changes' do
    given twins
    change twins(note: 'adds things up, twice')

    assert_empty flagged
  end

  it 'are flagged once when the first loses an assertion, with nothing said of the second' do
    given twins
    change twins(first: 'assert_equal 5, total')

    assert_equal [['Basket adds', 'assertion_removed']], flagged
    assert_equal ['assert_equal 2, size'], findings.map { |finding| finding['detail'] }
  end

  it 'are flagged once when the second loses an assertion' do
    given twins(second: "assert_equal 9, price\n    assert_equal 1, count")
    change twins(second: 'assert_equal 9, price')

    assert_equal ['assert_equal 1, count'], findings.map { |finding| finding['detail'] }
  end

  it 'give one deleted test when the second of them is deleted' do
    given twins
    change one("assert_equal 5, total\n    assert_equal 2, size")

    assert_equal [['Basket adds', 'test_deleted']], flagged
  end

  it 'give one deleted test when the first of them is deleted' do
    given twins
    change one('assert_equal 9, price')

    assert_equal [['Basket adds', 'test_deleted']], flagged
  end
end

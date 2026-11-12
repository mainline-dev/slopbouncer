# frozen_string_literal: true

require_relative '../dsl/dsl'

describe 'a test that got weaker' do
  include SlopbouncerDSL

  it 'is flagged when an assertion is removed from it' do
    given <<~RUBY
      describe 'Basket' do
        it 'adds up the items' do
          basket = Basket.new(2, 3)
          assert_equal 5, basket.total
          assert_equal 2, basket.size
        end
      end
    RUBY

    change <<~RUBY
      describe 'Basket' do
        it 'adds up the items' do
          basket = Basket.new(2, 3)
          assert_equal 5, basket.total
        end
      end
    RUBY

    assert_equal [['Basket adds up the items', 'assertion_removed']], flagged
  end

  it 'is not flagged when a test is added along with new code' do
    given(the_test_file => <<~RUBY, 'lib/basket.rb' => "class Basket; end\n")
      describe 'Basket' do
        it 'adds up the items' do
          assert_equal 5, Basket.new(2, 3).total
        end
      end
    RUBY

    change(the_test_file => <<~RUBY, 'lib/basket.rb' => "class Basket; def empty? = true; end\n")
      describe 'Basket' do
        it 'adds up the items' do
          assert_equal 5, Basket.new(2, 3).total
        end

        it 'starts empty' do
          assert_predicate Basket.new, :empty?
        end
      end
    RUBY

    assert_empty flagged
  end
end

describe 'the other ways a test gets weaker' do
  include SlopbouncerDSL

  def basket_test(body, name: 'adds up the items', opener: 'it')
    <<~RUBY
      describe 'Basket' do
        #{opener} '#{name}' do
      #{body.gsub(/^/, '    ')}
        end
      end
    RUBY
  end

  it 'is flagged when the value it expects is edited' do
    given basket_test('assert_equal 5, Basket.new(2, 3).total')
    change basket_test('assert_equal 6, Basket.new(2, 3).total')

    assert_equal [['Basket adds up the items', 'expected_value_changed']], flagged
    assert_equal %w[5 6], findings.first.values_at('before', 'after')
  end

  it 'is flagged when it is deleted' do
    given basket_test('assert_equal 5, Basket.new(2, 3).total')
    change "describe 'Basket' do\nend\n"

    assert_equal [['Basket adds up the items', 'test_deleted']], flagged
  end

  it 'is flagged when its whole file is deleted' do
    given basket_test('assert_equal 5, Basket.new(2, 3).total')
    change(the_test_file => nil)

    assert_equal [['Basket adds up the items', 'test_deleted']], flagged
  end

  it 'is flagged when it is marked to be skipped' do
    given basket_test('assert_equal 5, Basket.new(2, 3).total')
    change basket_test("skip 'flaky'\nassert_equal 5, Basket.new(2, 3).total")

    assert_equal [['Basket adds up the items', 'skip_added']], flagged
  end

  it 'is flagged when it is switched off by the word that opens it' do
    given basket_test('assert_equal 5, Basket.new(2, 3).total')
    change basket_test('assert_equal 5, Basket.new(2, 3).total', opener: 'xit')

    assert_equal [['Basket adds up the items', 'skip_added']], flagged
  end

  it 'is flagged when it is left with no assertions at all' do
    given basket_test('assert_equal 5, Basket.new(2, 3).total')
    change basket_test('Basket.new(2, 3).total')

    assert_equal [['Basket adds up the items', 'assertion_removed'], ['Basket adds up the items', 'no_assertions']], flagged
  end

  it 'is flagged for the assertion it lost when one kind of assertion is swapped for another' do
    given basket_test('refute_empty Basket.new(2, 3).items')
    change basket_test('assert_equal [2, 3], Basket.new(2, 3).items')

    assert_equal [['Basket adds up the items', 'assertion_removed']], flagged
  end

  it 'is not flagged when nothing about its assertions changes' do
    given basket_test("basket = Basket.new(2, 3)\nassert_equal 5, basket.total")
    change basket_test("items = Basket.new(2, 3)\nassert_equal 5, basket.total")

    assert_empty flagged
  end

  it 'is not flagged for being moved to another file' do
    given basket_test('assert_equal 5, Basket.new(2, 3).total')
    move the_test_file, 'test/models/test_basket.rb'

    assert_empty flagged
  end

  it 'is not flagged for being reworded when its body stays the same' do
    given basket_test("basket = Basket.new(2, 3)\nassert_equal 5, basket.total")
    change basket_test("basket = Basket.new(2, 3)\nassert_equal 5, basket.total", name: 'totals what is in it')

    assert_empty flagged
  end

  it 'is still checked when it is reworded and weakened at once' do
    given basket_test("assert_equal 5, Basket.new(2, 3).total\nassert_equal 2, Basket.new(2, 3).size")
    change basket_test('assert_equal 5, Basket.new(2, 3).total', name: 'totals what is in it')

    assert_equal [['Basket totals what is in it', 'assertion_removed']], flagged
  end

  it 'is read the same whether written as a block or as a test method' do
    given "class BasketTest < Minitest::Test\n  def test_total\n    assert_equal 5, Basket.new(2, 3).total\n    assert true\n  end\nend\n"
    change "class BasketTest < Minitest::Test\n  def test_total\n    assert true\n  end\nend\n"

    assert_equal [['BasketTest test_total', 'assertion_removed']], flagged
  end
end

describe 'what Slopbouncer leaves alone' do
  include SlopbouncerDSL

  it 'takes no notice of files that are not tests' do
    given('lib/basket.rb' => "def total\n  assert_equal 1, 1\nend\n")
    change('lib/basket.rb' => "def total\nend\n")

    assert_empty flagged
  end
end

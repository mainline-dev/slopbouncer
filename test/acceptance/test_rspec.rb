# frozen_string_literal: true

require_relative '../dsl/dsl'

# RSpec writes an assertion as an expectation: a subject, a direction and a
# matcher, as in expect(total).to eq(5). The value it expects is inside the
# matcher.
describe 'a spec that got weaker' do
  include SlopbouncerDSL

  def basket_spec(body, opener: "it 'adds up the items' do")
    { 'spec/basket_spec.rb' => "RSpec.describe Basket do\n  #{opener}\n#{body.gsub(/^/, '    ')}\n  end\nend\n" }
  end

  def edited
    findings.map { |finding| finding.values_at('rule', 'before', 'after') }
  end

  it 'is flagged when an expectation is removed from it' do
    given basket_spec("expect(basket.total).to eq(5)\nexpect(basket.size).to eq(2)")
    change basket_spec('expect(basket.total).to eq(5)')

    assert_equal [['Basket adds up the items', 'assertion_removed']], flagged
    assert_equal 'expect(basket.size).to eq(2)', findings.first['detail']
  end

  it 'is flagged when the value its matcher expects is edited' do
    given basket_spec('expect(basket.total).to eq(5)')
    change basket_spec('expect(basket.total).to eq(6)')

    assert_equal [%w[expected_value_changed 5 6]], edited
  end

  it 'is flagged the same way when the matcher is written without brackets' do
    given basket_spec('expect(basket.total).to eq 5')
    change basket_spec('expect(basket.total).to eq 6')

    assert_equal [%w[expected_value_changed 5 6]], edited
  end

  it 'is flagged when it expects something of a different subject' do
    given basket_spec('expect(basket.total).to eq(5)')
    change basket_spec('expect(basket.size).to eq(5)')

    assert_equal [%w[expected_value_changed basket.total basket.size]], edited
  end

  it 'is flagged for the expectation it lost when a matcher is swapped for another' do
    given basket_spec('expect(basket.total).to eq(5)')
    change basket_spec('expect(basket.total).to be_truthy')

    assert_equal [['Basket adds up the items', 'assertion_removed']], flagged
  end

  it 'is flagged when an expectation is turned round' do
    given basket_spec('expect(basket.total).to eq(5)')
    change basket_spec('expect(basket.total).not_to eq(5)')

    assert_equal [['Basket adds up the items', 'assertion_removed']], flagged
  end

  it 'is flagged when the error a block must raise is edited' do
    given basket_spec('expect { basket.pay }.to raise_error(Declined)')
    change basket_spec('expect { basket.pay }.to raise_error(StandardError)')

    assert_equal [%w[expected_value_changed Declined StandardError]], edited
  end

  it 'is flagged when a matcher built from several calls is edited, and shows the whole matcher' do
    given basket_spec('expect { basket.add(3) }.to change { basket.total }.from(0).to(3)')
    change basket_spec('expect { basket.add(3) }.to change { basket.total }.from(0).to(4)')

    assert_equal [['expected_value_changed', 'change { basket.total }.from(0).to(3)', 'change { basket.total }.from(0).to(4)']], edited
  end

  it 'is not flagged when it gains an expectation' do
    given basket_spec('expect(basket.total).to eq(5)')
    change basket_spec("expect(basket.total).to eq(5)\nexpect(basket.size).to eq(2)")

    assert_empty flagged
  end

  it 'is not flagged for a stub it lost, since a stub checks nothing' do
    given basket_spec("allow(prices).to receive(:for).and_return(5)\nexpect(basket.total).to eq(5)")
    change basket_spec('expect(basket.total).to eq(5)')

    assert_empty flagged
  end

  it 'is flagged when it is marked to be skipped beside its name' do
    given basket_spec('expect(basket.total).to eq(5)')
    change basket_spec('expect(basket.total).to eq(5)', opener: "it 'adds up the items', :skip do")

    assert_equal [['Basket adds up the items', 'skip_added']], flagged
  end

  it 'is flagged when it is marked as pending with a reason' do
    given basket_spec('expect(basket.total).to eq(5)')
    change basket_spec('expect(basket.total).to eq(5)', opener: "it 'adds up the items', pending: 'later' do")

    assert_equal [['Basket adds up the items', 'skip_added']], flagged
  end

  it 'is not flagged when the mark beside its name says not to skip it' do
    given basket_spec('expect(basket.total).to eq(5)')
    change basket_spec('expect(basket.total).to eq(5)', opener: "it 'adds up the items', skip: false do")

    assert_empty flagged
  end

  it 'is flagged when the group it is in is marked to be skipped' do
    given basket_spec('expect(basket.total).to eq(5)')
    change('spec/basket_spec.rb' => <<~RUBY)
      RSpec.describe Basket, :skip do
        it 'adds up the items' do
          expect(basket.total).to eq(5)
        end
      end
    RUBY

    assert_equal [['Basket adds up the items', 'skip_added']], flagged
  end

  it 'is flagged when its body is taken away, which leaves it pending' do
    given basket_spec('expect(basket.total).to eq(5)')
    change('spec/basket_spec.rb' => "RSpec.describe Basket do\n  it 'adds up the items'\nend\n")

    assert_equal [['Basket adds up the items', 'test_deleted']], flagged
  end
end

describe 'a spec written on one line, with no name' do
  include SlopbouncerDSL

  def user_spec(*lines)
    { 'spec/user_spec.rb' => "RSpec.describe User do\n#{lines.map { |line| "  #{line}\n" }.join}end\n" }
  end

  it 'is named by what it expects, and flagged when it is deleted' do
    given user_spec('it { is_expected.to validate_presence_of(:name) }', 'it { is_expected.to validate_presence_of(:email) }')
    change user_spec('it { is_expected.to validate_presence_of(:name) }')

    assert_equal [['User is_expected.to validate_presence_of(:email)', 'test_deleted']], flagged
  end

  it 'is not flagged for another one-line spec added beside it' do
    given user_spec('it { is_expected.to validate_presence_of(:name) }')
    change user_spec('it { is_expected.to validate_presence_of(:email) }', 'it { is_expected.to validate_presence_of(:name) }')

    assert_empty flagged
  end

  it 'is flagged for the value it expects when that is edited' do
    given user_spec('it { is_expected.to have_attributes(age: 18) }')
    change user_spec('it { is_expected.to have_attributes(age: 21) }')

    assert_equal [['expected_value_changed', 'age: 18', 'age: 21']], findings.map { |finding| finding.values_at('rule', 'before', 'after') }
  end

  it 'is read the same when written with should' do
    given user_spec('it { should validate_presence_of(:name) }', 'it { should_not allow_value(nil).for(:email) }')
    change user_spec('it { should validate_presence_of(:name) }')

    assert_equal [['User should_not allow_value(nil).for(:email)', 'test_deleted']], flagged
  end
end

describe 'specs in groups' do
  include SlopbouncerDSL

  def groups(total)
    { 'spec/basket_spec.rb' => <<~RUBY }
      RSpec.describe Basket, '#total' do
        context 'with two items' do
          it('adds them up') { expect(basket.total).to eq(#{total}) }
        end
      end

      RSpec.describe Basket, '#size' do
        context 'with two items' do
          it('adds them up') { expect(basket.size).to eq(2) }
        end
      end
    RUBY
  end

  it 'tells apart two groups that differ only in their second description' do
    given groups(5)
    change groups(6)

    assert_equal [['Basket #total with two items adds them up', 'expected_value_changed']], flagged
  end

  it 'names a shared example after the examples it belongs to' do
    given('spec/support/priced.rb' => "RSpec.shared_examples 'something priced' do\n  it('has a price') { expect(subject.price).to be > 0 }\nend\n")
    change('spec/support/priced.rb' => "RSpec.shared_examples 'something priced' do\n  it('has a price') { expect(subject.price).to be >= 0 }\nend\n")

    assert_equal [['something priced has a price', 'expected_value_changed']], flagged
  end
end

# A group's before, after and around hooks can hold the expectation for every
# spec in the group, as in after { expect(request).to have_been_made }.
describe 'specs checked by a hook in their group' do
  include SlopbouncerDSL

  def connection_spec(hook:, body: "conn.get('/colours', only: %w[red blue])")
    { 'spec/connection_spec.rb' => <<~RUBY }
      RSpec.describe Connection do
        context 'with params' do
          it 'sends them' do
            #{body}
          end

          it 'sends them again' do
            conn.get('/colours')
          end
        #{hook}
        end
      end
    RUBY
  end

  it 'are not said to assert nothing when their own lines change' do
    given connection_spec(hook: 'after { expect(request).to have_been_made.once }')
    change connection_spec(hook: 'after { expect(request).to have_been_made.once }', body: "conn.get('/colours', only: %w[red])")

    assert_empty flagged
  end

  it 'are covered by a hook in a group further out as well' do
    given('spec/connection_spec.rb' => <<~RUBY)
      RSpec.describe Connection do
        after { expect(request).to have_been_made.once }

        context 'with params' do
          it('sends them') { conn.get('/colours') }
        end
      end
    RUBY

    change('spec/connection_spec.rb' => <<~RUBY)
      RSpec.describe Connection do
        after { expect(request).to have_been_made.once }

        context 'with params' do
          it('sends them') { conn.get('/colors') }
        end
      end
    RUBY

    assert_empty flagged
  end

  it 'are still said to assert nothing when the hook only sets things up' do
    given connection_spec(hook: 'before { stub_request(:get, "/colours") }')
    change connection_spec(hook: 'before { stub_request(:get, "/colours") }', body: "conn.get('/colours', only: %w[red])")

    assert_equal [['Connection with params sends them', 'no_assertions']], flagged
  end

  it 'are flagged once, at the hook, when the hook loses its expectation' do
    given connection_spec(hook: 'after { expect(request).to have_been_made.once }')
    change connection_spec(hook: '')

    assert_equal [['Connection with params after hook', 'test_deleted']], flagged
  end

  it 'are flagged at the hook when the value it expects is edited' do
    given connection_spec(hook: 'after { expect(request).to have_been_made.times(2) }')
    change connection_spec(hook: 'after { expect(request).to have_been_made.times(1) }')

    assert_equal [['Connection with params after hook', 'expected_value_changed']], flagged
  end
end

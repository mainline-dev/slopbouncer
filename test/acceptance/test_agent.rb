# frozen_string_literal: true

require_relative '../dsl/dsl'

# Slopbouncer is most use fed back to the coding agent that made the change:
# it knows why it changed a test, and can put the test back.
describe 'work an agent has not committed' do
  include SlopbouncerDSL

  def basket(*assertions)
    "describe 'Basket' do\n  it 'adds up' do\n#{assertions.map { |line| "    #{line}\n" }.join}  end\nend\n"
  end

  it 'has a removed assertion flagged before anything is committed' do
    given basket('assert_equal 5, total', 'assert_equal 2, size')
    edit_without_committing basket('assert_equal 5, total')

    assert_equal [['Basket adds up', 'assertion_removed']], flagged_since_base
  end

  it 'is checked together with what has been committed since the base' do
    given(the_test_file => basket('assert_equal 5, total', 'assert_equal 2, size'),
      'test/test_refund.rb' => "describe 'Refund' do\n  it 'refunds' do\n    assert_equal 100, amount\n  end\nend\n")
    change(the_test_file => basket('assert_equal 5, total'))
    edit_without_committing('test/test_refund.rb' => "describe 'Refund' do\n  it 'refunds' do\n    assert_equal 90, amount\n  end\nend\n")

    assert_equal [['Basket adds up', 'assertion_removed'], ['Refund refunds', 'expected_value_changed']], flagged_since_base.sort
  end

  it 'is left alone when it only adds a test' do
    given basket('assert_equal 5, total')
    edit_without_committing basket('assert_equal 5, total').sub(/end\n\z/, "  it 'is new' do\n    assert true\n  end\nend\n")

    assert_empty flagged_since_base
  end
end

describe 'an agent about to finish' do
  include SlopbouncerDSL

  def weaken
    given "describe 'Basket' do\n  it 'adds up' do\n    assert_equal 5, total\n    assert_equal 2, size\n  end\nend\n"
    edit_without_committing "describe 'Basket' do\n  it 'adds up' do\n    assert_equal 5, total\n  end\nend\n"
  end

  it 'is stopped and told which test it weakened, and where' do
    weaken

    told = as_the_agents_stop_hook

    assert_equal 2, told.status
    assert_includes told.error, 'Basket adds up'
    assert_includes told.error, the_test_file
  end

  it 'is told on the channel the agent reads, with nothing on the other' do
    weaken

    assert_empty as_the_agents_stop_hook.output
  end

  it 'is let finish when it weakened nothing' do
    given "describe 'Basket' do\n  it 'adds up' do\n    assert_equal 5, total\n  end\nend\n"
    edit_without_committing "describe 'Basket' do\n  it 'adds up' do\n    assert_equal 5, total\n    assert true\n  end\nend\n"

    told = as_the_agents_stop_hook

    assert_equal [0, ''], [told.status, told.error]
  end

  it 'is asked once: having been stopped already, it is let finish' do
    weaken

    assert_equal 0, as_the_agents_stop_hook(stopped_before: true).status
  end

  it 'is still stopped when the hook is given nothing to read' do
    weaken

    assert_equal 2, as_the_agents_stop_hook(input: '').status
  end
end

# frozen_string_literal: true

require_relative '../dsl/dsl'

# One command sets a coding agent up to run Slopbouncer when it finishes, so
# nobody has to paste a block of settings from the README.
describe 'setting up Claude Code' do
  include SlopbouncerDSL

  SETTINGS = '.claude/settings.json'

  def weakened_work
    given "describe 'Basket' do\n  it 'adds up' do\n    assert_equal 5, total\n    assert_equal 2, size\n  end\nend\n"
    edit_without_committing "describe 'Basket' do\n  it 'adds up' do\n    assert_equal 5, total\n  end\nend\n"
  end

  it 'writes the hook into a project that has no settings yet' do
    assert_equal 0, install('claude-code').status
    assert_equal 1, stop_hooks_in(SETTINGS).size
  end

  it 'sets up a hook that really stops an agent that weakened a test' do
    weakened_work
    install('claude-code')

    assert_equal 2, run_stop_hook_from(SETTINGS).status
  end

  it 'keeps the settings and the hooks a project already has' do
    have_file SETTINGS, JSON.generate(
      'permissions' => { 'allow' => ['Bash(git *)'] },
      'hooks'       => { 'Stop'       => [{ 'hooks' => [{ 'type' => 'command', 'command' => 'say done' }] }],
                         'PreToolUse' => [{ 'matcher' => 'Bash', 'hooks' => [{ 'type' => 'command', 'command' => 'true' }] }] }
    )

    install('claude-code')
    settings = JSON.parse(file(SETTINGS))

    assert_equal ['Bash(git *)'], settings.dig('permissions', 'allow')
    assert_equal 1, settings.dig('hooks', 'PreToolUse').size
    assert_equal 2, stop_hooks_in(SETTINGS).size
    assert_includes stop_hooks_in(SETTINGS), 'say done'
  end

  it 'changes nothing when it is already set up' do
    install('claude-code')
    once = file(SETTINGS)

    assert_equal 0, install('claude-code').status
    assert_equal once, file(SETTINGS)
  end

  it 'can keep the hook to one person, out of the shared settings' do
    install('claude-code', '--local')

    assert_equal 1, stop_hooks_in('.claude/settings.local.json').size
    refute file_exists?(SETTINGS)
  end

  it 'refuses settings it cannot read, and leaves them as they were' do
    have_file SETTINGS, '{ not json'

    assert_equal 2, install('claude-code').status
    assert_equal '{ not json', file(SETTINGS)
  end

  it 'says which agents it can set up when asked for one it does not know' do
    refused = install('emacs')

    assert_equal 2, refused.status
    assert_includes refused.error, 'claude-code'
  end
end

describe 'speaking for a named agent' do
  include SlopbouncerDSL

  it "answers in Claude Code's way when told that is who is asking" do
    given "describe 'Basket' do\n  it 'adds up' do\n    assert_equal 5, total\n    assert_equal 2, size\n  end\nend\n"
    edit_without_committing "describe 'Basket' do\n  it 'adds up' do\n    assert_equal 5, total\n  end\nend\n"

    assert_equal 2, as_the_agents_stop_hook(agent: 'claude-code').status
  end

  it 'lets the agent finish, and says why, when told to speak for an agent it does not know' do
    given "describe 'Basket' do\nend\n"

    told = as_the_agents_stop_hook(agent: 'emacs')

    assert_equal 0, told.status
    assert_includes told.error, 'claude-code'
  end
end

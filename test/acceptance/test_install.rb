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

# Cursor keeps hooks in .cursor/hooks.json. Its stop hook answers on standard
# output: a follow-up message that Cursor gives the agent as its next turn.
describe 'setting up Cursor' do
  include SlopbouncerDSL

  HOOKS = '.cursor/hooks.json'

  def weakened_work
    given "describe 'Basket' do\n  it 'adds up' do\n    assert_equal 5, total\n    assert_equal 2, size\n  end\nend\n"
    edit_without_committing "describe 'Basket' do\n  it 'adds up' do\n    assert_equal 5, total\n  end\nend\n"
  end

  def follow_up(**input)
    weakened_work
    install('cursor')
    run_stop_hook_from(HOOKS, { 'status' => 'completed', 'loop_count' => 0 }.merge(input.transform_keys(&:to_s)))
  end

  it 'writes the hook into a project with no hooks yet, in the form Cursor reads' do
    assert_equal 0, install('cursor').status
    assert_equal 1, JSON.parse(file(HOOKS))['version']
    assert_equal 1, stop_hooks_in(HOOKS).size
  end

  it 'keeps the hooks a project already has' do
    have_file HOOKS, JSON.generate('version' => 1,
      'hooks' => { 'afterFileEdit' => [{ 'command' => '.cursor/hooks/format.sh' }], 'stop' => [{ 'command' => './audit.sh', 'loop_limit' => 10 }] })

    install('cursor')

    assert_equal [{ 'command' => '.cursor/hooks/format.sh' }], JSON.parse(file(HOOKS)).dig('hooks', 'afterFileEdit')
    assert_equal 2, stop_hooks_in(HOOKS).size
    assert_includes stop_hooks_in(HOOKS), './audit.sh'
  end

  it 'changes nothing when it is already set up' do
    install('cursor')
    once = file(HOOKS)
    install('cursor')

    assert_equal once, file(HOOKS)
  end

  it 'sets up a hook that sends the agent back with what it weakened' do
    sent = follow_up

    assert_equal 0, sent.status
    assert_includes JSON.parse(sent.output).fetch('followup_message'), 'Basket adds up'
    assert_includes JSON.parse(sent.output).fetch('followup_message'), test_file
  end

  it 'sends the agent back once only' do
    assert_empty follow_up(loop_count: 1).output
  end

  it 'sends nothing after the person stopped the agent themselves' do
    assert_empty follow_up(status: 'aborted').output
  end

  it 'sends nothing when nothing was weakened' do
    given "describe 'Basket' do\nend\n"
    install('cursor')

    assert_empty run_stop_hook_from(HOOKS, 'status' => 'completed', 'loop_count' => 0).output
  end

  it 'has no per-person hooks file in the project to offer' do
    assert_equal 2, install('cursor', '--local').status
    refute file_exists?(HOOKS)
  end
end

# Gemini CLI keeps hooks in .gemini/settings.json. Its AfterAgent hook answers
# on standard output: denying the response, with a reason that Gemini gives
# the agent as a new prompt.
describe 'setting up Gemini CLI' do
  include SlopbouncerDSL

  GEMINI = '.gemini/settings.json'

  def denial(**input)
    given "describe 'Basket' do\n  it 'adds up' do\n    assert_equal 5, total\n    assert_equal 2, size\n  end\nend\n"
    edit_without_committing "describe 'Basket' do\n  it 'adds up' do\n    assert_equal 5, total\n  end\nend\n"
    install('gemini')
    run_stop_hook_from(GEMINI, { 'stop_hook_active' => false }.merge(input.transform_keys(&:to_s)))
  end

  it 'writes the hook into a project with no settings yet' do
    assert_equal 0, install('gemini').status
    assert_equal 1, stop_hooks_in(GEMINI).size
  end

  it 'keeps the settings and the hooks a project already has' do
    have_file GEMINI, JSON.generate('theme' => 'dark',
      'hooks' => { 'AfterAgent' => [{ 'hooks' => [{ 'type' => 'command', 'command' => 'notify done' }] }] })

    install('gemini')

    assert_equal 'dark', JSON.parse(file(GEMINI))['theme']
    assert_equal 2, stop_hooks_in(GEMINI).size
    assert_includes stop_hooks_in(GEMINI), 'notify done'
  end

  it 'changes nothing when it is already set up' do
    install('gemini')
    once = file(GEMINI)
    install('gemini')

    assert_equal once, file(GEMINI)
  end

  it 'sets up a hook that turns the response down and says what was weakened' do
    answer = JSON.parse(denial.output)

    assert_equal 'deny', answer['decision']
    assert_includes answer['reason'], 'Basket adds up'
  end

  it 'answers with nothing but the JSON Gemini reads, and succeeds' do
    answer = denial

    assert_equal [0, ''], [answer.status, answer.error]
  end

  it 'turns the response down once only' do
    assert_empty denial(stop_hook_active: true).output
  end

  it 'has no per-person settings file in the project to offer' do
    assert_equal 2, install('gemini', '--local').status
  end
end

describe 'a hook run from somewhere other than the project' do
  include SlopbouncerDSL

  it 'checks the directory the agent says it is working in' do
    given "describe 'Basket' do\n  it 'adds up' do\n    assert_equal 5, total\n    assert_equal 2, size\n  end\nend\n"
    edit_without_committing "describe 'Basket' do\n  it 'adds up' do\n    assert_equal 5, total\n  end\nend\n"

    assert_equal 2, as_the_agents_stop_hook_from_elsewhere.status
  end
end

# Codex keeps a project's hooks in .codex/hooks.json. Its Stop hook answers on
# standard output with JSON: a decision to block, whose reason Codex gives the
# agent as a new prompt. Codex runs a new hook only once a person has trusted it.
describe 'setting up Codex' do
  include SlopbouncerDSL

  CODEX = '.codex/hooks.json'

  def continuation(**input)
    given "describe 'Basket' do\n  it 'adds up' do\n    assert_equal 5, total\n    assert_equal 2, size\n  end\nend\n"
    edit_without_committing "describe 'Basket' do\n  it 'adds up' do\n    assert_equal 5, total\n  end\nend\n"
    install('codex')
    run_stop_hook_from(CODEX, { 'stop_hook_active' => false }.merge(input.transform_keys(&:to_s)))
  end

  it 'writes the hook into a project with no hooks yet' do
    assert_equal 0, install('codex').status
    assert_equal 1, stop_hooks_in(CODEX).size
  end

  it 'says where in Codex to trust the new hook, since Codex skips it until then' do
    assert_includes install('codex').output, '/hooks'
  end

  it 'keeps the hooks a project already has' do
    have_file CODEX, JSON.generate('description' => 'ours',
      'hooks' => { 'Stop'       => [{ 'hooks' => [{ 'type' => 'command', 'command' => 'notify done' }] }],
                   'PreToolUse' => [{ 'matcher' => 'Bash', 'hooks' => [{ 'type' => 'command', 'command' => 'true' }] }] })

    install('codex')
    hooks = JSON.parse(file(CODEX))

    assert_equal 'ours', hooks['description']
    assert_equal 1, hooks.dig('hooks', 'PreToolUse').size
    assert_equal 2, stop_hooks_in(CODEX).size
    assert_includes stop_hooks_in(CODEX), 'notify done'
  end

  it 'changes nothing when it is already set up' do
    install('codex')
    once = file(CODEX)
    install('codex')

    assert_equal once, file(CODEX)
  end

  it 'sets up a hook that keeps the agent going and says what was weakened' do
    answer = JSON.parse(continuation.output)

    assert_equal 'block', answer['decision']
    assert_includes answer['reason'], 'Basket adds up'
  end

  it 'answers with nothing but the JSON Codex reads, and succeeds' do
    answer = continuation

    assert_equal [0, ''], [answer.status, answer.error]
  end

  it 'keeps the agent going once only' do
    assert_empty continuation(stop_hook_active: true).output
  end

  it 'says nothing at all when nothing was weakened' do
    given "describe 'Basket' do\nend\n"
    install('codex')

    answer = run_stop_hook_from(CODEX)

    assert_equal [0, '', ''], [answer.status, answer.output, answer.error]
  end

  it 'has no per-person hooks file in the project to offer' do
    assert_equal 2, install('codex', '--local').status
  end
end

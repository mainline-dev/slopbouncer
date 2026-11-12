# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'driver'

# What the scenarios say: a test file is one way, a change makes it another,
# and Slopbouncer flags (or does not flag) tests in it.
module SlopbouncerDSL
  TEST_FILE = 'test/test_basket.rb'

  def before_setup
    super
    @driver = Driver.new
  end

  def after_teardown
    @driver.remove
    super
  end

  # The one test file most scenarios talk about.
  def the_test_file
    TEST_FILE
  end

  # The repository before the change under review.
  def given(files)
    @base = @driver.commit(normalise(files))
  end

  # The change under review.
  def change(files)
    @driver.commit(normalise(files))
  end

  # A change left in the working tree, as an agent leaves its work.
  def edit_without_committing(files)
    normalise(files).each { |path, source| @driver.write(path, source) }
  end

  # What Slopbouncer flags in everything since the base, committed or not.
  def flagged_since_base
    @driver.slopbouncer(@base, '--json').findings.map { |finding| finding.values_at('test', 'rule') }
  end

  # Slopbouncer run the way a coding agent's stop hook runs it: told on
  # standard input whether it has stopped the agent once already.
  def as_the_agents_stop_hook(stopped_before: false, input: nil, agent: nil)
    @driver.slopbouncer(@base, agent ? "--agent=#{agent}" : '--agent',
      input: input || JSON.generate('stop_hook_active' => stopped_before))
  end

  # The stop hook run from outside the repository, told where the agent is
  # working the way a harness tells it: in the hook's input.
  def as_the_agents_stop_hook_from_elsewhere
    @driver.slopbouncer(@base, '--agent', from: Dir.tmpdir,
      input: JSON.generate('stop_hook_active' => false, 'cwd' => @driver.root))
  end

  # Sets an agent up in the repository, as a person would from its root.
  def install(agent, *flags)
    @driver.slopbouncer('install', agent, *flags)
  end

  def have_file(path, content)
    @driver.write(path, content)
  end

  def file(path)
    @driver.read(path)
  end

  def file_exists?(path)
    @driver.exists?(path)
  end

  # The commands a settings file runs when the agent stops, whichever agent's
  # file it is: Claude Code nests them under hooks.Stop, Gemini CLI under
  # hooks.AfterAgent, and Cursor lists them under hooks.stop.
  def stop_hooks_in(path)
    hooks = JSON.parse(file(path)).fetch('hooks')
    return hooks.fetch('stop').map { |hook| hook['command'] } if hooks.key?('stop')

    (hooks['Stop'] || hooks.fetch('AfterAgent')).flat_map { |entry| entry['hooks'].map { |hook| hook['command'] } }
  end

  # Runs the Slopbouncer hook a settings file holds, the way the agent's
  # harness would: through a shell, with the command on the path, and what
  # the harness tells a stop hook on standard input.
  def run_stop_hook_from(path, input = { 'stop_hook_active' => false })
    command = stop_hooks_in(path).find { |hook| hook.include?('slopbouncer') }
    @driver.shell(command, input: JSON.generate(input))
  end

  def move(from, to)
    @driver.move(from, to)
  end

  def configure(yaml)
    @driver.write('.slopbouncer.yml', yaml)
  end

  # What Slopbouncer flags in the change: [test name, rule] pairs.
  def flagged
    run_slopbouncer.findings.map { |finding| finding.values_at('test', 'rule') }
  end

  def findings
    run_slopbouncer.findings
  end

  def run_slopbouncer(*flags)
    @driver.slopbouncer("#{@base}..HEAD", '--json', *flags)
  end

  # What the command prints when not asked for JSON.
  def plain_report
    @driver.slopbouncer("#{@base}..HEAD").output
  end

  # The command with exactly these arguments.
  def slopbouncer_with(*arguments)
    @driver.slopbouncer(*arguments)
  end

  private

  # A bare string is the one test file the scenarios mostly talk about.
  def normalise(files)
    files.is_a?(String) ? { TEST_FILE => files } : files
  end
end

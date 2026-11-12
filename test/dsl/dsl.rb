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
  def test_file
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

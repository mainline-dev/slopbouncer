# frozen_string_literal: true

require 'json'
require 'yaml'
require_relative 'slopbouncer/version'
require_relative 'slopbouncer/git'
require_relative 'slopbouncer/ruby_tests'
require_relative 'slopbouncer/compare'
require_relative 'slopbouncer/agents'
require_relative 'slopbouncer/install'
require_relative 'slopbouncer/terminal_report'

# A static check that flags tests which got weaker in a change, so a person
# can decide whether that was intended.
module Slopbouncer
  class Error < StandardError; end

  # A project's own settings, in the directory the command is run from:
  #   assertions: the names of its helper methods that count as assertions.
  CONFIG = '.slopbouncer.yml'

  TEST_FILE = %r{(\A|/)(test|spec)/.*\.rb\z|(\A|/)(test_[^/]*|[^/]*_(test|spec))\.rb\z}

  # How many findings a coding agent is told about in full.
  TOLD_TO_AN_AGENT = 20

  USAGE = 'Give a range of commits, such as main..HEAD, or one commit to compare the working tree with, such as HEAD'

  # The findings for the commits in a range such as main..HEAD, or for
  # everything since one commit, committed or not, when given just that.
  def self.check(target)
    base, head = target.split('..', 2)
    raise Error, USAGE if base.to_s.empty? || (target.include?('..') && head.to_s.empty?)

    helpers = settings.fetch('assertions', [])
    results = Git.changed(base, head).filter_map do |changed|
      next unless [changed.before_path, changed.after_path].compact.all? { |path| path.match?(TEST_FILE) }

      before = changed.before_path ? RubyTests.in(Git.show(base, changed.before_path), helpers: helpers) : []
      after = changed.after_path ? RubyTests.in(Git.show(head, changed.after_path), helpers: helpers) : []
      [changed.after_path || changed.before_path, Compare.call(changed.after_path || changed.before_path, before, after)]
    end
    results.flat_map { |_file, result| result.findings } + deleted(results)
  end

  # A test that has gone from one file is deleted unless the same test, body
  # for body, is new in another file of the same change.
  def self.deleted(results)
    moved = results.flat_map { |_file, result| result.fresh.map(&:body) }
    results.flat_map do |file, result|
      result.gone.reject { |test| moved.include?(test.body) }.map { |test| Compare.deleted(file, test) }
    end
  end

  def self.settings
    File.exist?(CONFIG) ? YAML.safe_load_file(CONFIG) || {} : {}
  rescue Psych::Exception => e
    raise Error, "#{CONFIG} could not be read: #{e.message}"
  end

  def self.run(arguments, input: $stdin)
    return said(help) if arguments.intersect?(%w[--help -h])
    return said("slopbouncer #{VERSION}") if arguments.intersect?(%w[--version -v])

    words = arguments.reject { |argument| argument.start_with?('--') }
    return install(words.drop(1), arguments) if words.first == 'install'

    target = words.first
    agent = arguments.find { |argument| argument == '--agent' || argument.start_with?('--agent=') }
    return stop_hook(target.to_s, input, agent.split('=', 2)[1] || Agents::DEFAULT) if agent

    findings = check(target.to_s)
    puts printed(findings, arguments)
    arguments.include?('--strict') && findings.any? ? 1 : 0
  rescue Error => e
    warn e.message
    2
  end

  def self.said(text)
    puts text
    0
  end

  def self.help
    <<~HELP
      Slopbouncer flags tests that got weaker in a change. It reads the code and never runs it.

      Usage:
        slopbouncer main..HEAD       the commits in a range
        slopbouncer HEAD             everything since one commit, committed or not
        slopbouncer install AGENT    set up a coding agent's hook: #{Agents::ALL.keys.join(', ')}

      Options:
        --json           print the findings as JSON
        --strict         exit with 1 when anything is flagged
        --all            at a terminal, list every finding however many there are
        --color          use the terminal layout, in colour, wherever the output goes
        --agent=NAME     run as that coding agent's hook
        --local          with install claude-code, keep the hook out of the shared settings
        -h, --help       print this
        -v, --version    print the version
    HELP
  end

  # JSON when asked for it. Otherwise laid out for a person when the output is
  # a terminal or colour is asked for, and one plain line for each finding
  # when it goes to another program. What a program reads is always complete;
  # what a person reads is counted up when it is long, unless they ask for all.
  def self.printed(findings, arguments)
    return JSON.pretty_generate(findings.map { |finding| finding.to_h.compact }) if arguments.include?('--json')

    asked = arguments.intersect?(%w[--color --colour])
    return report(findings) unless asked || $stdout.tty?

    TerminalReport.call(findings, colour: asked || ENV['NO_COLOR'].to_s.empty?, all: arguments.include?('--all'))
  end

  # Sets a coding agent up in the current directory: slopbouncer install claude-code
  def self.install(words, arguments)
    raise Error, "Say which agent to set up: #{Agents::ALL.keys.join(', ')}" if words.empty?

    puts Install.call(words.first, local: arguments.include?('--local'))
    0
  rescue Error => e
    warn e.message
    2
  end

  # Run as a coding agent's stop hook. The agent is stopped from finishing
  # once and told what it weakened, in the way its own harness expects. A
  # mistake in how the hook is set up never stops the agent: it is said on
  # standard error and the agent is let finish.
  def self.stop_hook(target, input, agent_name)
    agent = Agents.named(agent_name)
    told = hook_input(input)
    return 0 if agent.stopped_before?(told)

    findings = Dir.chdir(working_directory(told)) { check(target) }
    return 0 if findings.empty?

    output, error, status = agent.block(to_the_agent(findings, target))
    print output
    warn error unless error.empty?
    status
  rescue Error => e
    warn e.message
    0
  end

  # Where the agent says it is working, when its harness says so on the
  # hook's input. Some harnesses run hooks from somewhere else.
  def self.working_directory(told)
    said = told['cwd'] || Array(told['workspace_roots']).first
    said.is_a?(String) && File.directory?(said) ? said : Dir.pwd
  end

  # What the agent's harness passes the hook on standard input, if anything.
  def self.hook_input(input)
    text = input.tty? ? '' : input.read.to_s
    parsed = text.strip.empty? ? {} : JSON.parse(text)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  # A coding agent is told about the first few findings, since a mechanical
  # rewrite can make hundreds, and how to list the rest.
  def self.to_the_agent(findings, target)
    more = findings.size - TOLD_TO_AN_AGENT
    rest = "\nand #{more} more. Run `slopbouncer #{target}` to list them all.\n" if more.positive?
    <<~MESSAGE
      Slopbouncer: this change looks to weaken #{findings.size} existing #{findings.size == 1 ? 'test' : 'tests'}.

      #{report(findings.first(TOLD_TO_AN_AGENT))}
      #{rest}
      For each one, do one of two things before you finish:
      1. Put the test back as it was, and make the code pass it.
      2. Leave the change, and tell the person which behaviour changed and why the test had to change with it.
    MESSAGE
  end

  def self.report(findings)
    findings.map { |finding|
      what = finding.before ? "#{finding.before} → #{finding.after}" : finding.detail
      "#{finding.file}: #{finding.test}: #{finding.rule}: #{what}"
    }.join("\n")
  end
  private_class_method :deleted, :settings, :said, :help, :printed, :install, :stop_hook, :working_directory, :hook_input, :to_the_agent
end

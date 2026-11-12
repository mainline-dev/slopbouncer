# frozen_string_literal: true

require 'json'

module Slopbouncer
  # The coding agents Slopbouncer can run under. Each one knows where that
  # agent keeps its hooks, how to add Slopbouncer to them, and how to tell the
  # agent it may not finish yet. A new agent is one more module here.
  module Agents
    # Claude Code runs Stop hooks when the agent is about to finish. A hook
    # that exits with 2 stops it, and what the hook wrote to standard error is
    # handed to the agent as the reason.
    module ClaudeCode
      NAME = 'claude-code'
      SHARED = '.claude/settings.json'
      LOCAL = '.claude/settings.local.json'

      def self.settings_path(local:)
        local ? LOCAL : SHARED
      end

      def self.command(base)
        "slopbouncer #{base} --agent=#{NAME}"
      end

      def self.installed?(settings)
        stop_hooks(settings).any? { |hook| hook['command'].to_s.include?('slopbouncer') }
      end

      # The settings with Slopbouncer added to whatever runs at Stop already.
      def self.add(settings, command)
        hooks = settings.fetch('hooks', {})
        entry = { 'hooks' => [{ 'type' => 'command', 'command' => command }] }
        settings.merge('hooks' => hooks.merge('Stop' => hooks.fetch('Stop', []) + [entry]))
      end

      # Claude Code says on the hook's input whether it has stopped the agent
      # once already.
      def self.stopped_before?(input)
        input['stop_hook_active'] == true
      end

      # What to write and exit with to send the agent back: [output, error, status].
      def self.block(message)
        ['', message, 2]
      end

      def self.stop_hooks(settings)
        settings.dig('hooks', 'Stop').to_a.flat_map { |entry| entry['hooks'].to_a }
      end
      private_class_method :stop_hooks
    end

    # Cursor runs stop hooks when the agent loop ends. A hook answers on
    # standard output with JSON, and a follow-up message there is given to the
    # agent as its next turn. Project hooks run from the project root.
    module Cursor
      NAME = 'cursor'
      SHARED = '.cursor/hooks.json'
      VERSION = 1

      # Cursor's own per-person file is in the home directory and its hooks
      # do not run from the project, so there is nothing to offer here.
      def self.settings_path(local:)
        raise Error, "Cursor keeps a project's hooks in #{SHARED} only. Run it without --local." if local

        SHARED
      end

      def self.command(base)
        "slopbouncer #{base} --agent=#{NAME}"
      end

      def self.installed?(settings)
        stop_hooks(settings).any? { |hook| hook['command'].to_s.include?('slopbouncer') }
      end

      def self.add(settings, command)
        hooks = settings.fetch('hooks', {})
        { 'version' => VERSION }.merge(settings).merge('hooks' => hooks.merge('stop' => stop_hooks(settings) + [{ 'command' => command }]))
      end

      # Cursor counts the follow-ups a stop hook has already caused, and says
      # how the loop ended. Only an agent that finished by itself is sent back.
      def self.stopped_before?(input)
        input['loop_count'].to_i.positive? || (input.key?('status') && input['status'] != 'completed')
      end

      def self.block(message)
        [JSON.generate('followup_message' => message), '', 0]
      end

      def self.stop_hooks(settings)
        settings.dig('hooks', 'stop').to_a
      end
      private_class_method :stop_hooks
    end

    # Gemini CLI runs AfterAgent hooks once the agent has written its final
    # response. A hook answers on standard output with JSON and nothing else:
    # a decision to deny the response, with a reason that Gemini gives the
    # agent as a new prompt.
    module Gemini
      NAME = 'gemini'
      SHARED = '.gemini/settings.json'

      # Gemini's per-person settings are in the home directory and apply to
      # every project, so there is nothing to offer here.
      def self.settings_path(local:)
        raise Error, "Gemini CLI keeps a project's hooks in #{SHARED} only. Run it without --local." if local

        SHARED
      end

      def self.command(base)
        "slopbouncer #{base} --agent=#{NAME}"
      end

      def self.installed?(settings)
        after_agent(settings).flat_map { |entry| entry['hooks'].to_a }.any? { |hook| hook['command'].to_s.include?('slopbouncer') }
      end

      def self.add(settings, command)
        entry = { 'hooks' => [{ 'type' => 'command', 'name' => 'slopbouncer', 'command' => command }] }
        settings.merge('hooks' => settings.fetch('hooks', {}).merge('AfterAgent' => after_agent(settings) + [entry]))
      end

      # Gemini says on the hook's input whether this is already a retry.
      def self.stopped_before?(input)
        input['stop_hook_active'] == true
      end

      def self.block(message)
        [JSON.generate('decision' => 'deny', 'reason' => message), '', 0]
      end

      def self.after_agent(settings)
        settings.dig('hooks', 'AfterAgent').to_a
      end
      private_class_method :after_agent
    end

    # Codex runs Stop hooks when a turn is about to end. A hook answers on
    # standard output with JSON: a decision to block, whose reason Codex gives
    # the agent as a new prompt. Codex skips a new or changed hook until a
    # person has reviewed and trusted it.
    module Codex
      NAME = 'codex'
      SHARED = '.codex/hooks.json'
      AFTER = 'Codex skips a new hook until you trust it: open /hooks in Codex to review it.'

      # Codex's per-person hooks are in the home directory and apply to every
      # project, so there is nothing to offer here.
      def self.settings_path(local:)
        raise Error, "Codex keeps a project's hooks in #{SHARED} only. Run it without --local." if local

        SHARED
      end

      def self.command(base)
        "slopbouncer #{base} --agent=#{NAME}"
      end

      def self.installed?(settings)
        stop(settings).flat_map { |entry| entry['hooks'].to_a }.any? { |hook| hook['command'].to_s.include?('slopbouncer') }
      end

      def self.add(settings, command)
        entry = { 'hooks' => [{ 'type' => 'command', 'command' => command }] }
        settings.merge('hooks' => settings.fetch('hooks', {}).merge('Stop' => stop(settings) + [entry]))
      end

      # Codex says on the hook's input whether Stop already continued this turn.
      def self.stopped_before?(input)
        input['stop_hook_active'] == true
      end

      def self.block(message)
        [JSON.generate('decision' => 'block', 'reason' => message), '', 0]
      end

      def self.stop(settings)
        settings.dig('hooks', 'Stop').to_a
      end
      private_class_method :stop
    end

    ALL = { ClaudeCode::NAME => ClaudeCode, Cursor::NAME => Cursor, Gemini::NAME => Gemini, Codex::NAME => Codex }.freeze
    DEFAULT = ClaudeCode::NAME

    def self.named(name)
      ALL.fetch(name) { raise Error, "Slopbouncer does not know the agent #{name.inspect}. It knows: #{ALL.keys.join(', ')}" }
    end
  end
end

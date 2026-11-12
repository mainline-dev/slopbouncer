# frozen_string_literal: true

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

      # What to write and exit with to stop the agent: [output, error, status].
      def self.stop(message)
        ['', message, 2]
      end

      def self.stop_hooks(settings)
        settings.dig('hooks', 'Stop').to_a.flat_map { |entry| entry['hooks'].to_a }
      end
      private_class_method :stop_hooks
    end

    ALL = { ClaudeCode::NAME => ClaudeCode }.freeze
    DEFAULT = ClaudeCode::NAME

    def self.named(name)
      ALL.fetch(name) { raise Error, "Slopbouncer does not know the agent #{name.inspect}. It knows: #{ALL.keys.join(', ')}" }
    end
  end
end

# frozen_string_literal: true

require 'fileutils'
require 'json'

module Slopbouncer
  # Sets a coding agent up to run Slopbouncer when it finishes, by adding one
  # hook to that agent's settings in the current directory. Everything else in
  # the settings is kept, and setting up twice changes nothing.
  module Install
    # Says what it did, in one line.
    def self.call(agent_name, local: false, base: 'HEAD')
      agent = Agents.named(agent_name)
      path = agent.settings_path(local: local)
      settings = read(path)
      return "#{path} already runs Slopbouncer. Nothing changed." if agent.installed?(settings)

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "#{JSON.pretty_generate(agent.add(settings, agent.command(base)))}\n")
      ["Added Slopbouncer to #{path}. #{agent_name} will run it when it is about to finish.",
       (agent::AFTER if agent.const_defined?(:AFTER))].compact.join("\n")
    end

    def self.read(path)
      return {} unless File.exist?(path)

      settings = JSON.parse(File.read(path))
      raise Error, "#{path} does not hold settings Slopbouncer can add to. Nothing changed." unless settings.is_a?(Hash)

      settings
    rescue JSON::ParserError
      raise Error, "#{path} could not be read as JSON. Nothing changed."
    end
    private_class_method :read
  end
end

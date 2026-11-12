# frozen_string_literal: true

require 'prism'

module Slopbouncer
  # What a piece of code parses to, with everything about how it was written
  # left out: where it sits, its white space and line breaks, a string's
  # quote style, the parentheses round a call's arguments, whether a block
  # uses braces or do and end. Two pieces of code with the same form are the
  # same code written two ways.
  module Form
    # Flags that say how something was written and not what it means:
    # total against total(), and how a string's bytes were spelled.
    WRITTEN = /\A(variable_call|ignore_visibility|frozen|mutable|forced_\w+_encoding)\?\z/

    def self.of(node)
      return unless node
      return [:name, node.name] if bare_name?(node)

      [node.type, *node.class.fields.filter_map { |field| part(node, field) }]
    end

    # A name on its own, such as basket. Whether it is a variable or a call
    # with no arguments is decided by the code round it, and so is how many
    # blocks out a variable was set. Neither is part of what was written.
    def self.bare_name?(node)
      return true if node.is_a?(Prism::LocalVariableReadNode)

      node.is_a?(Prism::CallNode) && node.receiver.nil? && node.arguments.nil? && node.block.nil?
    end

    def self.part(node, field)
      return if field.name == :depth

      case field
      when Prism::Reflection::LocationField, Prism::Reflection::OptionalLocationField then nil
      when Prism::Reflection::FlagsField then field.flags.reject { |flag| flag.match?(WRITTEN) }.select { |flag| node.public_send(flag) }
      when Prism::Reflection::NodeListField then node.public_send(field.name).map { |child| of(child) }
      when Prism::Reflection::NodeField, Prism::Reflection::OptionalNodeField then of(node.public_send(field.name))
      else node.public_send(field.name)
      end
    end
    private_class_method :bare_name?, :part
  end
end

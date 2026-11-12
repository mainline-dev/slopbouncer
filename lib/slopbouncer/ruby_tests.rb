# frozen_string_literal: true

require 'prism'

module Slopbouncer
  # Reads a Ruby test file into a table of its tests: each test's full name,
  # the assertions it makes, whether it is marked to be skipped, and its body.
  # It reads the code and never runs it.
  module RubyTests
    Test = Struct.new(:name, :assertions, :skipped, :body, keyword_init: true)
    Assertion = Struct.new(:method, :arguments, :source, keyword_init: true)

    GROUPS = %i[describe context feature].freeze
    SKIPPED_GROUPS = %i[xdescribe xcontext xfeature].freeze
    TESTS = %i[it test specify scenario example].freeze
    SKIPPED_TESTS = %i[xit xtest xspecify xscenario xexample].freeze
    SKIPS = %i[skip pending].freeze
    ASSERTION = /\A(assert|refute|must|wont)(_|\z)|\A(expect|flunk)\z/

    # helpers: the project's own method names that count as assertions.
    def self.in(source, helpers: [])
      Reader.new(helpers).read(Prism.parse(source).value)
    end

    # Walks the syntax tree, keeping the names of the groups it is inside.
    class Reader
      def initialize(helpers)
        @helpers = helpers.map(&:to_sym)
        @tests = []
        @groups = []
        @skipping = 0
      end

      def read(node)
        visit(node)
        @tests
      end

      private

      def visit(node)
        return unless node

        case node
        when Prism::ClassNode, Prism::ModuleNode then inside(node.constant_path.slice) { visit(node.body) }
        when Prism::DefNode then node.name.start_with?('test_') ? test(node.name.to_s, node.body) : visit(node.body)
        when Prism::CallNode then call(node)
        else node.compact_child_nodes.each { |child| visit(child) }
        end
      end

      def call(node)
        label = label(node)
        if !(node.block && label) then node.compact_child_nodes.each { |child| visit(child) }
        elsif GROUPS.include?(node.name) then inside(label) { visit(node.block) }
        elsif SKIPPED_GROUPS.include?(node.name) then inside(label, skipped: true) { visit(node.block) }
        elsif TESTS.include?(node.name) then test(label, node.block)
        elsif SKIPPED_TESTS.include?(node.name) then test(label, node.block, skipped: true)
        else node.compact_child_nodes.each { |child| visit(child) }
        end
      end

      # What a group or test is called: its first argument, as written.
      def label(node)
        first = node.arguments&.arguments&.first
        return unless first

        first.respond_to?(:unescaped) ? first.unescaped : first.slice
      end

      def inside(name, skipped: false)
        @groups.push(name)
        @skipping += 1 if skipped
        yield
      ensure
        @skipping -= 1 if skipped
        @groups.pop
      end

      def test(name, body, skipped: false)
        calls = calls_in(body)
        @tests << Test.new(
          name:       [*@groups, name].join(' '),
          assertions: calls.select { |call| assertion?(call) }.map { |call| assertion(call) },
          skipped:    skipped || @skipping.positive? || calls.any? { |call| call.receiver.nil? && SKIPS.include?(call.name) },
          body:       body_of(body)
        )
      end

      def calls_in(node)
        return [] unless node

        own = node.is_a?(Prism::CallNode) ? [node] : []
        own + node.compact_child_nodes.flat_map { |child| calls_in(child) }
      end

      def assertion?(call)
        call.name.match?(ASSERTION) || @helpers.include?(call.name)
      end

      def assertion(node)
        arguments = node.arguments&.arguments.to_a.map { |argument| argument.slice.split.join(' ') }
        Assertion.new(method: node.name.to_s, arguments: arguments, source: node.slice.split.join(' '))
      end

      # The lines inside a test, without its opening and closing lines.
      def body_of(node)
        inner = node.is_a?(Prism::BlockNode) ? node.body : node
        inner ? inner.slice.lines.map(&:strip).reject(&:empty?) : []
      end
    end
  end
end

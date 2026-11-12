# frozen_string_literal: true

require 'prism'
require_relative 'form'

module Slopbouncer
  # Reads a Ruby test file into a table of its tests: each test's full name,
  # the assertions it makes, whether it is marked to be skipped, and its body.
  # It reads the code and never runs it.
  module RubyTests
    # hooked: a hook in one of the test's groups makes an assertion for it.
    # form: what the body parses to, however it is written.
    Test = Struct.new(:name, :assertions, :skipped, :body, :hooked, :form, keyword_init: true)
    # arguments and source are as written, for showing. forms and form are
    # what the same things parse to, for telling whether anything changed.
    Assertion = Struct.new(:method, :arguments, :source, :forms, :form, keyword_init: true)

    GROUPS = %i[describe context feature shared_examples shared_examples_for shared_context].freeze
    SKIPPED_GROUPS = %i[xdescribe xcontext xfeature].freeze
    TESTS = %i[it test specify scenario example].freeze
    SKIPPED_TESTS = %i[xit xtest xspecify xscenario xexample].freeze
    # RSpec lets a test go without a name: it { is_expected.to be_valid }
    UNNAMED = %i[it specify].freeze
    SKIPS = %i[skip pending].freeze
    # What a group runs around each of its tests. A hook can hold the
    # assertion for all of them: after { expect(request).to have_been_made }
    HOOKS = %i[before after around].freeze
    ASSERTION = /\A(assert|refute|must|wont)(_|\z)|\A(expect|flunk)\z/
    # An RSpec expectation: expect(total).to eq(5), is_expected.not_to be_nil,
    # and the older total.should eq(5).
    SUBJECTS = %i[expect is_expected].freeze
    DIRECTIONS = %i[to not_to to_not].freeze
    SHOULDS = %i[should should_not].freeze

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
        @hooked = 0
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
        if unnamed_test?(node) then test(tidy(node.block.body || node.block), node.block)
        elsif hook?(node) then hook(node)
        elsif !(node.block && label) then node.compact_child_nodes.each { |child| visit(child) }
        elsif GROUPS.include?(node.name) then inside(label, node.block, skipped: marked_skipped?(node)) { visit(node.block) }
        elsif SKIPPED_GROUPS.include?(node.name) then inside(label, node.block, skipped: true) { visit(node.block) }
        elsif TESTS.include?(node.name) then test(label, node.block, skipped: marked_skipped?(node))
        elsif SKIPPED_TESTS.include?(node.name) then test(label, node.block, skipped: true)
        else node.compact_child_nodes.each { |child| visit(child) }
        end
      end

      # What a group or test is called: its first argument, as written, and
      # any descriptions straight after it, as in describe Basket, '#total'.
      def label(node)
        first, *rest = node.arguments&.arguments.to_a
        return unless first

        more = rest.take_while { |argument| argument.is_a?(Prism::StringNode) }
        [first, *more].map { |argument| argument.respond_to?(:unescaped) ? argument.unescaped : argument.slice }.join(' ')
      end

      # A test in a group with a body and no name. It is known by its body.
      def unnamed_test?(node)
        UNNAMED.include?(node.name) && node.receiver.nil? && node.arguments.nil? &&
          node.block.is_a?(Prism::BlockNode) && @groups.any?
      end

      # RSpec marks a group or test to be skipped beside its name:
      # it 'adds up', :skip do, or it 'adds up', pending: 'later' do.
      def marked_skipped?(node)
        node.arguments&.arguments.to_a.drop(1).any? do |argument|
          case argument
          when Prism::SymbolNode then skip_mark?(argument)
          when Prism::KeywordHashNode, Prism::HashNode then argument.elements.any? { |pair| skip_pair?(pair) }
          end
        end
      end

      def skip_mark?(node)
        node.is_a?(Prism::SymbolNode) && SKIPS.include?(node.unescaped.to_sym)
      end

      def skip_pair?(pair)
        pair.is_a?(Prism::AssocNode) && skip_mark?(pair.key) &&
          !pair.value.is_a?(Prism::FalseNode) && !pair.value.is_a?(Prism::NilNode)
      end

      def inside(name, block = nil, skipped: false)
        hooked = asserting_hook?(block)
        @groups.push(name)
        @skipping += 1 if skipped
        @hooked += 1 if hooked
        yield
      ensure
        @hooked -= 1 if hooked
        @skipping -= 1 if skipped
        @groups.pop
      end

      def hook?(node)
        hook_shape?(node) && @groups.any?
      end

      # A hook that makes assertions is read as a test of its own, so an
      # assertion it loses is flagged once and not for every test it covers.
      def hook(node)
        assertions = assertions_in(calls_in(node.block))
        return if assertions.empty?

        @tests << Test.new(name: [*@groups, "#{node.name} hook"].join(' '), assertions: assertions,
          skipped: @skipping.positive?, body: body_of(node.block), hooked: false, form: Form.of(inner(node.block)))
      end

      # Whether a group has, among its own lines, a hook that asserts.
      def asserting_hook?(block)
        lines = block.is_a?(Prism::BlockNode) && block.body.is_a?(Prism::StatementsNode) ? block.body.body : []
        lines.any? { |line| line.is_a?(Prism::CallNode) && hook_shape?(line) && assertions_in(calls_in(line.block)).any? }
      end

      def hook_shape?(node)
        HOOKS.include?(node.name) && node.receiver.nil? && node.block.is_a?(Prism::BlockNode)
      end

      def test(name, body, skipped: false)
        calls = calls_in(body)
        @tests << Test.new(
          name:       [*@groups, name].join(' '),
          assertions: assertions_in(calls),
          skipped:    skipped || @skipping.positive? || calls.any? { |call| call.receiver.nil? && SKIPS.include?(call.name) },
          body:       body_of(body),
          hooked:     @hooked.positive?,
          form:       Form.of(inner(body))
        )
      end

      def calls_in(node)
        return [] unless node

        own = node.is_a?(Prism::CallNode) ? [node] : []
        own + node.compact_child_nodes.flat_map { |child| calls_in(child) }
      end

      # The assertions among a test's calls, in the order they are written.
      # An RSpec expectation is read whole, so the expect inside it is not
      # counted a second time.
      def assertions_in(calls)
        expectations = calls.select { |call| expectation?(call) }
        inside = expectations.map(&:receiver)
        plain = calls.select { |call| assertion?(call) && inside.none? { |subject| subject.equal?(call) } }
        (expectations + plain).sort_by { |call| call.location.start_offset }
                              .map { |call| expectation?(call) ? expectation(call) : assertion(call) }
      end

      def assertion?(call)
        call.name.match?(ASSERTION) || @helpers.include?(call.name)
      end

      def assertion(node)
        made(node, node.name.to_s, node.arguments&.arguments.to_a)
      end

      def expectation?(call)
        return !call.arguments.nil? if SHOULDS.include?(call.name)

        subject = call.receiver
        DIRECTIONS.include?(call.name) && subject.is_a?(Prism::CallNode) &&
          SUBJECTS.include?(subject.name) && subject.receiver.nil?
      end

      # An expectation as an assertion: what it is about, then what the
      # matcher expects. A plain matcher such as eq(5) gives its own
      # arguments, so an edited value shows as 5 → 6. A matcher built from
      # several calls, such as change { total }.by(1), is taken whole.
      def expectation(node)
        matcher = node.arguments&.arguments&.first
        plain = matcher.is_a?(Prism::CallNode) && matcher.receiver.nil? && matcher.block.nil?
        expected = plain ? matcher.arguments&.arguments.to_a : [matcher].compact
        made(node, [(node.receiver.name if about_a_subject?(node)), node.name, (matcher.name if plain)].compact.join(' '),
          subject_of(node) + expected)
      end

      def made(node, method, parts)
        Assertion.new(method: method, arguments: parts.map { |part| tidy(part) }, source: tidy(node),
          forms: parts.map { |part| Form.of(part) }, form: Form.of(node))
      end

      def about_a_subject?(node)
        DIRECTIONS.include?(node.name)
      end

      # What an expectation is about: expect's arguments or block, or what
      # should was called on.
      def subject_of(node)
        subject = node.receiver
        return [subject].compact unless about_a_subject?(node)

        [*subject.arguments&.arguments.to_a, subject.block].compact
      end

      def tidy(node)
        node.slice.split.join(' ')
      end

      # The lines inside a test, without its opening and closing lines.
      def body_of(node)
        inner = inner(node)
        inner ? inner.slice.lines.map(&:strip).reject(&:empty?) : []
      end

      def inner(node)
        node.is_a?(Prism::BlockNode) ? node.body : node
      end
    end
  end
end

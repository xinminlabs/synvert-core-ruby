# frozen_string_literal: true

module Synvert::Core
  # WrapAction to warp node within a block, class or module.
  class Rewriter::WrapAction < Rewriter::Action
    def initialize(instance, with:, indent: nil)
      @instance = instance
      @code = with
      @node = @instance.current_node
      @indent = indent || @node.indent
    end

    # Begin position of code to wrap.
    #
    # @return [Integer] begin position.
    def begin_pos
      @node.loc.expression.begin_pos
    end

    # End position of code to wrap.
    #
    # @return [Integer] end position.
    def end_pos
      @node.loc.expression.end_pos
    end

    # The rewritten source code.
    #
    # @return [String] rewritten code.
    def rewritten_code
      "#{@code}\n#{' ' * @indent}" +
      @node.to_source.split("\n").map { |line| "  #{line}" }.join("\n") +
      "\n#{' ' * @indent}end"
    end
  end
end

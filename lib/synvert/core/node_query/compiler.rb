# frozen_string_literal: true

module Synvert::Core::NodeQuery
  class Compiler
    class InvalidOperator < StandardError; end

    module Comparable
      SIMPLE_VALID_OPERATORS = [:==, :!=, :includes]
      NUMBER_VALID_OPERATORS = [:==, :!=, :>, :>=, :<, :<=, :includes]
      ARRAY_VALID_OPERATORS = [:==, :!=, :in, :not_in]
      REGEXP_VALID_OPERATORS = [:=~, :!~]

      def match?(node, operator)
        raise InvalidOperator, "invalid operator #{operator}" unless valid_operator?(operator)

        case operator
        when :!=
          if expected_value.is_a?(Array)
            actual = actual_value(node)
            !actual.is_a?(Array) || actual.size != expected_value.size ||
              actual.zip(expected_value).any? { |actual_node, expected_node| expected_node.match?(actual_node, :!=) }
          else
            actual_value(node) != expected_value
          end
        when :=~
          actual_value(node) =~ expected_value
        when :!~
          actual_value(node) !~ expected_value
        when :>
          actual_value(node) > expected_value
        when :>=
          actual_value(node) >= expected_value
        when :<
          actual_value(node) < expected_value
        when :<=
          actual_value(node) <= expected_value
        when :in
          expected_value.any? { |expected| expected.match?(node, :==) }
        when :not_in
          expected_value.all? { |expected| expected.match?(node, :!=) }
        when :includes
          actual_value(node).any? { |actual| actual == expected_value }
        else
          if expected_value.is_a?(Array)
            actual = actual_value(node)
            actual.is_a?(Array) && actual.size == expected_value.size &&
              actual.zip(expected_value).all? { |actual_node, expected_node| expected_node.match?(actual_node, :==) }
          else
            actual_value(node) == expected_value
          end
        end
      end

      def actual_value(node)
        if node.is_a?(::Parser::AST::Node)
          node.to_value
        else
          node
        end
      end

      def expected_value
        @value
      end

      def valid_operator?(operator)
        valid_operators.include?(operator)
      end
    end

    class Expression
      def initialize(selector: nil, expression: nil, relationship: nil)
        @selector = selector
        @expression = expression
        @relationship = relationship
      end

      def filter(nodes)
        @selector.filter(nodes)
      end

      def match?(node)
        !query_nodes(node).empty?
      end

      # If @relationship is nil, it will match in all recursive child nodes and return matching nodes.
      # If @relationship is :decendant, it will match in all recursive child nodes.
      # If @relationship is :child, it will match in direct child nodes.
      # If @relationship is :next_sibling, it try to match next sibling node.
      # If @relationship is :subsequent_sibling, it will match in all sibling nodes.
      # @param node [Parser::AST::Node] node to match
      # @param descendant_match [Boolean] whether to match in descendant nodes, default is true
      def query_nodes(node, descendant_match = true)
        matching_nodes =  find_nodes_without_relationship(node, descendant_match)
        if @relationship.nil?
          return matching_nodes
        end

        expression_nodes = matching_nodes.map do |matching_node|
          case @relationship
          when :descendant
            nodes = []
            matching_node.recursive_children { |child_node| nodes += @expression.query_nodes(child_node, false) }
            nodes
          when :child
            matching_node.children.map { |child_node| @expression.query_nodes(child_node, false) }.flatten
          when :next_sibling
            @expression.query_nodes(matching_node.siblings.first, false)
          when :subsequent_sibling
            matching_node.siblings.map { |sibling_node| @expression.query_nodes(sibling_node, false) }.flatten
          end
        end.flatten
      end

      def to_s
        return @selector.to_s unless @expression

        result = []
        result << @selector if @selector
        case @relationship
        when :child then result << '>'
        when :subsequent_sibling then result << '~'
        when :next_sibling then result << '+'
        end
        result << @expression
        result.map(&:to_s).join(' ')
      end

      private

      def find_nodes_without_relationship(node, descendant_match)
        return [node] unless @selector

        nodes = []
        nodes << node if @selector.match?(node)
        if descendant_match
          node.recursive_children do |child_node|
            nodes << child_node if @selector.match?(child_node)
          end
        end
        filter(nodes)
      end
    end

    class Selector
      def initialize(node_type: nil, attribute_list: nil, index: nil, has_expression: nil)
        @node_type = node_type
        @attribute_list = attribute_list
        @index = index
        @has_expression = has_expression
      end

      def filter(nodes)
        return nodes if @index.nil?

        nodes[@index] ? [nodes[@index]] : []
      end

      def match?(node, operator = :==)
        (!@node_type || (node.is_a?(::Parser::AST::Node) && @node_type.to_sym == node.type)) &&
        (!@attribute_list || @attribute_list.match?(node, operator)) &&
        (!@has_expression || @has_expression.match?(node))
      end

      def to_s
        str = ".#{@node_type}#{@attribute_list}"
        return str if !@index && !@has_expression

        return "#{str}:has(#{@has_expression.to_s})" if @has_expression

        case @index
        when 0
          str + ':first-child'
        when -1
          str + ':last-child'
        when (1..)
          str + ":nth-child(#{@index + 1})"
        when (...-1)
          str + ":nth-last-child(#{-@index})"
        else
          str
        end
      end
    end

    class AttributeList
      def initialize(attribute:, attribute_list: nil)
        @attribute = attribute
        @attribute_list = attribute_list
      end

      def match?(node, operator = :==)
        @attribute.match?(node, operator) && (!@attribute_list || @attribute_list.match?(node, operator))
      end

      def to_s
        "[#{@attribute}]#{@attribute_list}"
      end
    end

    class Attribute
      def initialize(key:, value:, operator: :==)
        @key = key
        @value = value
        @operator = operator
      end

      def match?(node, operator = :==)
        @value.base_node = node if @value.is_a?(AttributeValue)
        node && @value.match?(node.child_node_by_name(@key), @operator)
      end

      def to_s
        case @operator
        when :!=
          "#{@key}!=#{@value}"
        when :=~
          "#{@key}=~#{@value}"
        when :!~
          "#{@key}!~#{@value}"
        when :>
          "#{@key}>#{@value}"
        when :>=
          "#{@key}>=#{@value}"
        when :<
          "#{@key}<#{@value}"
        when :<=
          "#{@key}<=#{@value}"
        when :in
          "#{@key} in (#{@value})"
        when :not_in
          "#{@key} not in (#{@value})"
        when :includes
          "#{@key} includes #{@value}"
        else
          "#{@key}=#{@value}"
        end
      end
    end

    class ArrayValue
      include Comparable

      def initialize(value: nil, rest: nil)
        @value = value
        @rest = rest
      end

      def expected_value
        expected = []
        expected.push(@value) if @value
        expected += @rest.expected_value if @rest
        expected
      end

      def valid_operators
        ARRAY_VALID_OPERATORS
      end

      def to_s
        [@value, @rest].compact.join(', ')
      end
    end

    class AttributeValue
      include Comparable

      attr_accessor :base_node

      def initialize(value:)
        @value = value
      end

      def actual_value(node)
        if node.is_a?(::Parser::AST::Node)
          node.to_source
        else
          node
        end
      end

      def expected_value
        node = base_node.child_node_by_name(@value)
        if node.is_a?(::Parser::AST::Node)
          node.to_source
        else
          node
        end
      end

      def valid_operators
        SIMPLE_VALID_OPERATORS
      end

      def to_s
        "{{#{@value}}}"
      end
    end

    class Boolean
      include Comparable

      def initialize(value:)
        @value = value
      end

      def to_s
        @value.to_s
      end

      def valid_operators
        SIMPLE_VALID_OPERATORS
      end
    end

    class Float
      include Comparable

      def initialize(value:)
        @value = value
      end

      def valid_operators
        NUMBER_VALID_OPERATORS
      end

      def to_s
        @value.to_s
      end
    end

    class Integer
      include Comparable

      def initialize(value:)
        @value = value
      end

      def valid_operators
        NUMBER_VALID_OPERATORS
      end

      def to_s
        @value.to_s
      end
    end

    class Nil
      include Comparable

      def initialize(value:)
        @value = value
      end

      def valid_operators
        SIMPLE_VALID_OPERATORS
      end

      def to_s
        'nil'
      end
    end

    class Regexp
      include Comparable

      def initialize(value:)
        @value = value
      end

      def match?(node, operator)
        if node.is_a?(::Parser::AST::Node)
          @value.match(node.to_source)
        else
          @value.match(node.to_s)
        end
      end

      def valid_operators
        REGEXP_VALID_OPERATORS
      end

      def to_s
        @value.to_s
      end
    end

    class String
      include Comparable

      def initialize(value:)
        @value = value
      end

      def valid_operators
        SIMPLE_VALID_OPERATORS
      end

      def actual_value(node)
        if node.is_a?(::Parser::AST::Node)
          node.to_source
        else
          node.to_s
        end
      end

      def to_s
        "\"#{@value}\""
      end
    end

    # Symbol node represents a symbol value.
    class Symbol
      include Comparable

      def initialize(value:)
        @value = value
      end

      def valid_operators
        SIMPLE_VALID_OPERATORS
      end

      def to_s
        ":#{@value}"
      end
    end

    class Identifier
      include Comparable

      def initialize(value:)
        @value = value
      end

      def actual_value(node)
        if node.is_a?(::Parser::AST::Node)
          node.to_source
        elsif node.is_a?(Array)
          node.map { |n| actual_value(n) }
        else
          node.to_s
        end
      end

      def valid_operators
        SIMPLE_VALID_OPERATORS
      end

      def to_s
        @value
      end
    end
  end
end
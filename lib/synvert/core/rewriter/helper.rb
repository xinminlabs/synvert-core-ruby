# frozen_string_literal: true

module Synvert::Core
  # Rewriter::Helper provides some helper methods to make it easier to write a snippet.
  module Rewriter::Helper
    # Add receiver to code if necessary.
    #
    # @param code [String] old code
    # @return [String] new code
    #
    # @example
    #
    #   add_receiver_if_necessary("{{message}} {{arguments}}")
    #
    #   if current_node doesn't have a receiver, it returns "{{message}} {{arguments}}"
    #   if current_node has a receiver, it returns "{{receiver}}.{{message}} {{arguments}}"
    def add_receiver_if_necessary(code)
      if node.receiver
        "{{receiver}}.#{code}"
      else
        code
      end
    end

    # Add arguments with parenthesis if necessary.
    #
    # @return [String] return (!{{arguments}}) if node.arguments present, otherwise return nothing.
    #
    # @example
    #
    #   add_arguments_with_parenthesis_if_necessary
    #
    #   if current_node doesn't have an argument, it returns ""
    #   if current_node has argument, it returns "({{arguments}})"
    def add_arguments_with_parenthesis_if_necessary
      if node.arguments.size > 0
        '({{arguments}})'
      else
        ''
      end
    end

    # Add curly brackets to code if necessary.
    #
    # @param code [String] old code
    # @return [String] new code
    #
    # @example
    #
    #   add_curly_brackets_if_necessary("{{arguments}}")
    def add_curly_brackets_if_necessary(code)
      if code.start_with?('{') && code.end_with?('}')
        code
      else
        "{ #{code} }"
      end
    end

    # Remove leading and trailing brackets.
    #
    # @param code [String] old code
    # @return [String] new code
    #
    # @example
    #
    #   strip_brackets("(1..100)") #=> "1..100"
    def strip_brackets(code)
      code.sub(/^\((.*)\)$/) { Regexp.last_match(1) }
          .sub(/^\[(.*)\]$/) { Regexp.last_match(1) }
          .sub(/^{(.*)}$/) {
        Regexp.last_match(1).strip
      }
    end

    # Reject some keys from hash node.
    #
    # @param hash_node [Parser::AST::Node]
    # @param keys [Array<String, Symbol>] keys should be rejected from the hash.
    # @return [String] source of of the hash node after rejecting some keys.
    #
    # @example
    #
    #   hash_node = Parser::CurrentRuby.parse("{ key1: 'value1', key2: 'value2' }")
    #   reject_keys_from_hash(hash_node, :key1) => "key2: 'value2'"
    def reject_keys_from_hash(hash_node, *keys)
      hash_node.children.reject { |pair_node| keys.include?(pair_node.key.to_value) }
               .map(&:to_source).join(', ')
    end
  end
end

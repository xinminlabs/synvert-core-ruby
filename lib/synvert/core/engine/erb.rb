# frozen_string_literal: true

module Synvert::Core
  module Engine
    class Erb
      class << self
        # Encode erb string, leave only ruby code, replace other erb code with whitespace.
        #
        # @param source [String] erb code.
        # @return [String] encoded ruby code.
        def encode(source)
          source.gsub(/%>.*?<%=?/m) { |str| replace_all_code_but_white_space_characters(str) }
                .sub(/^.*?<%=?/m) { |str| replace_all_code_but_white_space_characters(str) }
                .sub(/%>.*?$/m) { |str| replace_all_code_but_white_space_characters(str) }
        end

        private

        def replace_all_code_but_white_space_characters(source)
          source.gsub(/\S/, ' ')
        end
      end
    end
  end
end

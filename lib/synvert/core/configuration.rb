# frozen_string_literal: true

module Synvert::Core
  # Synvert global configuration.
  class Configuration
    class << self
      # @!attribute [w] root_path
      # @!attribute [w] skip_paths
      # @!attribute [w] only_paths
      # @!attribute [w] respect_gitignore
      # @!attribute [w] show_run_process
      # @!attribute [w] number_of_workers
      # @!attribute [w] single_quote
      # @!attribute [w] tab_width
      # @!attribute [w] strict, if strict is false, it will ignore ruby version and gem version check.
      # @!attribute [w] test_result, default is 'actions', it can be 'actions' or 'new_source'.
      attr_writer :root_path,
                  :skip_paths,
                  :only_paths,
                  :respect_gitignore,
                  :show_run_process,
                  :number_of_workers,
                  :single_quote,
                  :tab_width,
                  :strict,
                  :test_result

      # Get the path.
      #
      # @return [String] default is '.'
      def root_path
        @root_path || '.'
      end

      # Get a list of skip paths.
      #
      # @return [Array<String>] default is [].
      def skip_paths
        @skip_paths || []
      end

      # Get a list of only paths.
      #
      # @return [Array<String>] default is [].
      def only_paths
        @only_paths || []
      end

      # Check if respect .gitignore
      #
      # @return [Boolean] default is true
      def respect_gitignore
        @respect_gitignore.nil? ? true : @respect_gitignore
      end

      # Check if show run process.
      #
      # @return [Boolean] default is false
      def show_run_process
        @show_run_process || false
      end

      # Number of workers
      #
      # @return [Integer] default is 1
      def number_of_workers
        @number_of_workers || 1
      end

      # Use single quote or double quote.
      #
      # @return [Boolean] true if use single quote, default is true
      def single_quote
        @single_quote.nil? ? true : @single_quote
      end

      # Returns the tab width used for indentation.
      #
      # If the tab width is not explicitly set, it defaults to 2.
      #
      # @return [Integer] The tab width.
      def tab_width
        @tab_width || 2
      end

      # Returns the value of the strict flag.
      #
      # If the strict flag is not set, it returns true by default.
      #
      # @return [Boolean] the value of the strict flag
      def strict
        @strict.nil? ? true : @strict
      end

      # Returns the value of the test_result flag.
      #
      # If the test_result flag is not set, it returns 'actions' by default.
      #
      # @return [String] the value of the test_result flag
      def test_result
        @test_result || 'actions'
      end

      # Temporarily sets the specified configurations, executes the given block, and then restores the original configurations.
      #
      # @param configurations [Hash] The configurations to be set temporarily.
      # @yield The block of code to be executed.
      #
      # @example
      #   with_temporary_configurations({ number_of_workers: 1 }) do
      #     # Code to be executed with temporary configurations
      #   end
      def with_temporary_configurations(configurations, &block)
        old_instance_variables =
          instance_variables.reduce({}) do |hash, var|
            hash[var] = instance_variable_get(var)
            hash
          end

        configurations.each do |variable, value|
          instance_variable_set("@#{variable}", value)
        end

        block.call

        old_instance_variables.each do |var, value|
          instance_variable_set(var, value)
        end
      end
    end
  end
end
